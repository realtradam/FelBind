# frozen_string_literal:true

# ---

mgem = FelBind::BindGem.new(gem_name: "basic_example")

mgem.add_class("BasicExample")

mgem.add_function(class_name: "BasicExample", function_name: "say_hello") do |func|
  func.content = "printf(\"Hello World\n\");"
  func.return_call do |rc|
    rc.type = "nil"
  end
end

puts mgem.build

# ---

mgem = FelBind::BindGem.new

mgem.add_class("ArgumentsAndReturnExample")

mgem.add_function(class: "ArgumentsAndReturnExample", name: "multiply_numbers") do |func|
  func.get_args do |args|
    args.int "first_input"
    args.int "second_input"
  end

  func.return_call do |rc|
    rc.type = "int"
    rc.val = "#{func.arg("first_input")} * #{func.arg("second_input")}"
  end
end

# ---

mgem = BindGem.new

mgem.add_class("KeywordArgumentsExample")

mgem.add_function(class: "KeywordArgumentsExample", name: "multiply_numbers") do |func|
  func.get_kwargs do |kwargs|
    kwargs.args x: "int", y: "int"
  end

  func.return_call do |rc|
    rc.rtype = "int"
    rc.val = "#{func.kwarg("x")} * #{func.kwarg("y")}"
  end
end

# ---

mgem = BindGem.new

mgem.add_class("Color")

mgem.add_struct(class: "Color") do |struct|
  struct.initializer = true
  struct.member(
    name: "r",
    ctype: "char",
    rtype: "int",
    accessor: true
  )
  struct.member(
    name: "g",
    ctype: "char",
    rtype: "int",
    accessor: true
  )
  struct.member(
    name: "b",
    ctype: "char",
    rtype: "int",
    accessor: true
  )
end

