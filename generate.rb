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
LibraryName = 'Test'

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


$all_params = []
$bound_params = []
# generates structs, accessors, and initializers
glue.last.each do |struct, params|
  defines += Tplt.init_struct_wrapper(struct)
  init_body += Tplt.init_class(struct, LibraryName.downcase)

  init_vars = ''

  params.each do |param|
    $all_params.push param
    rpart = param.rpartition(' ')
    param_datatype = rpart.first
    param_name = rpart.last

    next unless Tplt.non_struct_types.include? param_datatype
    $bound_params.push param

    # getter
    # take no params
    # unwrap struct
    # return(using correct type conversion)
    body = Tplt.unwrap_struct("#{struct} *struct_#{struct.downcase}", 'self', "mrb_#{struct}_struct", struct)
    body += "return #{Tplt.to_mrb(param_datatype, "struct_#{struct.downcase}->#{param_name}")};\n"
    defines += Tplt.function("#{struct}_get_#{param_name}", body)
    init_body += Tplt.init_function("#{struct.downcase}_class", param_name, "#{struct}_get_#{param_name}", "MRB_ARGS_NONE()")

    # setter
    # init var of correct type
    # take 1 arg param
    # unwrap struct
    # set value in struct
    # return same value
    body = Tplt.get_args({ "#{param_name}": "#{param_datatype}" })
    body += Tplt.unwrap_struct("#{struct} *struct_#{struct.downcase}", 'self', "mrb_#{struct}_struct", struct)
    body += "struct_#{struct.downcase}->#{param_name} = #{param_name};\n"
    body += "return #{Tplt.to_mrb(param_datatype, param_name)};\n"
    defines += Tplt.function("#{struct}_set_#{param_name}", body)
    init_body += Tplt.init_function("#{struct.downcase}_class", "#{param_name}=", "#{struct}_set_#{param_name}", "MRB_ARGS_REQ(1)")


  end

  # initializer
  # init the struct(using mrb to allocate)
  # get values
  # assign values to struct
  # wrap struct
  # return self
  body = ''
  body += Tplt.get_module(LibraryName)
  body += Tplt.get_class(struct, LibraryName.downcase)
  body += "#{struct} *wrapped_value = (#{struct} *)mrb_malloc(mrb, sizeof(#{struct}));\n"
  #body += "*wrapped_value = {0};\n" #{func_name}("

  init_array_body = ''
  unwrapped_kwargs = ''
  params.each_with_index do |param, index|
    temp = param
    temp_rpart = temp.rpartition(' ')
    #if temp_rpart.first == 'const char *'
    #  temp = 'char *' + temp_rpart.last
    #end
    #init_var_body += temp + ";\n"
    init_array_body += "mrb_intern_lit(mrb, \"#{temp_rpart.last}\"),\n"
    #unwrapped_kwargs += Tplt.unwrap_kwarg(index, "#{temp_rpart.last} = #{Tplt.to_c(temp_rpart.first, "kw_values[#{index}]")};", nil, "#{temp_rpart.last} Argument Missing")
    if Tplt.non_struct_types.include? temp_rpart.first
      unwrapped_kwargs += Tplt.unwrap_kwarg(index, "wrapped_value->#{temp_rpart.last} = #{Tplt.to_c(temp_rpart.first, "kw_values[#{index}]")};\n")
    else
      # this is for structs or "undetermined" types
      # doesnt work yet
      next
      #unwrapped_kwargs += Tplt.unwrap_kwarg(index, "wrapped_value->#{temp_rpart.last} = (#{temp_rpart.first})kw_values[#{index}];\n")
    end
  end
  body += Tplt.get_kwargs(params.length, '', init_array_body)
  body += unwrapped_kwargs

  body += "mrb_data_init(self, wrapped_value, &mrb_#{struct}_struct);\n"
  body += 'return self;'
  defines += Tplt.function("#{struct}_initialize", body)
  init_body += Tplt.init_function("#{struct.downcase}_class", "initialize", "#{struct}_initialize", "MRB_ARGS_OPT(1)")


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

  # since void * can be anything just skip functions
  # (by default) that use it
  next if ['void *'].include? func_datatype

  body = ''

  body += Template::C.initialize_variables(params, glue.last)
  #TODO CONTINUE HERE

  # if phase 1 or 2
  if (func_datatype == 'void' && params[0] == 'void') || ((Tplt.non_struct_types.include? func_datatype) && (params[0] == 'void'))
    body = Tplt.return_format(func, params)
    #defines += 'PHASE 1\n'
    defines += "\n//#{func}"
    defines += Tplt.function(func_name, body)
    init_body += Tplt.init_module_function(LibraryName.downcase, Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_NONE()")

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
        #init_var_body += "#{func_datatype} *wrapped_value = {0};\n"
      end

      body = Tplt.get_kwargs(params.length, init_var_body, init_array_body)
      body += unwrapped_kwargs

      # if return isnt regular types, use struct return format
      if Tplt.non_struct_types.include? func_datatype
        body += Tplt.return_format(func, params)
      else
        body += Tplt.get_module(LibraryName)
        body += Tplt.get_class(func_datatype, LibraryName.downcase)
        body += "#{func_datatype} *wrapped_value = (#{func_datatype} *)mrb_malloc(mrb, sizeof(#{func_datatype}));\n"
        body += "*wrapped_value = #{func_name}("
        params.each do |param|
          temp_rpart = param.rpartition(' ')
          body += "#{temp_rpart.last}, "
        end
        body.delete_suffix!(', ')
        body += ");\n"
        body += "return mrb_obj_value(Data_Wrap_Struct(mrb, #{func_datatype.downcase}_mrb_class, &mrb_#{func_datatype}_struct, wrapped_value));"
      end

      defines += "\n//#{func}"
      defines += Tplt.function(func_name, body)
      init_body += Tplt.init_module_function(LibraryName.downcase, Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_OPT(1)") # opt stuff isnt correct, need to look at this again
      # ---
      #puts func
      debug_mark_binding(func, params)
      #end
    else
      #$phase5[func] = params
    end
  end
end

init_body.prepend(Tplt.define_module(LibraryName))

result = %{
#{includes}
#{defines}
#{Tplt.base(LibraryName.downcase, init_body, nil)}
}

result += "//Bound Functions: #{$complete_phase1.length + $complete_phase2.length + $complete_phase3.length + $complete_phase4.length + $complete_phase5.length} / #{$phase1.length + $phase2.length + $phase3.length + $phase4.length + $phase5.length}\n//---\n"

result += "//Phase 1 Functions: #{$complete_phase1.length} / #{$phase1.length}\n"
result += "//Phase 2 Functions: #{$complete_phase2.length} / #{$phase2.length}\n"
result += "//Phase 3 Functions: #{$complete_phase3.length} / #{$phase3.length}\n"
result += "//Phase 4 Functions: #{$complete_phase4.length} / #{$phase4.length}\n"
result += "//Phase 5 Functions: #{$complete_phase5.length} / #{$phase5.length}\n"
result += "\n"
result += "//Struct Accessors: #{$bound_params.length} / #{$all_params.length}\n"


puts result

#$phase4.reverse_each do |key, elem|
#  puts '---'
#  puts key
#  pp elem
#end
