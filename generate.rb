require 'optparse'
require 'json'
require 'active_record' # use to make strings to snake_case. probably overkill
require_relative './templates.rb'

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: example.rb [options]"

  parser.on("-gGLUE", "--glue=GLUE", "Path to file(defaults to ./glue.rb)") do |glue|
    options[:glue] = glue
  end

  parser.on('-cCONFIG', '--config=CONFIG', 'Path to config file') do |config|
    options[:config] = config
  end
end.parse!

options[:glue] ||= './glue.json'
glue = JSON.parse(File.read(options[:glue]))

# configuration
Tplt.treated_as_int |= ['unsigned char']

$phase1 = {}
$phase2 = {}
$phase3 = {}
$phase4 = {}
$phase5 = {}
$complete_phase1 = {}
$complete_phase2 = {}
$complete_phase3 = {}
$complete_phase4 = {}
$complete_phase5 = {}

result = ""
includes = %{
#include <raylib.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/data.h>
#include <mruby/class.h>
#include <mruby/numeric.h>
#include <mruby/string.h>
#include <mruby/compile.h>
#include <stdlib.h>
}
defines = ""
init_body = ""


# convert types
# TODO need to make this built in
# functionality(with scanner + generator)
glue.first.keys.each do |k|
  rpart = k.rpartition(' ')

  #glue.first[ mappings[k] ] = glue.first.delete(k) if mappings[k]
  if 'Texture2D' == rpart.first
    glue.first["Texture #{rpart.last}"] = glue.first.delete(k)
  elsif 'RenderTexture2D' == rpart.first
    glue.first["RenderTexture #{rpart.last}"] = glue.first.delete(k)
  end
end

# for displaying statistics
glue.first.each do |func, params|
  if (func.rpartition(' ').first == 'void') && (params[0] == 'void')
    $phase1[func] = params
  elsif (Tplt.non_struct_types.include? func.rpartition(' ').first) && (params[0] == 'void')
    $phase2[func] = params
  else
    no_struct_param = true
    params.each do |param|
      if !(Tplt.non_struct_types.include? param.rpartition(' ').first)
        no_struct_param = false
        break
      end
    end
    if no_struct_param
      if Tplt.non_struct_types.include? func.rpartition(' ').first
        $phase3[func] = params
      else
        $phase4[func] = params
      end
    else
      $phase5[func] = params
    end
  end
end

# also for display statistics
def debug_mark_binding(func, params)
  if $phase1.include? func
    $complete_phase1[func] = params
  elsif $phase2.include? func
    $complete_phase2[func] = params
  elsif $phase3.include? func
    $complete_phase3[func] = params
  elsif $phase4.include? func
    $complete_phase4[func] = params
  elsif $phase5.include? func
    $complete_phase5[func] = params
  end
end


# generates structs
# TODO
# Auto generate struct accessors
#
glue.last.each do |struct, params|
  defines += Tplt.init_struct_wrapper(struct)
  init_body += Tplt.init_class(struct, 'test')

  params.each do |param|
    #puts param
  end
end

# generates functions
glue.first.each do |func, params|
  # func = function name with return type
  # func_datatype = function return type
  # func_name = function name
  # params = array of params with their data types(void means none)
  rpart = func.rpartition(' ')
  func_datatype = rpart.first
  func_name = rpart.last

  # TODO: just treat longs and shorts as ints
  #
  # since void * can be anything just skip functions
  # (by default) that use it
  next if ['void *'].include? func_datatype


  # if phase 1 or 2
  if (func_datatype == 'void' && params[0] == 'void') || ((Tplt.non_struct_types.include? func_datatype) && (params[0] == 'void'))
    body = Tplt.return_format(func, params)
    #defines += 'PHASE 1\n'
    defines += "\n//#{func}"
    defines += Tplt.function(func_name, body)
    init_body += Tplt.init_module_function('test', Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_NONE()")

    debug_mark_binding(func, params)
  else Tplt.non_struct_types.include? func_datatype # accept params
    # detecting if there is no struct param(wont need this in the future)
    no_struct_param = true
    params.each do |param|
      if !(Tplt.non_struct_types.include? param.rpartition(' ').first)
        no_struct_param = false
        break
      end
    end
    if no_struct_param
      #if true# Tplt.non_struct_types.include? func.rpartition(' ').first
      #$phase3[func] = params
      # ---
      body = ''
      #body = Tplt.return_format(func, params) 
      init_var_body = ''
      init_array_body = ''
      unwrapped_kwargs = ''
      params.each_with_index do |param, index|
        temp = param
        temp_rpart = temp.rpartition(' ')
        if temp_rpart.first == 'const char *'
          temp = 'char *' + temp_rpart.last
        end
        init_var_body += temp + ";\n"
        init_array_body += "mrb_intern_lit(mrb, \"#{temp_rpart.last}\"),\n"
        unwrapped_kwargs += Tplt.unwrap_kwarg(index, "#{temp_rpart.last} = #{Tplt.to_c(temp_rpart.first, "kw_values[#{index}]")};", nil, "#{temp_rpart.last} Argument Missing")
      end

      # if return isnt regular types, add struct to init
      unless Tplt.non_struct_types.include? func_datatype
        init_var_body += "#{func_datatype} *return_value = {0};\n"
      end

      body = Tplt.get_kwargs(params.length, init_var_body, init_array_body)
      body += unwrapped_kwargs

      # if return isnt regular types, use struct return format
      if Tplt.non_struct_types.include? func_datatype
        body += Tplt.return_format(func, params)
      else
        body += Tplt.get_module('Test')
        body += Tplt.get_class(func_datatype, 'test')
        body += Tplt.return_format_struct(func)
      end

      defines += "\n//#{func}"
      defines += Tplt.function(func_name, body)
      init_body += Tplt.init_module_function('test', Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_OPT(1)") # opt stuff isnt correct, need to look at this again
      # ---
      #puts func
      debug_mark_binding(func, params)
      #end
    else
      #$phase5[func] = params
    end
  end
end

init_body.prepend(Tplt.define_module('Test'))

result = %{
#{includes}
#{defines}
#{Tplt.base('test', init_body, nil)}
}

result += "//Bound Functions: #{$complete_phase1.length + $complete_phase2.length + $complete_phase3.length + $complete_phase4.length + $complete_phase5.length} / #{$phase1.length + $phase2.length + $phase3.length + $phase4.length + $phase5.length}\n//---\n"

result += "//Phase 1 Functions: #{$complete_phase1.length} / #{$phase1.length}\n"
result += "//Phase 2 Functions: #{$complete_phase2.length} / #{$phase2.length}\n"
result += "//Phase 3 Functions: #{$complete_phase3.length} / #{$phase3.length}\n"
result += "//Phase 4 Functions: #{$complete_phase4.length} / #{$phase4.length}\n"
result += "//Phase 5 Functions: #{$complete_phase5.length} / #{$phase5.length}\n"


puts result

#$phase4.reverse_each do |key, elem|
#  puts '---'
#  puts key
#  pp elem
#end
