# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bindings_helper"

# The generator ports listed wrap functions to Rice bindings, and its
# drift gate fails when the committed files differ from what it writes.
class GeneratorTest < Minitest::Test
  include BindingsHelper
  include TreeHelper

  def port(love_name, arguments: nil, assume: {}, main_thread: nil)
    binding = Bindings::BindingList::Generated.new(love_name:, arguments:, assume:, reason: nil)
    entry = entry(love_name)
    Bindings::Port.new(entry, binding, native_name: "native", types: BindingsHelper.types,
      module_class: entry.function.wrap.instance_class, helpers: survey.catalog.helpers, main_thread:)
  end

  # w_setLineStyle checks the name before it reaches the module, as the
  # port does: LÖVE's statements, in LÖVE's order.
  def test_a_port_keeps_lovees_statements_in_order
    code = port("love.graphics.setLineStyle").definition

    assert_includes code, "void w_setLineStyle(const std::string &style)"
    assert_operator code.index("raise_enum_error(\"line style\", Graphics::getConstants(style_value), style)"), :<,
      code.index("instance()->setLineStyle(style_value)")
  end

  # w_setDefaultFilter reads its magnification filter only when given
  # (luaL_optstring), and Rice converts it once, so the binding takes it
  # by reference, as it takes a String it always reads.
  def test_an_optional_string_is_taken_by_reference
    port = port("love.graphics.setDefaultFilter")

    assert_includes port.definition, "const std::optional<std::string> &magstr"
    assert_includes port.registration, %(Rice::Arg("magstr") = std::optional<std::string>())
  end

  # The generated file includes a header for each name it uses: the class
  # of an object argument (w_setFont's Font), std::min and std::max,
  # LÖVE's integer limits, and its Rect (w_getSafeArea's, common/math.h), as clang-tidy's misc-include-cleaner requires.
  def test_a_module_file_includes_what_its_ports_use
    list = Bindings::BindingList.new
    list.generate("love.graphics.setFont")
    list.generate("love.graphics.setDefaultFilter")
    code = BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/graphics.cpp")

    assert_includes code, %(#include "graphics/Font.h")
    assert_includes code, %(#include "common/int.h")
    assert_includes code, "#include <algorithm>"
    safe_area = Bindings::BindingList.new
    safe_area.generate("love.window.getSafeArea")
    assert_includes BindingsHelper.generator(list: safe_area).files.fetch("ext/lota/native/generated/window.cpp"),
      %(#include "common/math.h")
  end

  # w_Source_setPitch limits its pitch by std::numeric_limits<lua_Number>,
  # Lua's number, a double in LÖVE's LuaJIT, so the port limits it by a
  # double's and its file includes <limits>.
  def test_lua_numbers_limits_become_a_doubles
    list = Bindings::BindingList.new
    list.generate("Source:setPitch")
    code = BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/audio.cpp")

    assert_includes code, "std::numeric_limits<double>::max()"
    refute_includes code, "lua_Number"
    assert_includes code, "<= 0.0F"
    assert_includes code, "#include <limits>"
  end

  # w_setFused takes any value and asks whether it is truthy
  # (luax_toboolean), which Rice reads as a bool.
  def test_a_truthy_argument_is_a_bool
    port = port("love.filesystem.setFused")

    assert_includes port.definition, "void w_setFused(bool fused)"
    assert_includes port.rbs, "(bool fused) -> nil"
  end

  # w_setClipboardText reads a const char *, which the port's std::string
  # parameter stands for; System::setClipboardText takes a std::string, so
  # the parameter passes as it is, while a method that takes a const char *
  # still gets c_str().
  def test_a_string_parameter_passes_as_it_is_where_the_engine_takes_a_string
    assert_includes port("love.system.setClipboardText").definition, "instance()->setClipboardText(text);"
    assert_includes port("love.graphics.setLineStyle").definition, "getConstant(style.c_str(), style_value)"
  end

  def test_a_runtime_test_of_an_argument_makes_it_optional
    port = port("love.graphics.circle")

    assert_includes port.definition, "std::optional<int> points"
    assert_includes port.definition, "if (!points.has_value())"
    assert_includes port.registration, %(Rice::Arg("points") = std::optional<int>())
    assert_equal "def native: (String mode, Float | Integer x, Float | Integer y, Float | Integer radius, " \
      "?Integer? points) -> nil", port.rbs.sub("self.", "")
  end

  # w_SpriteBatch_setDrawRange reads its start, which Lua counts from 1,
  # into a variable as (int) luaL_checkinteger(L, 2) - 1, and the engine
  # counts from 0, so the port keeps the subtraction the declaration
  # makes, as w_Quad_setLayer's does.
  def test_a_variable_read_with_arithmetic_keeps_it
    assert_includes port("SpriteBatch:setDrawRange").definition, %(t.setDrawRange((start.value() - 1), required(count, "count"));)
    assert_includes port("Quad:setLayer").definition, "quad.setLayer((layer - 1));"
  end

  # w_Quad_setViewport reads the texture's height (argument 7) only when
  # it is given a width (argument 6), so Ruby may leave both out: an
  # argument after an optional one is optional too, as a Ruby method's
  # positional parameters are, and a form that reads it says so when it is
  # missing, naming it as Rice names a missing argument.
  def test_an_argument_after_an_optional_one_is_optional_and_required_where_read
    port = port("Quad:setViewport")

    assert_includes port.registration, %(Rice::Arg("sw") = std::optional<double>(), ) +
      %(Rice::Arg("sh") = std::optional<double>())
    assert_includes port.definition, %(quad.refresh(v, sw.value(), required(sh, "sh"));)
    assert_match(/\?\(Float \| Integer\)\? sw, \?\(Float \| Integer\)\? sh\) -> nil\z/, port.rbs)
  end

  def test_arguments_beyond_the_bound_form_are_pruned
    code = port("love.graphics.rectangle", arguments: 5).definition

    refute_includes code, "rx"
    assert_includes code, "instance()->rectangle(mode_value, static_cast<float>(x), static_cast<float>(y), " \
      "static_cast<float>(w), static_cast<float>(h))"
  end

  def test_an_assumed_condition_picks_the_form
    code = port("love.graphics.setColor", arguments: 4, assume: { "lua_istable(L, 1)" => false }).definition

    assert_includes code, "c.r = static_cast<float>(r)"
    refute_includes code, "rawgeti"
  end

  def test_an_optional_reader_with_a_literal_default_becomes_a_rice_default
    assert_includes port("love.event.pump").registration, %(Rice::Arg("wait_timeout") = 0.0)
  end

  # Rule 14: a float result is widened to a Float, an int stays an Integer.
  def test_results_take_the_type_lovees_cpp_holds_them_in
    assert_includes port("love.graphics.getLineWidth").definition,
      "double w_getLineWidth() {\nreturn static_cast<double>(instance()->getLineWidth());"
    assert_includes port("love.graphics.getWidth").definition, "int w_getWidth() {"
    assert_match(/-> Array\[Float\]\z/, port("love.graphics.getColor").rbs)
  end

  # w_getX declares two doubles in one statement (double x, y;), which
  # getPosition fills; the port declares each in a statement of its own,
  # initialized, and pushes x as the Float LÖVE holds it in.
  def test_variables_declared_together_are_declared_apart
    port = port("love.mouse.getX")

    assert_includes port.definition, "double w_getX() {\ndouble x{};\ndouble y{};\n" \
      "instance()->getPosition(x, y);\nreturn x;"
    assert_equal "def native: () -> Float", port.rbs.sub("self.", "")
  end

  def test_a_method_takes_its_object_const_when_it_only_reads_it
    code = port("Texture:isCanvas", main_thread: "Lota::Graphics").definition

    assert_includes code, "bool w_Texture_isCanvas(const Texture &t)"
    assert_includes code, "require_main_thread(MODULE);"
    assert_includes port("RandomGenerator:setState").definition, "(RandomGenerator &rng, const std::string &statestr)"
  end

  # Rule 4: w_SpriteBatch_getDrawRange returns nothing when the batch
  # draws every sprite and two values otherwise, so the port returns an
  # Array on both paths, empty on the first (ADR 001, section 7).
  def test_a_form_that_returns_several_values_returns_an_array_on_every_path
    port = port("SpriteBatch:getDrawRange", main_thread: "Lota::Graphics")

    assert_includes port.definition, "Rice::Array w_SpriteBatch_getDrawRange(const SpriteBatch &t) {\n" \
      "require_main_thread(MODULE);\nRice::Array results;"
    assert_includes port.definition, "if (!t.getDrawRange(start, count)) {\nreturn results;\n}"
    assert_includes port.definition, "results.push(start + 1, false);\nresults.push(count, false);\nreturn results;"
    assert_match(/-> Array\[Integer\]\z/, port.rbs)
  end

  # Rule 4 again: w_File_tell returns luax_ioError's nil and message when
  # the position is unknown, and the position otherwise, so both are an
  # Array, and the message is the one LÖVE formats.
  def test_an_io_error_returns_nil_and_its_message_in_an_array
    port = port("File:tell")

    assert_includes port.definition, "Rice::Array w_File_tell(File &file) {\nRice::Array results;"
    assert_includes port.definition, %(if (pos == -1) {\nreturn io_error("Invalid position.");\n})
    assert_match(/results\.push\(\(double\)pos, false\);\n\}\n\}\nreturn results;\n\}\n\z/, port.definition)
    assert_match(/-> Array\[Integer \| nil \| String\]\z/, port.rbs)
  end

  def test_errors_become_engine_exceptions
    assert_includes port("love.graphics.getLineStyle").definition, %(throw love::Exception("Unknown line style");)
  end

  def test_a_body_the_port_cannot_write_is_refused_by_name
    error = assert_raises(Bindings::Port::Unsupported) { port("love.graphics.clear") }

    assert_equal "love.graphics.clear is not readable", error.message
    assert_raises(Bindings::Port::Unsupported) { port("love.keyboard.isDown") }
  end

  def test_native_names_follow_the_rules_except_writers_and_listed_exceptions
    generator = BindingsHelper.generator

    assert_equal "set_line_width", generator.native_name(entry("love.graphics.setLineWidth"))
    assert_equal "canvas?", generator.native_name(entry("Texture:isCanvas"))
    assert_equal "new_canvas", generator.native_name(entry("love.graphics.newCanvas"))
    assert_equal "state=", generator.native_name(entry("RandomGenerator:setState"))
    assert_raises(Bindings::Generator::Failure) { generator.native_name(entry("Transform:__mul")) }
  end

  def test_main_thread_modules_come_from_lovees_thread_module
    assert_equal %w[window graphics], BindingsHelper.generator.main_thread_modules
  end

  def test_a_limited_form_needs_a_reason
    list = Bindings::BindingList.new

    assert_raises(Bindings::BindingList::Invalid) { list.generate("love.graphics.rectangle", arguments: 5) }
    assert_raises(Bindings::BindingExceptions::Invalid) do
      Bindings::BindingExceptions.new.native_name("X:y", as: "z", reason: " ")
    end
  end

  def test_every_listed_function_is_in_lovees_api_once
    names = BindingsHelper.list.generated.map(&:love_name) + BindingsHelper.list.hand_written.map(&:love_name)

    assert_equal names.uniq, names
    names.each { |name| assert entry(name), name }
  end

  def test_every_exception_names_a_generated_function
    generated = BindingsHelper.list.generated.map(&:love_name)

    BindingsHelper.exceptions.names.each { |name| assert_includes generated, name.love_name }
  end

  # The rules give each bound function the Ruby name lib/ already
  # defines, so the generator and the hand-written Ruby agree. RandomGenerator
  # has no Ruby class yet, and Lota::Math draws from the math module's
  # generator itself; capture_screenshot serves only the parity harness;
  # love.filesystem's init and setSource only Lota::Boot, as they serve
  # only boot.lua; and love.window.showMessageBox only Lota's error
  # handler, until the maintainer settles how its buttons form, whose table
  # holds both the buttons and the enterbutton and escapebutton settings,
  # translates.
  UNWRITTEN = %w[
    RandomGenerator:_random
    RandomGenerator:getState
    RandomGenerator:randomNormal
    RandomGenerator:setSeed
    RandomGenerator:setState
    love.filesystem.init
    love.filesystem.setSource
    love.graphics.captureScreenshot
    love.math._getRandomGenerator
    love.math.newRandomGenerator
    love.window.showMessageBox
  ].freeze

  def test_lib_defines_the_name_the_rules_give_each_bound_function
    list = BindingsHelper.list
    missing = (list.generated + list.hand_written).map(&:love_name).reject do |love_name|
      defined_in_lib?(translation(love_name))
    end

    assert_equal UNWRITTEN, missing.sort
  end

  def defined_in_lib?(translation)
    name = translation.name or return false
    return constant("#{translation.scope}::#{name.delete_suffix('.new')}").respond_to?(:new) if name.end_with?(".new")

    owner = constant(translation.scope) or return false
    translation.singleton ? owner.respond_to?(name) : owner.method_defined?(name)
  end

  # The constant named +path+, or nil.
  def constant(path)
    path.split("::").reduce(Object) do |scope, name|
      return nil unless scope.const_defined?(name, false)

      scope.const_get(name, false)
    end
  end

  # The name table errors.hpp translates LÖVE's messages with (ADR 001,
  # section 7): every function a rule names, with the Ruby name the rules
  # give it, sorted for errors.hpp's binary search; a function no rule
  # names is not in it.
  def test_the_name_table_gives_each_function_the_name_the_rules_give_it
    table = BindingsHelper.generator.name_table

    assert_equal "Lota::Window.title=", table.fetch("love.window.setTitle")
    assert_equal "Lota::Window.set_mode", table.fetch("love.window.setMode")
    assert_equal "Lota::Graphics::Canvas.new", table.fetch("love.graphics.newCanvas")
    assert_equal "Lota::Image::ImageData#pixel", table.fetch("ImageData:getPixel")
    refute table.key?("love.math._getRandomGenerator")
    assert_equal table.keys.sort, table.keys
    assert_includes BindingsHelper.generator.files.fetch("ext/lota/native/generated/names.hpp"),
      %(    LoveName("love.window.setTitle", "Lota::Window.title="),\n)
  end

  def test_the_committed_bindings_match_the_generator
    assert_empty BindingsHelper.generator.problems
  end

  # The drift gate, against a copy of the generated files: an edit, a
  # missing file, and a stale one each fail it.
  def test_the_drift_gate_reports_edited_missing_and_stale_files
    in_tree do |root|
      FileUtils.mkdir_p(File.join(root, "vendor"))
      File.symlink(BindingsHelper::LOVE, File.join(root, "vendor/love"))
      FileUtils.mkdir_p(File.join(root, "ext"))
      FileUtils.cp(File.join(ROOT, "ext/.clang-format"), File.join(root, "ext/.clang-format"))
      generator = BindingsHelper.generator(root:)
      generator.write

      assert_empty generator.problems
      File.write(File.join(root, "ext/lota/native/generated/timer.cpp"), "// edited\n", mode: "a")
      File.delete(File.join(root, "sig/lota/native/generated.rbs"))
      write(root, "ext/lota/native/generated/stale.cpp", "")
      problems = generator.problems

      assert_includes problems, "ext/lota/native/generated/timer.cpp differs from what the generator writes:"
      assert_includes problems, "  - // edited"
      assert_includes problems, "sig/lota/native/generated.rbs does not exist; generate it"
      assert_includes problems, "ext/lota/native/generated/stale.cpp is no longer generated; remove it"
      generator.write

      assert_empty generator.problems
    end
  end
end
