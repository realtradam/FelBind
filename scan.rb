require 'json'

parse = `ctags --output-format=json --c-kinds=pmz --language-force=c raylib.h`
File.write('json.json', parse)
$params = {}
$members = {}
$garbage = []
$struct = []
parse.each_line do |line|
  json_line = JSON.parse line
  puts json_line['kind']
  if json_line['kind'] == 'parameter'
    if $params[json_line['scope']].nil?
      $params[json_line['scope']] = []
    end
    $params[json_line['scope']].push json_line
  elsif json_line['kind'] == 'prototype'
    $members[json_line['name']] = json_line
  elsif json_line['kind'] == 'member'
    if json_line['scopeKind'] == 'struct'
      $struct.push json_line
    else
      $garbage.push json_line
    end
  else
    if json_line['scopeKind'] == 'struct'
      $garbage.push json_line
    end
  end
end

$members.each do |key, item|
  puts "Function: #{item['typeref'].gsub(/typename:[^ ]* /,'')} #{item['name']}"
  $params.each do |key, param_arry|
    param_arry.each do |param| 
      if param['scope'] == item['name']
        puts "#{param['typeref'].gsub('typename:','')} #{param['name']}"
      end
    end
  end
  puts '---'
end

puts 
puts "Struct: #{$struct.size}"
puts "Garbage: #{$garbage.size}(should be 0)"
