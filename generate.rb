require 'optparse'
require 'json'
require 'set'
require 'active_record'
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

bound = {}

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
#include <mruby/class.h>
#include <mruby/numeric.h>
#include <mruby/string.h>
#include <mruby/compile.h>
#include <stdlib.h>
}
defines = ""
init_body = ""
standard_types = ['bool', 'int', 'float', 'double', 'float', 'const char *', 'unsigned int', 'void']

# for displaying statistics
glue.first.each do |func, params|
  if (func.rpartition(' ').first == 'void') && (params[0] == 'void')
    $phase1[func] = params
  elsif (standard_types.include? func.rpartition(' ').first) && (params[0] == 'void')
    $phase2[func] = params
  else
    no_struct_param = true
    params.each do |param|
      if !(standard_types.include? param.rpartition(' ').first)
        no_struct_param = false
        break
      end
    end
    if no_struct_param
      if standard_types.include? func.rpartition(' ').first
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

# generates functions
glue.first.each do |func, params|
  # func = function name with return type
  # func_datatype = function return type
  # func_name = function name
  # params = array of params with their data types(void means none)
  rpart = func.rpartition(' ')
  func_datatype = rpart.first
  func_name = rpart.last

  # if phase 1
  if func_datatype == 'void' && params[0] == 'void'
    body = Tplt.return_format(func, params) #"#{func_name}();\nreturn mrb_nil_value();"
    #defines += 'PHASE 1\n'
    defines += Tplt.function(func_name, body)
    init_body += Tplt.init_module_function('test', Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_NONE()")

    bound[func] = params
    debug_mark_binding(func, params)
    # if phase 2
  elsif (standard_types.include? func_datatype) && (params[0] == 'void')
    body = Tplt.return_format(func, params) 
    #defines += 'PHASE 2\n'
    defines += Tplt.function(func_name, body)
    init_body += Tplt.init_module_function('test', Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_NONE()")

    bound[func] = params
    debug_mark_binding(func, params)
  elsif standard_types.include? func_datatype # accept params
    # detecting if there is no struct param(wont need this in the future)
    no_struct_param = true
    params.each do |param|
      if !(standard_types.include? param.rpartition(' ').first)
        no_struct_param = false
        break
      end
    end
    if no_struct_param
      if standard_types.include? func.rpartition(' ').first
        #$phase3[func] = params
        # ---
        #body = ''
        body = Tplt.return_format(func, params) 
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
        body = Tplt.get_kwargs(params.length, init_var_body, init_array_body)
        body += unwrapped_kwargs
        body += Tplt.return_format(func, params)
        defines += Tplt.function(func_name, body)
        init_body += Tplt.init_module_function('test', Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_OPT(1)") # opt stuff isnt correct, need to look at this again
        # ---
        #puts func
        bound[func] = params
        debug_mark_binding(func, params)
      else
        #$phase4[func] = params
      end
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
