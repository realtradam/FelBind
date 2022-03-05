module Template
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

    def get_kwargs(kwarg_num, body)
      %{
uint32_t kw_num = #{kwarg_num};
const mrb_sym kw_names[] = {
#{body}
};
mrb_value kw_values[kw_num];
const mrb_kwargs kwargs = { kw_num, 0, kw_names, kw_values, NULL };
mrb_get_args(mrb, "|:", &kwargs);
      }
    end

    def unwrap_kwarg(kwarg_iter, body_if_defined, body_if_undefined)
      %{
if (mrb_undef_p(kw_values[#{kwarg_iter}])) {
#{body_if_defined}
} else {
#{body_if_undefined}
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

  end
end

