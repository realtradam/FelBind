require 'optparse'
require 'json'
require 'set'
require 'active_record'
require_relative './templates.rb'

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: example.rb [options]"

  parser.on("-gGLUE", "--glue=GLUE", "Path to file(defaults to ./glue.rb)") do |glue|
    options[:glue] = glue
  end

  parser.on('-cCONFIG', '--config=CONFIG', 'Path to config file') do |config|
    options[:config] = config
  end
end.parse!

options[:glue] ||= './glue.json'
glue = JSON.parse(File.read(options[:glue]))

bound = {}

$phase1 = {}
$phase2 = {}
$phase3 = {}
$phase4 = {}
$phase5 = {}
$complete_phase1 = {}
$complete_phase2 = {}
$complete_phase3 = {}
$complete_phase4 = {}
$complete_phase5 = {}

result = ""
includes = %{
#include <raylib.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/numeric.h>
#include <mruby/string.h>
#include <stdlib.h>
}
defines = ""
init_body = ""
standard_types = ['bool', 'int', 'float', 'double', 'float', 'const char *', 'unsigned int', 'void']

# for displaying statistics
glue.first.each do |func, params|
  if (func.rpartition(' ').first == 'void') && (params[0] == 'void')
    $phase1[func] = params
  elsif (standard_types.include? func.rpartition(' ').first) && (params[0] == 'void')
    $phase2[func] = params
  else
    no_struct_param = true
    params.each do |param|
      if !(standard_types.include? param.rpartition(' ').first)
        no_struct_param = false
        break
      end
    end
    if no_struct_param
      if standard_types.include? func.rpartition(' ').first
        $phase3[func] = params
      else
        $phase4[func] = params
      end
    else
      $phase5[func] = params
    end
  end
end

def debug_mark_binding(func, params)
  if $phase1.include? func
    $complete_phase1[func] = params
  elsif $phase2.include? func
    $complete_phase2[func] = params
  elsif $phase3.include? func
    $complete_phase3[func] = params
  elsif $phase4.include? func
    $complete_phase4[func] = params
  elsif $phase5.include? func
    $complete_phase5[func] = params
  end
end

# generates functions
glue.first.each do |func, params|
  # for now dont worry about params or returns
  rpart = func.rpartition(' ')
  func_datatype = rpart.first
  func_name = rpart.last

  if func_datatype == 'void' && params[0] == 'void'
    body = "#{func.split(' ').last}();\nreturn mrb_nil_value();"
    defines += Template.function(func.split(' ').last, body)
    init_body += Template.init_module_function('test', func.split(' ').last.underscore, func.split(' ').last, "MRB_ARGS_NONE()")

    bound[func] = params
    debug_mark_binding(func, params)
  elsif (standard_types.include? func_datatype) && (params[0] == 'void')
    if func_datatype == 'int'
      body = "return mrb_fixnum_value(#{func.split(' ').last}());"
      defines += Template.function(func.split(' ').last, body)
      init_body += Template.init_module_function('test', func.split(' ').last.underscore, func.split(' ').last, "MRB_ARGS_NONE()")

      bound[func] = params
      debug_mark_binding(func, params)
    end
  end
end

init_body.prepend(Template.define_module('Test'))

result = %{
  #{includes}
#{defines}
#{Template.base('test', init_body, nil)}
}

result += "//Bound Functions: #{$complete_phase1.length + $complete_phase2.length + $complete_phase3.length + $complete_phase4.length + $complete_phase5.length} / #{$phase1.length + $phase2.length + $phase3.length + $phase4.length + $phase5.length}\n//---\n"

result += "//Phase 1 Functions: #{$complete_phase1.length} / #{$phase1.length}\n"
result += "//Phase 2 Functions: #{$complete_phase2.length} / #{$phase2.length}\n"
result += "//Phase 3 Functions: #{$complete_phase3.length} / #{$phase3.length}\n"
result += "//Phase 4 Functions: #{$complete_phase4.length} / #{$phase4.length}\n"
result += "//Phase 5 Functions: #{$complete_phase5.length} / #{$phase5.length}\n"


puts result
