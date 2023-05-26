# frozen_string_literal: true

=begin
require_relative "FelBind/version"
require_relative "FelBind/backend/uctags.rb"
require_relative "FelBind/frontend/mruby.rb"
=end

module FelBind
  class Error < StandardError; end
  # Your code goes here...

  # Binding C to mruby
  class BindGem
    attr_accessor :gem_name

    def initialize(gem_name:)
      self.gem_name = gem_name
    end

    def add_class(name)
      class_names.push name
    end

    def add_function(class_name:, function_name:, &block)
      functions.push Function.new(class_name: class_name, function_name: function_name)
      block.call(functions.last)
    end

    def add_struct(class_name:, cstruct_name:, &block)
      structs.push StructObj.new(class_name, cstruct_name)
      block.call(structs.last)
    end

    # structs
    class StructObj
      attr_accessor :class_name, :cstruct_name, :initializer

      # declaring the C struct
      def build_struct_init
        "static const struct mrb_data_type felbind_struct_#{class_name} = { \"#{class_name}\", mrb_free };\n"
      end

      # building the C functions
      def build_funcs
        init_result = ""
        init_vars = ""
        init_get_args_types = ""
        init_get_args_addresses = ""
        init_set_vars = ""
        accessor_result = ""
        if initializer
          init_result += "static mrb_value felbind_struct_init_#{class_name}(mrb_state* mrb, mrb_value self) {\n"
          init_result += "#{cstruct_name} *felbind_struct_wrapped_#{class_name} = (#{cstruct_name} *)DATA_PTR(self);\n"
          init_result += "if(felbind_struct_wrapped_#{class_name}) { mrb_free(mrb, felbind_struct_wrapped_#{class_name}); }\n"
          init_result += "mrb_data_init(self, NULL, &felbind_struct_#{class_name});\n"
          init_result += "felbind_struct_wrapped_#{class_name} = (#{cstruct_name} *)mrb_malloc(mrb, sizeof(#{cstruct_name}));\n"
        end
        members.each do |mem|
          next if !mem.accessor
          next if !initializer

          if mem.rtype == "int"
            init_vars += "mrb_int felbind_param_#{mem.name};\n"
            init_get_args_types += "i"
            init_get_args_addresses += ", &felbind_param_#{mem.name}"
            init_set_vars += "felbind_struct_wrapped_#{class_name}->#{mem.name} = (#{mem.ctype})felbind_param_#{mem.name};\n"

            accessor_result += "static mrb_value felbind_getter_#{class_name}_#{mem.name}(mrb_state *mrb, mrb_value self) {\n"
            accessor_result += "struct #{cstruct_name} *felbind_struct_get = DATA_GET_PTR(mrb, self, &felbind_struct_#{class_name}, #{cstruct_name});\n"
            #accessor_result += "return mrb_fixnum_value(felbind_getter_#{class_name}_#{mem.name});\n"
            accessor_result += "return mrb_fixnum_value(felbind_struct_get->#{mem.name});\n"
            accessor_result += "}\n"

            accessor_result += "static mrb_value felbind_setter_#{class_name}_#{mem.name}(mrb_state *mrb, mrb_value self) {\n"
            accessor_result += "mrb_int felbind_param_#{mem.name};\n"
            accessor_result += "mrb_get_args(mrb, \"i\", &felbind_param_#{mem.name});\n"
            accessor_result += "struct #{cstruct_name} *felbind_struct_set = DATA_GET_PTR(mrb, self, &felbind_struct_#{class_name}, #{cstruct_name});\n"
            accessor_result += "felbind_struct_set->#{mem.name} = (#{mem.ctype})felbind_param_#{mem.name};\n"
            accessor_result += "return mrb_fixnum_value(felbind_struct_set->#{mem.name});\n"
            accessor_result += "}\n"
          end
        end
        result = init_result
        result += init_vars
        result += "mrb_get_args(mrb, \"#{init_get_args_types}\"#{init_get_args_addresses});\n"
        result += init_set_vars
        result += "mrb_data_init(self, felbind_struct_wrapped_#{class_name}, &felbind_struct_#{class_name});\n"
        result += "return self;\n"
        result += "}\n"
        result + accessor_result
      end

      # binding instance after class is defined
      def build_set_instance(def_class_name)
        "MRB_SET_INSTANCE_TT(#{def_class_name}, MRB_TT_DATA);\n"
      end

      # binding the C funcs to Ruby
      def build_def_funcs(def_class_name)
        result = ""
        if initializer
          result += "mrb_define_method(mrb, #{def_class_name}, \"initialize\", felbind_struct_init_#{class_name}, MRB_ARGS_ANY());\n"
        end
        members.each do |mem|
          next if !initializer
          next if !mem.accessor

          result += "mrb_define_method(mrb, #{def_class_name}, \"#{mem.name}\", felbind_getter_#{class_name}_#{mem.name}, MRB_ARGS_NONE());\n"
          result += "mrb_define_method(mrb, #{def_class_name}, \"#{mem.name}=\", felbind_setter_#{class_name}_#{mem.name}, MRB_ARGS_ANY());\n"
        end
        result
      end

      def initialize(class_name, cstruct_name)
        self.class_name = class_name
        self.cstruct_name = cstruct_name
      end

      def members
        @members ||= []
      end

      def member(name:, ctype:, rtype:, accessor:)
        members.push MemberObj.new(name, ctype, rtype, accessor)
      end

      # members
      class MemberObj
        attr_accessor :name, :ctype, :rtype, :accessor

        def initialize(name, ctype, rtype, accessor)
          self.name = name
          self.ctype = ctype
          self.rtype = rtype
          self.accessor = accessor
        end
      end
    end

    private

    def functions
      @functions ||= []
    end

    def class_names
      @class_names ||= []
    end

    def structs
      @structs ||= []
    end

    # function
    class Function
      attr_accessor :content, :name, :class_name, :return_call_val, :args

      def initialize(class_name:, function_name:)
        self.class_name = class_name
        self.name = function_name
      end

      def return_call(&block)
        self.return_call_val = ReturnCall.new
        block.call(return_call_val)
      end

      def build_get_vars
        result = ""
        expect = ""
        addresses = ""
        args.arguments.each do |param|
          if param.first == :int
            result += "mrb_int #{arg(param.last)};\n"
            expect += "i"
            addresses += ", &#{arg(param.last)}"
          end
        end
        addresses.delete_prefix! ", "
        result += "mrb_get_args(mrb, \"#{expect}\", #{addresses});\n"
      end

      def build
        function = "static mrb_value\n"
        function += "felbind_#{name}(mrb_state *mrb, mrb_value self){\n"
        function += build_get_vars
        function += "#{content}\n"
        function += "#{return_call_val.build}"
        function += "}\n"
        function
      end

      def arg(name)
        "felbind_var_#{name}"
      end

      def get_args(&block)
        self.args = Args.new
        block.call(args)
      end

      # args
      class Args
        def arguments
          @arguments ||= []
        end

        def int(name)
          arguments.push [:int, name]
        end
      end

      # return call
      class ReturnCall
        attr_accessor :type, :val

        def build
          if type == "nil"
            "return mrb_nil_value();\n"
          elsif type == "int"
            "return mrb_fixnum_value(#{val});\n"
          end
        end
      end
    end
  end

  # bind gem
  class BindGem
    def build
      result = ""
      result += insert_includes

      structs.each do |strct|
        result += strct.build_struct_init
        result += strct.build_funcs
      end

      functions.each do |func_obj|
        result += func_obj.build
      end

      result += build_init
      result += build_final
      result
    end

    private

    def insert_includes
      "#include <mruby.h>\n" +
        "#include <mruby/data.h>\n" +
        "#include <mruby/class.h>\n" +
        "#include <mruby/compile.h>\n" +
        "#include <stdio.h>\n"
    end

    def build_init
      result = ""
      result += "void mrb_#{gem_name}_gem_init(mrb_state* mrb) {\n"
      class_names.each do |class_name|
        result += "struct RClass *#{class_name}_class = mrb_define_class(mrb, \"#{class_name}\", mrb->object_class);\n"
      end
      structs.each do |strct|
        result += strct.build_set_instance("#{strct.class_name}_class")
        result += strct.build_def_funcs("#{strct.class_name}_class")
      end

      functions.each do |func|
        result += "mrb_define_class_method(mrb, #{func.class_name}_class, \"#{func.name}\", felbind_#{func.name},"
        if(func.args.arguments.size.zero?)
          result += " MRB_ARGS_NONE()"
        else
          result += " MRB_ARGS_REQ(#{func.args.arguments.size})"
        end
        result += ");\n"
      end
      result += "}\n"
      result
    end

    def build_final
      "void mrb_#{gem_name}_gem_final(mrb_state* mrb) {}\n"
    end
  end
end
