require_relative 'scan.rb'
require_relative 'generate.rb'

desc 'create parsed file with ctags'
task :scan do
  # for each file in target directory
  # parse file
  # output to build/parse
  Dir.mkdir('build') unless File.exists?('build')
  Dir.each_child('target') do |file|
    Scan.scan("target/#{file}", 'build/parsed.json')
  end
end

desc 'build bindings from the parsed file'
task :generate do
  # read parse file
  # output to build/bind
  Generate.generate('build/parsed.json', '../FelFlameEngine/mrbgems/mruby-raylib/src/bind.c')
end

task :make_gem do
  # read bind file
  # output to build/gem
end
