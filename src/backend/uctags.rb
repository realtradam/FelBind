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
      
      def add_function(name:, ruby_name: , ruby_class:, param_as_self: '')
        #TODO
      end
      
      def add_struct
        #TODO
      end
      
      def add_typedef
        #TODO
      end
      
      def add_struct_param
        #TODO
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
            elsif tag["kind"] == "typedef"
              if tag["typeref"].split(':').first == "typename"
                # is a typedef
                puts 'its an alias(typedef)' #TODO remove
              elsif tag["typeref"].split(':').first == "struct"
                # is a struct
                puts 'its a struct' #TODO remove
              else
                puts "warning: no match" #TODO better errors
              end
            elsif tag['kind'] == 'member'
              # is struct param
              puts 'its a param' #TODO remove
            else
              puts "warning: no match" #TODO better errors
            end
          end

        end

=begin
def param_strip(signature)
        signature[1...-1].split(',')
      end

      def parse_header(path)
        parse = `ctags --output-format=json --c-kinds=pm --fields=+S --language-force=c #{path}`
        structs = {}
        functions = {}
        failed = []
        parse.each_line do |line|
          json_line = JSON.parse line
          if json_line['kind'] == 'prototype'
            functions["#{json_line['typeref'].sub(/^[^ ][^ ]* /,'')} #{json_line['name']}"] = param_strip(json_line['signature'])
          elsif json_line['kind'] == 'member'
            if json_line['scopeKind'] == 'struct'
              structs[json_line['scope']] ||= []
              structs[json_line['scope']].push "#{json_line['typeref'].delete_prefix('typename:')} #{json_line['name']}"
            else
              failed.push json_line
            end
          elsif json_line['kind'] == 'struct'
            structs[json_line['name']] =  json_line
          else
            failed.push json_line
          end
        end
        [functions, structs, failed]
      end


      def debug_show(type, hash)
        puts "#{type.upcase}:"
        puts '---'
        hash.each do |key, params|
          puts "#{type.capitalize}: #{key}"
          params.each do |param|
            puts param
          end
          puts '---'
        end
        puts
      end

      def scan(file, destination)
        functions, structs, failed = parse_header(file)
        debug_show('functions', functions)
        debug_show('structs', structs)

        if !failed.empty?
          puts "-- Failed: --"
          pp failed
          puts
        end

        puts "Functions: #{functions.size}"
        puts "Structs:   #{structs.size}"
        puts "Failed:    #{failed.size}"
        puts

        result = [functions, structs]

        File.write(destination, JSON.generate(result))
      end
=end
      end
    end
  end
end   
