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

    private

    def functions
      @functions ||= []
    end

    def class_names
      @class_names ||= []
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
        "felflame_var_#{name}"
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
      functions.each do |func_obj|
        result += func_obj.build
      end
      result += build_init
      result += build_final
      result
    end

    private

    def insert_includes
      "#include <mruby.h>\n#include <stdio.h>\n"
    end

    def build_init
      result = ""
      result += "void mrb_#{gem_name}_gem_init(mrb_state* mrb) {\n"
      class_names.each do |class_name|
        result += "struct RClass *#{class_name}_class = mrb_define_module(mrb, \"#{class_name}\");\n"
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
