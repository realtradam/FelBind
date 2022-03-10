module Tplt # Template
  class << self
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

    attr_writer :treated_as_int
    def treated_as_int
      @treated_as_int ||= ['int', 'unsigned int', 'long', 'short']
    end

    attr_writer :treated_as_bool
    def treated_as_bool
      @treated_as_bool ||= ['bool']
    end

    attr_writer :treated_as_float
    def treated_as_float
      @treated_as_float ||= ['float', 'double']
    end

    attr_writer :treated_as_string
    def treated_as_string
      @treated_as_string ||= ['char *', 'const char *']
    end

    attr_writer :treated_as_void
    def treated_as_void
      @treated_as_void ||= ['void']
    end

    def non_struct_types
      treated_as_int | treated_as_bool | treated_as_float | treated_as_string | treated_as_void
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

    def get_kwargs(kwarg_num, init_var_body, init_array_body)
      %{
#{init_var_body}

uint32_t kw_num = #{kwarg_num};
const mrb_sym kw_names[] = {
#{init_array_body}
};
mrb_value kw_values[kw_num];
const mrb_kwargs kwargs = { kw_num, 0, kw_names, kw_values, NULL };
mrb_get_args(mrb, "|:", &kwargs);
      }
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


    def unwrap_struct(var_name, target, mrb_type, type)
      %{#{var_name} = DATA_GET_PTR(mrb, #{target}, &#{mrb_type}, #{type})}
    end

    def wrap_struct(var_name, target, mrb_type, type)
      %{
          #{var_name} = (#{type} *)DATA_PTR(#{target})
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
      if treated_as_int.include?(type) || treated_as_bool.include?(type)
        "mrb_as_int(mrb, #{variable})"
      elsif treated_as_float.include? type
        "mrb_as_float(mrb, #{variable})"
      elsif treated_as_string.include? type
        "mrb_str_to_cstr(mrb, #{variable})"
      end
    end

    # for converting C to mrb
    def to_mrb(type, variable)
      if treated_as_int.include? type
        "mrb_fixnum_value(#{variable})"
      elsif treated_as_float.include? type
        "mrb_float_value(mrb, #{variable})"
      elsif treated_as_bool.include? type
        "mrb_bool_value(#{variable})"
      elsif treated_as_string.include? type
        "mrb_str_new_cstr(mrb, #{variable})"
      elsif treated_as_void.include? type
        'mrb_nil_value()'
      end
    end

    # convert a C function name to be
    # formatted like a Ruby method name
    def rubify_func_name(function)
      func = function.underscore
      if func.start_with? 'is_'
        func = func.delete_prefix('is_') + '?'
      end
      func.delete_prefix('get_')
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

    def return_format_struct(function)
      func_rpart = function.rpartition(' ')
      func_datatype = func_rpart.first.delete_suffix(' *')
      func_name = func_rpart.last
      "return mrb_obj_value(Data_Wrap_Struct(mrb, #{func_datatype.downcase}_mrb_class, &mrb_#{func_datatype}_struct, return_value));"
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

