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

    def init_module_function(module_name, function_name, mrb_function_name, mrb_args)
      %{
      mrb_define_module_function(mrb, #{module_name}, "#{function_name}", mrb_#{mrb_function_name}, #{mrb_args});
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

    def unwrap_kwarg(kwarg_iter, body_if_defined, body_if_undefined)
      %{
if (mrb_undef_p(kw_values[#{kwarg_iter}])) {
#{body_if_undefined}
} else {
#{body_if_defined}
}
      }
    end

    def unwrap_struct(var_name, target, mrb_type, type)
      %{#{var_name} = DATA_GET_PTR(mrb, #{target}, &#{mrb_type}, #{type})}
    end

    def define_module(module_name)
      %{struct RClass *#{module_name.downcase} = mrb_define_module(mrb, "#{module_name}");
      }
    end

    # for converting mrb to C
    def to_c(type, variable)
      if (type == 'int') || (type == 'unsigned int') || (type == 'bool')
        "mrb_as_int(mrb, #{variable})"
      elsif (type == 'float') || (type == 'double')
        "mrb_as_float(mrb, #{variable})"
      elsif (type == 'const char *') || (type == 'char *')
        "mrb_str_to_cstr(mrb, #{variable})"
      end
    end

    # for converting C to mrb
    def to_mrb(type, variable)
      if (type == 'int') || (type == 'unsigned int')
        "mrb_fixnum_value(#{variable})"
      elsif (type == 'float') || (type == 'double')
        "mrb_float_value(mrb, #{variable})"
      elsif type == 'bool'
        "mrb_bool_value(#{variable})"
      elsif (type == 'const char *') || (type == 'char *')
        "mrb_str_new_cstr(mrb, #{variable})"
      elsif type == 'NULL'
        'mrb_nil_value()'
      end
    end

  end
end

