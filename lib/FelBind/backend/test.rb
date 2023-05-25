require_relative './uctags.rb'

pp FelBind::Backends::UCTags.parse('test.h')
#pp FelBind::Backends::UCTags.parse('raylib.h')
