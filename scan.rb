require 'json'

# ctags --list-kinds=c
# p  function prototypes
# s  structure names
# z  function parameters inside function or prototype definitions
# m  struct, and union members
parse = `ctags --output-format=json --c-kinds=pm --fields=+S --language-force=c raylib.h`
File.write('json.json', parse)
$garbage = []

def param_strip(signature)
  signature[1...-1].split(',')
end


def parse_header(path)
  parse = `ctags --output-format=json --c-kinds=pm --fields=+S --language-force=c #{path}`
  structs = {}
  functions = {}
  parse.each_line do |line|
    json_line = JSON.parse line
    if json_line['kind'] == 'prototype'
      functions[json_line['name']] = param_strip(json_line['signature'])
    elsif json_line['kind'] == 'member'
      if json_line['scopeKind'] == 'struct'
        structs[json_line['scope']] ||= []
        structs[json_line['scope']].push "#{json_line['typeref'].delete_prefix('typename:')} #{json_line['name']}"
      else
        $garbage.push json_line
      end
    elsif json_line['kind'] == 'struct'
      structs[json_line['name']] =  json_line
    else
      $garbage.push json_line
    end
  end
  [functions, structs]
end

functions, structs = parse_header('raylib.h')

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

debug_show('functions', functions)
debug_show('structs', structs)

if !$garbage.empty?
  pp $garbage
  puts
end

puts "Functions: #{functions.size}"
puts "Structs: #{structs.size}"
puts "Garbage: #{$garbage.size}(should be 0)"
puts
