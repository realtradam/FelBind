require 'felbind'

FelBind::Config.set('Raylib') do |config|
  # what namespace to make the bindings under
  config.namespace = 'Raylib'

  config.func('DrawLineV') << {
    # use vars inside of the struc as params rather then the struct
    # as a param and place them into a struct later when passing into func
    # this avoids using mruby struct wrapping
    dont_wrap: ['color'],

    # default setting, converts functions names to snakecase
    ruby_name_conversion: true
  }

  config.func('DrawText') << {
    # will be under Raylib::String because of namespace
    define_under_module: 'String',

    # default(because of ruby_name_conversion)
    override_func_name: 'draw_text' 
  }

  config.func('DrawRectangleRec') << {
    # define as a function used by Rectangle objects
    define_under_obj: 'Raylib::Rectangle',

    # Unwrap "self" rather then accept a parameter
    use_self_for: 'rec'
  }

  # do not bind these at all
  config.func_ignore << [
    'TextCopy',
    'TextIsEqual',
    'TextLength'
  ]

  config.struct_ignore << [
    'Vector3'
  ]
end


