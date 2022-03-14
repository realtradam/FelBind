module Template # Template
  # methods that convert something from ruby-land to c-land
  module C
    class << self
      def to_c_function_name(function_name:)
        "mrb_#{function_name}"
      end

      def to_getter_name(struct_name:, variable_name:)
        "mrb_#{struct_name}_get_#{variable_name}"
      end

      def to_setter_name(struct_name:, variable_name:)
        "mrb_#{struct_name}_set_#{variable_name}"
      end

      def to_initializer_name(struct_name:)
        "mrb_#{struct_name}_initialize"
      end

      def format_type(param_datatype)
        if Template.treated_as_int =~ param_datatype
          'int'
        elsif Template.treated_as_bool =~ param_datatype
          'bool'
        elsif Template.treated_as_float =~ param_datatype
          'float'
        elsif Template.treated_as_string =~ param_datatype
          'char *'
        elsif Template.struct_types =~ param_datatype
          "#{param_datatype}"
        else
          nil # cannot be formated
        end
      end

      def convention_parameter(param)
        "parameter_#{param}"
      end

      def convention_return_variable(func_name)
        "return_of_#{func_name}"
      end

      def initialize_variables(params, structs, func_name=nil)

        result = ''
        return result if params.first == 'void'
        params.each do |param|
          rpart = param.rpartition(' ')
          format = Template::C.format_type(rpart.first)
          if format
            result += format + " #{Template::C.convention_parameter(rpart.last)};\n"
          elsif !func_name.nil?
            puts "// \"#{rpart.first}\" is not a parameter datatype that can be currently autobound. From function: \"#{func_name}\" and param: #{rpart.first}\n\n"
            raise
          end
        end
        result + "\n"
      end

      def get_kwargs(params)
        init_array_body = ''
        params.each do |param|
          rpart = param.rpartition(' ')
          init_array_body += "mrb_intern_lit(mrb, \"#{rpart.last}\"),\n"
        end
        init_array_body.delete_suffix!(",\n")
        %{uint32_t kw_num = #{params.length};
const mrb_sym kw_names[] = {
#{init_array_body}
};
mrb_value kw_values[kw_num];
const mrb_kwargs kwargs = { kw_num, 0, kw_names, kw_values, NULL };
mrb_get_args(mrb, "|:", &kwargs);
        }
      end

      def parse_kwargs(params)
        result = ''
        skipped = 0
        params.each_with_index do |param, index|
          rpart = param.rpartition(' ')
          (skipped += 1) && next unless Template.valid_types =~ rpart.first
          unwrap = "#{Template::C.convention_parameter(rpart.last)} = #{Template.to_c(rpart.first, "kw_values[#{index - skipped}]")};"
          result += Template::C.unwrap_kwarg(index - skipped,unwrap)
        end
        result
      end

      def unwrap_kwarg(kwarg_iter, body_if_defined, body_if_undefined = nil, no_argument_error_message = 'Missing Keyword Argument')
        %{
if (mrb_undef_p(kw_values[#{kwarg_iter}])) {
#{body_if_undefined || "mrb_load_string(mrb, \"raise ArgumentError.new \\\"#{no_argument_error_message}\\\"\");"}
} else {
#{body_if_defined}
}
        }
      end

    end
  end

  # methods that convert something from c-land to ruby-land
  module MRuby
    class << self
      # convert a C function name to be
      # formatted like a Ruby method name
      def rubify_func_name(function)
        func = function.underscore
        if func.start_with? 'is_'
          func = func.delete_prefix('is_') + '?'
        elsif func.start_with? 'set_'
          func = func.delete_prefix('set_') + '='
        else
          func.delete_prefix('get_')
        end
        func
      end

      def to_c_function_name(function_name:)
        rubify_func_name(function_name)
      end

      def to_getter_name(struct_name:, variable_name: nil)
        rubify_func_name(variable_name)
      end

      def to_setter_name(struct_name:, variable_name: nil)
        rubify_func_name(variable_name) + '='
      end

      def to_initializer_name(struct_name: nil)
        "initialize"
      end
    end
  end


  class << self

    # could be unsigned
    attr_writer :treated_as_int
    def treated_as_int
      @treated_as_int ||= /^((un)?signed )?int$|^((un)?signed )?long$|^((un)?signed )?short$|^((un)?signed )char$/
    end

    attr_writer :treated_as_bool
    def treated_as_bool
      @treated_as_bool ||= /^bool$/
    end

    attr_writer :treated_as_float
    def treated_as_float
      @treated_as_float ||= /^float$|^double$/
    end

    attr_writer :treated_as_string
    def treated_as_string
      @treated_as_string ||= /^(const )?char \*$/
    end

    attr_writer :treated_as_void
    def treated_as_void
      @treated_as_void ||= /^void$/
    end

    def non_struct_types
      @non_struct_types ||= Regexp.union(treated_as_int, treated_as_bool, treated_as_float, treated_as_string, treated_as_void)
    end

    attr_writer :struct_types
    def struct_types
      if @struct_types
        @struct_types
      else
        raise "Struct types were not parsed\nRun 'parse_struct_types' first"
      end
    end

    def parse_struct_types(structs)
      struct_types = structs.keys
      struct_types.map! do |string|
        "^#{string}$"
      end
      @struct_types = /#{struct_types.join('|')}/
    end

    def valid_types
      @valid_types ||= Regexp.union(non_struct_types, struct_types)
    end

    def base(gem_name, init_body, final_body)
      %{
      void
      mrb_mruby_#{gem_name}_gem_init(mrb_state* mrb) {
      #{init_body}
}

void
mrb_mruby_#{gem_name}_gem_final(mrb_state* mrb) {
#{final_body}
}
      }
    end

    def format_method_call(func_datatype, func_name, params, is_struct=false)
      result = ''
      if params.first == 'void'
        result += "return #{'*' if is_struct}#{Template::C.convention_return_variable(func_name)} = "
      end
      result += "#{func_name}("
      params.each do |param|
        rpart = param.rpartition(' ')
        result += "#{rpart.last}, "
      end
      result.delete_suffix(', ') + ");\n"
    end

    def format_return(func_datatype, func_name)
      "return #{Template.to_mrb(func_datatype, Template::C.convention_return_variable(func_name))};"
    end

    def init_module(module_name)
      "struct RClass *#{module_name.downcase}_module = mrb_define_module(mrb, \"#{module_name}\");"
    end

    def get_module(module_name)
      "struct RClass *#{module_name.downcase}_mrb_module = mrb_module_get(mrb, \"#{module_name}\");\n"
    end

    def get_class(class_name, defined_under)
      "struct RClass *#{class_name.downcase}_mrb_class = mrb_class_get_under(mrb, #{defined_under.downcase}_mrb_module, mrb_#{class_name}_struct.struct_name);\n"
    end

    def init_module_function(module_name, function_name, mrb_function_name, mrb_args)
      %{
      mrb_define_module_function(mrb, #{module_name}, "#{function_name}", mrb_#{mrb_function_name}, #{mrb_args});
      }
    end

    # define under needs the C name, not the ruby name which may be confusing
    def init_class(class_name, define_under, is_struct_wrapper = true)
      %{
        struct RClass *#{class_name.downcase}_class = mrb_define_class_under(mrb, #{define_under}, \"#{class_name}\", mrb->object_class);#{
      if is_struct_wrapper
        "\nMRB_SET_INSTANCE_TT(#{class_name.downcase}_class, MRB_TT_DATA);"
      end
        }
      }
    end

    def function(function_name, body)
      %{
static mrb_value
mrb_#{function_name}(mrb_state* mrb, mrb_value self) {
#{body}
}
      }
    end

    def init_function(class_name, function_name, mrb_function_name, mrb_args)
      %{mrb_define_method(mrb, #{class_name}, "#{function_name}", mrb_#{mrb_function_name}, #{mrb_args});
      }
    end

    def get_args(req_arg_hash, opt_arg_hash=nil)
      raise if opt_arg_hash
      result = ''
      tail = ''
      flags = ''
      req_arg_hash.each do |var_name, var_datatype|
        if var_datatype != 'unsigned char'
          result += "#{var_datatype} #{var_name};\n"
        else
          result += "mrb_int #{var_name};\n"
        end
        tail += ", &#{var_name}"
        flags += datatype_to_arg_flag(var_datatype)
      end
      result += "mrb_get_args(mrb, \"#{flags}\"#{tail});\n"
    end

    def datatype_to_arg_flag(datatype)
      if treated_as_int.include? datatype
        'i'
      elsif treated_as_bool.include? datatype
        'b'
      elsif treated_as_float.include? datatype
        'f'
      elsif treated_as_string.include? datatype
        'z'
      end
    end

    def unwrap_struct(var_name, target, mrb_type, type)
      %{#{var_name} = DATA_GET_PTR(mrb, #{target}, &#{mrb_type}, #{type});\n}
    end

    def wrap_struct(var_name, target, mrb_type, type)
      %{
        #{var_name} = (#{type} *)DATA_PTR(#{target});
        if(#{var_name}) #{'{'} mrb_free(mrb, #{var_name}); #{'}'}
            mrb_data_init(#{target}, NULL, &#{mrb_type});
#{var_name} = (#{type} *)mrb_malloc(mrb, sizeof(#{type}));
      }
    end

    def define_module(module_name)
      %{struct RClass *#{module_name.downcase} = mrb_define_module(mrb, "#{module_name}");
      }
    end

    # for converting mrb to C
    def to_c(type, variable)
      if (Template.treated_as_int =~ type) || (Template.treated_as_bool =~ type)
        "mrb_as_int(mrb, #{variable})"
      elsif Template.treated_as_float =~ type
        "mrb_as_float(mrb, #{variable})"
      elsif Template.treated_as_string =~ type
        "mrb_str_to_cstr(mrb, #{variable})"
      end
    end

    # for converting C to mrb
    def to_mrb(type, variable)
      if Template.treated_as_int =~ type
        "mrb_fixnum_value(#{variable})"
      elsif Template.treated_as_float =~ type
        "mrb_float_value(mrb, #{variable})"
      elsif Template.treated_as_bool =~ type
        "mrb_bool_value(#{variable})"
      elsif Template.treated_as_string =~ type
        "mrb_str_new_cstr(mrb, #{variable})"
      elsif Template.treated_as_void =~ type
        'mrb_nil_value()'
      end
    end


    # generate a return of a ruby bound C function
    def return_format(function, params)
      func_rpart = function.rpartition(' ')
      func_datatype = func_rpart.first
      func_name = func_rpart.last
      result = ''
      if func_datatype == 'void'
        if params.first == 'void'
          result = "#{func_name}();\nreturn mrb_nil_value();"
        else
          result = "#{func_name}("
          result += params.first.rpartition(' ').last

          params.drop(1).each do |param|
            result += ", #{param.rpartition(' ').last}"
          end
          result += ");\nreturn mrb_nil_value();"
        end
      elsif params.first == 'void'
        result = "return " + Tplt.to_mrb(func_datatype, "#{func_name}()") + ';'
      else
        temp_params = params.first.rpartition(' ').last

        params.drop(1).each do |param|
          temp_params += ", #{param.rpartition(' ').last}"
        end
        result = 'return ' + Tplt.to_mrb(func_datatype, "#{func_name}(#{temp_params})") + ';'
      end
      result
    end

    # doesnt seem correct?
    def return_format_struct(function)
      func_rpart = function.rpartition(' ')
      func_datatype = func_rpart.first.delete_suffix(' *')
      func_name = func_rpart.last
      "return mrb_obj_value(Data_Wrap_Struct(mrb, #{func_datatype.downcase}_mrb_class, &mrb_#{func_datatype}_struct, return_value));"
    end

    def make_mrb_obj_from_struct(mrb_var, func, struct_var)
      func_rpart = func.rpartition(' ')
      func_datatype = func_rpart.first.delete_suffix(' *')
      func_name = func_rpart.last
      "mrb_data_init(#{mrb_var}, #{struct_var}, &mrb_#{func_rpart.first}_struct);\n"
    end

    # wrapping an existing struct to be used by ruby
    def init_struct_wrapper(struct, free_body = nil)
      %{
      #{"void mrb_helper_#{struct}_free(mrb_state*, void*);" if free_body}

        static const struct mrb_data_type mrb_#{struct}_struct = { 
        "#{struct}", 
          #{
      if free_body
        "mrb_helper_#{struct}_free"
      else
        "mrb_free"
      end
}
        };
        #{
      if free_body

        %{
        void
        mrb_helper_#{struct}_free(mrb_state* mrb, void*ptr) {
        #{struct} *struct_data = (#{struct}*)ptr;
        #{free_body}
mrb_free(mrb, ptr);
  }
        }
      end
}
      }
    end

  end
end

