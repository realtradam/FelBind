require 'json'

module FelBind
  module Backends
    class Intermediate < Hash

      def initialize
        self[:GemName] = ''
        self[:Typedefs] = {}
        self[:CFunctions] = {}
        self[:CStructs] = {}
      end
      
      def add_function(name:, params:)
        func = {}
        self[:CFunctions][name] = func
        func[:RubyName] = name
        func[:Params] = {}
        params.each do |param|
          temp = param.rpartition(' ')
          func[:Params][temp.last] = [temp.last, temp.first]
        end
      end
      
      def add_struct(name:)
        self[:CStructs][name] = {}
      end
      
      def add_struct_param(struct_name:, param_name:, type:)
        struct = self[:CStructs][struct_name]
        struct[:Accessors] = []
        struct[:Accessors].push [
          param_name,
          {
            RubyName: param_name,
            Type: type,
            GetterSkip: false,
            SetterSkip: false,
          },
        ]
      end
      
      def add_typedef(typedef:, c_type:)
        self[:Typedefs][typedef] = c_type
      end

    end

    module UCTags
      class << self

        # ctags --list-kinds=c
        # --c-kinds:
        # p  function prototypes
        # (s  structure names)
        # (z  function parameters inside function or prototype definitions)
        # m  struct, and union members
        # t  typedef
        # --fields:
        # S  signature
        def ctag(file)
          `ctags --output-format=json --c-kinds=pmt --fields=+S --language-force=c #{file}`
        end

        def parse(file)
          ctags_output = self.ctag(file).each_line.map do |tag|
            JSON.parse tag
          end
          intermediate = FelBind::Backends::Intermediate.new

          ctags_output.each do |tag|
            if tag["kind"] == "prototype"
              # its a function
              puts 'its a function' #TODO remove
              intermediate.add_function(name: tag["name"], params: tag["signature"][1...-1].split(','))
            elsif tag["kind"] == "typedef"
              if tag["typeref"].split(':').first == "typename"
                # is a typedef
                puts 'its an alias(typedef)' #TODO remove
                intermediate.add_typedef(typedef: tag["name"], c_type: tag["typeref"].split(':').last)
              elsif tag["typeref"].split(':').first == "struct"
                # is a struct
                puts 'its a struct' #TODO remove
                intermediate.add_struct(name: tag["name"])
              else
                puts "warning: no match" #TODO better errors
              end
            elsif tag['kind'] == 'member'
              # is struct param
              puts 'its a struct param' #TODO remove
              intermediate.add_struct_param(struct_name: tag["scope"], param_name: tag["name"], type: tag["typeref"].split(":").last)
            else
              puts "warning: no match" #TODO better errors
            end
          end

          return intermediate
        end
      end
    end
  end
end   
