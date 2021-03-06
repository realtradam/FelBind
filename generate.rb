#require 'optparse'
require 'json'
require 'active_record' # use to make strings to snake_case. probably overkill
require_relative './templates.rb'
LibraryName = 'Test'

class Generate
  class << self
=begin
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
=end
    def generate(file, destination)
      glue = JSON.parse(File.read(file))

      # configuration
      #Template.treated_as_int |= ['unsigned char']

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

      $result = ""
      $includes = %{
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


      $defines = ""
      $init_body = ""
      Template.parse_struct_types(glue.last)


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

      glue.first.each do |params|
        params[1].map! do |param|
          rpart = param.rpartition(' ')

          if ['Texture2D'].include? rpart.first
            "Texture #{rpart.last}"
          elsif ['RenderTexture2D'].include? rpart.first
            "RenderTexture #{rpart.last}"
          else
            param
          end
        end
      end
      # for displaying statistics
      glue.first.each do |func, params|
        if (func.rpartition(' ').first == 'void') && (params[0] == 'void')
          $phase1[func] = params
        elsif (Template.non_struct_types =~ func.rpartition(' ').first) && (params[0] == 'void')
          $phase2[func] = params
        else
          no_struct_param = true
          params.each do |param|
            if !(Template.non_struct_types =~ param.rpartition(' ').first)
              no_struct_param = false
              break
            end
          end
          if no_struct_param
            if Template.non_struct_types =~ func.rpartition(' ').first
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
        $defines += Template.init_struct_wrapper(struct)
        $init_body += Template.init_class(struct, LibraryName.downcase)
        init_vars = ''

        params.each do |param|
          $all_params.push param
          param_datatype, _space, param_name = param.rpartition(' ')

          #next unless Template.non_struct_types =~ param_datatype

          # getter
          # take no params
          # unwrap struct
          # return(using correct type conversion)
          body = Template.unwrap_struct("#{struct} *struct_#{struct.downcase}", 'self', "mrb_#{struct}_struct", struct)

          # if non struct
          if Template.non_struct_types_all =~ param_datatype
            $bound_params.push param
            if Template.non_struct_types =~ param_datatype
              body += "return #{Template.to_mrb(param_datatype, "struct_#{struct.downcase}->#{param_name}")};\n"
            else # pointer
              body += "return #{Template.to_mrb(param_datatype, "struct_#{struct.downcase}->#{param_name}")};\n"
            end
            # elseif struct TODO
          elsif Template.struct_types_all =~ param_datatype
            if Template.struct_types =~ param_datatype
              next # TODO
              Template.wrap_struct(var_name, target, mrb_type, type)
            else # pointer
              next # TODO
            end
            # init var
            # unwrap struct
            # initialize struct as ruby object
            # set to var
            # end
          else
            next
          end
          $defines += Template.function("#{struct}_get_#{param_name}", body)
          $init_body += Template.init_function("#{struct.downcase}_class", Template::MRuby.rubify_func_name(param_name), "#{struct}_get_#{param_name}", "MRB_ARGS_NONE()")

          # setter
          # init var of correct type
          # take 1 arg param
          # unwrap struct
          # set value in struct
          # return same value
          body = ''
          # TODO check this and why it is kwargs?
          body += Template::C.initialize_variables_for_kwargs([param], glue.last, "Struct: #{struct}")
          body += Template.get_args({ "#{param_name}": "#{param_datatype}" })
          body += Template.unwrap_struct("#{struct} *struct_#{struct.downcase}", 'self', "mrb_#{struct}_struct", struct)

          if Template.non_struct_types_all =~ param_datatype
            # if its a pointer
            if Template.non_struct_types_pointer =~ param_datatype
              body += "*struct_#{struct.downcase}->#{param_name} = #{Template::C.convention_parameter(param_name)};\n"
              body += "return #{Template.to_mrb(param_datatype.delete_suffix(' *'), Template::C.convention_parameter(param_name))};\n"
            else
              body += "struct_#{struct.downcase}->#{param_name} = #{Template::C.convention_parameter(param_name)};\n"
              body += "return #{Template.to_mrb(param_datatype, Template::C.convention_parameter(param_name))};\n"
            end
          elsif Template.struct_types_all =~ param_datatype
            next
            if Template.struct_types_pointer =~ param_datatype
              #TODO
            else
              #TODO
            end
          end


          $defines += Template.function("#{struct}_set_#{param_name}", body)
          $init_body += Template.init_function("#{struct.downcase}_class", "#{Template::MRuby.rubify_func_name(param_name)}=", "#{struct}_set_#{param_name}", "MRB_ARGS_REQ(1)")


        end

        ## initializer
        # init the struct(using mrb to allocate)
        # get values
        # assign values to struct
        # wrap struct
        # return self
        body = ''
        body += Template.get_module(LibraryName)
        body += Template.get_class(struct, LibraryName.downcase)
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
          if Template.non_struct_types =~ temp_rpart.first
            unwrapped_kwargs += Template::C.unwrap_kwarg(index, "wrapped_value->#{temp_rpart.last} = #{Template.to_c(temp_rpart.first, "kw_values[#{index}]")};\n", nil, "Missing kwarg: #{temp_rpart.last.underscore}")
          else
            # this is for structs or "undetermined" types
            # doesnt work yet
            next
            #unwrapped_kwargs += Tplt.unwrap_kwarg(index, "wrapped_value->#{temp_rpart.last} = (#{temp_rpart.first})kw_values[#{index}];\n")
          end
        end
        body += Template::C.get_kwargs(params)#params.length, '', init_array_body)
        body += unwrapped_kwargs

        body += "mrb_data_init(self, wrapped_value, &mrb_#{struct}_struct);\n"
        body += 'return self;'
        $defines += Template.function("#{struct}_initialize", body)
        $init_body += Template.init_function("#{struct.downcase}_class", "initialize", "#{struct}_initialize", "MRB_ARGS_OPT(1)")

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

        # TODO make a skip detector(what functions to skip bindings)
        skip = false
        #puts "FUNCTION"
        #puts "#{func.rpartition(' ').first}| + |#{func.rpartition(' ').last}"
        params.each do |param|
          #puts "#{param.rpartition(' ').first}| - |#{param.rpartition(' ').last}"
          unless (Template.all_valid_types =~ param.rpartition(' ').first) || ("void" == param)
            skip = true
            break
          end
          #if param.chars.include? '*'
          #  unless /^char \*$/ =~ param.rpartition(' ').first
          #    skip = true
          #    break
          #  end
          #end
        end
        next if skip
        #next if ['SetTraceLogCallback', 'SetSaveFileTextCallback', 'SetSaveFileDataCallback', 'SetLoadFileTextCallback', 'SetLoadFileDataCallback', 'SetCameraMode', 'GetWorldToScreenEx', 'GetWorldToScreen', 'GetMouseRay', 'GetCameraMatrix', 'DrawBillboardRec', 'DrawBillboardPro', 'DrawBillboard'].include? func_name

        # since void * can be anything just skip functions
        # (by default) that use it
        next if ['void *'].include? func_datatype
        unless Template.all_valid_types =~ func_datatype
          puts "// \"#{func_datatype}\" is not a function return datatype that can be currently autobound. From function: \"#{func_name}\"\n\n"
          next
        end

        body = ''

        # use kwargs
        if params.count > 1
          body += Template::C.initialize_variables_for_kwargs(params, glue.last, func_name)

          body += Template::C.get_kwargs(params)

          body += Template::C.parse_kwargs(params)
          body += "\n" # formatting
          # use args
        elsif params.first != 'void'
          body += Template::C.initialize_variables_for_args(params, glue.last, func_name)
          param_rpart = params.first.rpartition(' ')
          body += Template.get_args({ "#{param_rpart.last}": "#{param_rpart.first}" })
          body += Template::C.parse_args(params)
        end

        body += Template::C.initialize_return_var(func_datatype, func_name)
        body += "\n" # formatting

        body += Template.format_set_method_call(func_datatype, func_name, params, Template.struct_types =~ func_datatype.gsub(/ *\*+$/,''))

        body += Template.format_return(func_datatype, func_name)

        $defines += "\n//#{func}"
        $defines += Template.function(func_name, body)
        $init_body += Template.init_module_function(LibraryName.downcase, Template::MRuby.rubify_func_name(func_name, params), func_name, "MRB_ARGS_OPT(1)")

        debug_mark_binding(func, params)
        #puts body
        # TODO CONTINUE HERE
        #puts "// --- NEXT ---"
        #next
=begin
  # if phase 1 or 2
  if (func_datatype == 'void' && params[0] == 'void') || ((Tplt.non_struct_types.include? func_datatype) && (params[0] == 'void'))
    body = Tplt.return_format(func, params)
    #$defines += 'PHASE 1\n'
    $defines += "\n//#{func}"
    $defines += Tplt.function(func_name, body)
    $init_body += Tplt.init_module_function(LibraryName.downcase, Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_NONE()")

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

      $defines += "\n//#{func}"
      $defines += Tplt.function(func_name, body)
      $init_body += Tplt.init_module_function(LibraryName.downcase, Tplt.rubify_func_name(func_name), func_name, "MRB_ARGS_OPT(1)") # opt stuff isnt correct, need to look at this again
      # ---
      #puts func
      debug_mark_binding(func, params)
      #end
    else
      #$phase5[func] = params
    end
  end
end
raise 'end of testing'
=end
      end
      $init_body.prepend(Template.define_module(LibraryName))

      $result = %{
#{$includes}
#{$defines}
#{Template.base(LibraryName.downcase, $init_body, nil)}
      }


      #pp ($phase3.keys - $complete_phase3.keys)
      #puts
      #pp $complete_phase3

      all_completed = $complete_phase1.keys | $complete_phase2.keys | $complete_phase3.keys | $complete_phase4.keys | $complete_phase5.keys
      all = $phase1.keys | $phase2.keys | $phase3.keys | $phase4.keys | $phase5.keys

      $result += "/* Unbound:\n"
      (all - all_completed).each do |unbound|
        $result += "#{unbound}\n"
      end
      $result += "*/\n"

      $result += "//Bound Functions: #{$complete_phase1.length + $complete_phase2.length + $complete_phase3.length + $complete_phase4.length + $complete_phase5.length} / #{$phase1.length + $phase2.length + $phase3.length + $phase4.length + $phase5.length}\n//---\n"
      $result += "//Struct Accessors: #{$bound_params.length} / #{$all_params.length}\n//---\n"

      $result += "\n"

      puts $result

      puts '/*'
      puts "UNBOUND:"
      pp $all_params - $bound_params
      puts
      puts "BOUND:"
      pp $bound_params
      puts '*/'

      File.write(destination, $result)
    end
  end
end
