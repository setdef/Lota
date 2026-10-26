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
  # of an object argument (w_setFont's Font), std::min and std::max, and
  # LÖVE's integer limits, as clang-tidy's misc-include-cleaner requires.
  def test_a_module_file_includes_what_its_ports_use
    list = Bindings::BindingList.new
    list.generate("love.graphics.setFont")
    list.generate("love.graphics.setDefaultFilter")
    code = BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/graphics.cpp")

    assert_includes code, %(#include "graphics/Font.h")
    assert_includes code, %(#include "common/int.h")
    assert_includes code, "#include <algorithm>"
  end

  def test_a_runtime_test_of_an_argument_makes_it_optional
    port = port("love.graphics.circle")

    assert_includes port.definition, "std::optional<int> points"
    assert_includes port.definition, "if (!points.has_value())"
    assert_includes port.registration, %(Rice::Arg("points") = std::optional<int>())
    assert_equal "def native: (String mode, Float | Integer x, Float | Integer y, Float | Integer radius, " \
      "?Integer? points) -> nil", port.rbs.sub("self.", "")
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
  # generator itself; and capture_screenshot serves only the parity
  # harness.
  UNWRITTEN = %w[
    RandomGenerator:_random
    RandomGenerator:getState
    RandomGenerator:randomNormal
    RandomGenerator:setSeed
    RandomGenerator:setState
    love.graphics.captureScreenshot
    love.math._getRandomGenerator
    love.math.newRandomGenerator
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
