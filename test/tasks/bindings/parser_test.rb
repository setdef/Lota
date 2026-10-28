# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bindings_helper"

# The parser reads LÖVE's wrap files: the source with comments blanked,
# the tables that register functions, and each body's statements.
class ParserTest < Minitest::Test
  include BindingsHelper

  def source(text)
    Bindings::CppSource.new("wrap_Example.cpp", text)
  end

  def test_comments_and_directives_are_blanked_but_keep_their_lines
    text = source(%(int a; // luaL_error(L, "x")\n/* lua_call(L) */ int b;\n#define instance() x\nchar *s = "// kept";\n)).text

    refute_includes text, "luaL_error"
    refute_includes text, "lua_call"
    refute_includes text, "#define"
    assert_includes text, %("// kept")
    assert_equal 4, text.count("\n")
  end

  def test_line_of_counts_from_one
    file = source("a\nbc\nd")

    assert_equal 1, file.line_of(0)
    assert_equal 2, file.line_of(3)
    assert_equal 3, file.line_of(5)
  end

  # w_rectangle (wrap_Graphics.cpp:3628-3658): declarations, an if with
  # a lambda in luax_catchexcept, and returns.
  def test_statements_open_ifs_and_catchexcept_lambdas
    function = entry("love.graphics.rectangle").function
    nodes = Bindings::Statements.parse(function.definition.body, function.definition.body_offset, function.wrap.source)
    first_if = nodes.find { |node| node.kind == :if }

    assert_equal "!Graphics::getConstant(str, mode)", first_if.text
    assert_equal 3632, first_if.line
    catches = nodes.flat_map { |node| node.each_node.to_a }.select { |node| node.kind == :catch }

    assert_equal 3, catches.size
    assert_equal ["instance()->rectangle(mode, x, y, w, h)"], catches.first.body.map(&:text)
  end

  # A statement that declares several variables of one type, with
  # initializers or pointer marks (SoundData *t = ..., *c = nullptr), is
  # one declaration of each, so each has its own type and initializer; a
  # call's arguments and a comma inside parentheses are not declarators.
  def test_a_declaration_of_several_variables_is_one_of_each
    text = "int width = 0, height = f(a, b); SoundData *t = g(L, 1), *c = nullptr; double x, y; call(a, b);"
    nodes = Bindings::Statements.parse(text, 0, source(text))

    assert_equal [
      "int width = 0",
      "int height = f(a, b)",
      "SoundData *t = g(L, 1)",
      "SoundData *c = nullptr",
      "double x",
      "double y",
      "call(a, b)",
], nodes.map(&:text)
  end

  # A helper that only checks a condition of the module's and raises
  # (luax_checkgraphicscreated, wrap_Graphics.cpp:56-61) is a guard, which
  # the port makes where a wrap function calls it.
  def test_guards_are_the_helpers_that_check_a_condition_and_raise
    guard = survey.catalog.guards.fetch("luax_checkgraphicscreated")

    assert_equal "!instance()->isCreated()", guard.condition
    assert_equal '"love.graphics cannot function without a window."', guard.message
  end

  def test_an_unbalanced_body_is_unreadable
    assert_raises(Bindings::Statements::Unreadable) { Bindings::Statements.parse("if (x { y; }", 0, source("")) }
  end

  def test_calls_split_arguments_at_the_top_level_only
    call = Bindings::Calls.in(%{luax_enumerror(L, "draw mode", Graphics::getConstants(mode), str)}).first

    assert_equal "luax_enumerror", call.name
    assert_equal ["L", '"draw mode"', "Graphics::getConstants(mode)", "str"], call.arguments
    assert_predicate call, :lua?
  end

  def test_calls_know_their_receiver_and_template
    calls = Bindings::Calls.in("luax_pushboolean(L, t->isRenderTarget()); luax_checktype<Texture>(L, 1)")

    assert_equal "t", calls.find { |call| call.base_name == "isRenderTarget" }.receiver
    assert_equal "Texture", calls.find { |call| call.base_name == "luax_checktype" }.template
  end

  # LÖVE registers 1,088 functions in the luaL_Reg tables of its 74 wrap
  # files at the pinned commit, under 815 distinct names.
  def test_the_catalog_lists_every_registered_function_once
    functions = survey.catalog.functions

    assert_equal 74, survey.catalog.files.size
    assert_equal 1088, functions.size
    assert_equal 815, functions.map(&:lua_name).uniq.size
    assert_equal functions.size, functions.map(&:love_name).uniq.size
  end

  # A type's own table belongs to it; the tables it inherits do not
  # (luax_register_type(L, &ImageData::type, data::w_Data_functions,
  # w_ImageData_functions, nullptr), wrap_ImageData.cpp).
  def test_methods_belong_to_the_type_whose_file_defines_their_table
    image_data = survey.catalog.functions.select { |function| function.type_name == "ImageData" }.map(&:lua_name)

    assert_includes image_data, "getPixel"
    refute_includes image_data, "getSize"
    assert_equal "image", entry("ImageData:getPixel").function.module_name
    assert_equal "physics", entry("Body:applyForce").function.module_name
  end

  def test_each_function_is_found_where_it_is_defined
    function = entry("love.timer.step").function

    assert_equal "src/modules/timer/wrap_Timer.cpp", function.wrap.path
    assert_equal "w_step", function.definition.name
    assert_equal [33, 37], [function.definition.line, function.definition.end_line]
  end

  def test_the_only_function_outside_the_wrap_files_is_getpackedsize
    outside = survey.entries.select { |entry| entry.source == :outside }.map { |entry| entry.function.love_name }

    assert_equal ["love.data.getPackedSize"], outside
  end

  def test_helpers_map_luax_check_functions_to_their_classes
    assert_equal "Texture", survey.catalog.helpers.fetch("luax_checktexture")
    assert_equal "RandomGenerator", survey.catalog.helpers.fetch("luax_checkrandomgenerator")
  end

  # wrap_RandomGenerator.lua defines random twice, with and without
  # LuaJIT's FFI; the first counts.
  def test_lua_functions_are_listed_once_with_their_parameters
    random = survey.entries.select { |entry| entry.function.love_name == "RandomGenerator:random" }

    assert_equal 1, random.size
    assert_equal :lua, random.first.source
    assert_equal %w[l u], random.first.function.parameters
    assert_equal "src/modules/math/wrap_RandomGenerator.lua:46", random.first.function.location
  end

  # Each Lua function records the guards its file returns at before
  # defining it: wrap_ImageData.lua defines its FFI code only under
  # LuaJIT with its compiler on and both libraries loaded, and
  # wrap_Data.lua checks for LuaJIT but not its compiler, while
  # RandomGenerator:random's first definition comes before any guard.
  def test_lua_functions_record_the_guards_they_run_behind
    get_pixel = survey.entries.find { |entry| entry.source == :lua && entry.function.love_name == "ImageData:getPixel" }

    assert_equal ["LÖVE runs on LuaJIT", "LuaJIT's compiler is on", "LuaJIT's FFI loads", "LuaJIT's bit library loads"],
      get_pixel.function.guards
    assert_equal "when LÖVE runs on LuaJIT, LuaJIT's compiler is on, LuaJIT's FFI loads, and LuaJIT's bit library " \
      "loads", get_pixel.function.condition
    ffi_pointer = survey.replaced_by_lua("Data:getFFIPointer")

    assert_equal ["LÖVE runs on LuaJIT", "LuaJIT's FFI loads"], ffi_pointer.guards
    assert_equal "always", survey.entries.find { |entry| entry.function.love_name == "RandomGenerator:random" }
      .function.condition
  end

  # A Lua function replaces a C++ wrap function only where both define
  # the name: SoundData:getSample's LuaJIT code replaces
  # w_SoundData_getSample, while RandomGenerator:random wraps a C++
  # function of another name, _random, and ImageData:paste is C++ alone.
  def test_the_survey_knows_which_lua_replaces_which_cpp
    assert_equal "src/modules/sound/wrap_SoundData.lua:79", survey.replaced_by_lua("SoundData:getSample").location
    assert_equal "src/modules/image/wrap_ImageData.lua:395", survey.replaced_by_lua("ImageData:getPixel").location
    assert_nil survey.replaced_by_lua("RandomGenerator:random")
    assert_nil survey.replaced_by_lua("ImageData:paste")
  end

  def test_headers_give_return_types_through_bases_and_typedefs
    types = BindingsHelper.types

    assert_equal "int", types.methods("ImageData", "getWidth", module_dir: "src/modules/image").first.return_type
    assert_equal "float", types.field("Colorf", "r")
    sleep = types.methods("Timer", "sleep").first

    assert_equal ["seconds"], sleep.parameters.map(&:name)
    assert sleep.const
    refute types.methods("RandomGenerator", "setState").first.const
  end
end
