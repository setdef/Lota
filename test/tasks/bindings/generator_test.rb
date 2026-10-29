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
      module_class: entry.function.wrap.instance_class, helpers: survey.catalog.helpers, main_thread:,
      guards: survey.catalog.guards)
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

  # wrap_Decoder.cpp defines LÖVE's instance() macro for love.sound's
  # class, Sound, but Decoder:getSampleRate never reaches it, so the file
  # does not include Sound.h, which clang-tidy's misc-include-cleaner would
  # refuse; Data's class is LÖVE's common Data (common/Data.h), and the
  # size_t its size is, <cstddef>'s.
  def test_a_module_file_includes_its_modules_class_only_when_it_reaches_the_module
    list = Bindings::BindingList.new
    list.generate("Decoder:getSampleRate")
    sound = BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/sound.cpp")
    data = Bindings::BindingList.new
    data.generate("Data:getSize")

    assert_includes sound, %(#include "sound/Decoder.h")
    refute_includes sound, %(#include "sound/Sound.h")
    data_file = BindingsHelper.generator(list: data).files.fetch("ext/lota/native/generated/data.cpp")
    assert_includes data_file, %(#include "common/Data.h")
    assert_includes data_file, "#include <cstddef>"
  end

  # love.math's class, Math, is declared in MathModule.h, as no Math.h
  # exists; a header is found by the class it declares, not by a name that
  # matches only on a file system that ignores case (common/math.h).
  def test_a_module_class_is_included_from_the_header_that_declares_it
    list = Bindings::BindingList.new
    list.generate("love.math.newTransform")
    math = BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/math.cpp")

    assert_includes math, %(#include "math/MathModule.h")
    refute_includes math, %(#include "common/math.h")
  end

  # w_SoundData_copyFrom reads its source as a const SoundData *, which the
  # port takes as LÖVE declares it.
  def test_an_object_read_as_const_is_taken_const
    assert_includes port("SoundData:copyFrom").definition,
      "void w_SoundData_copyFrom(SoundData &dst, const SoundData *src, int src_start, int count, int dst_start)"
  end

  # w_Transform_inverseOf reads its source as a Transform * but calls only
  # its const getMatrix, as clang-tidy's misc-const-correctness sees, so
  # the port takes it const; w_Transform_apply passes its other Transform
  # on to Transform::apply, which takes it as it is.
  def test_an_object_only_const_methods_reach_is_taken_const
    assert_includes port("Transform:inverseOf").definition, "const Transform *source)"
    assert_includes port("Transform:apply").definition, "(Transform &t, Transform *other)"
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
    assert_includes port("SpriteBatch:setDrawRange").definition, %(t.setDrawRange((required(start, "start") - 1), required(count, "count"));)
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
    assert_includes port.definition, %(quad.refresh(v, required(sw, "sw"), required(sh, "sh"));)
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
    assert_match(/-> \[Float, Float, Float, Float\]\z/, port("love.graphics.getColor").rbs)
  end

  # w_Data_getSize pushes the size_t Data::getSize returns as a lua_Number,
  # which rule 14 makes an Integer, as the C++ holds it: the port returns
  # it as the size_t it is, without the cast to a Lua number.
  def test_an_integer_pushed_as_a_lua_number_stays_an_integer
    port = port("Data:getSize")

    assert_includes port.definition, "size_t w_Data_getSize(const Data &t) {\nreturn t.getSize();\n}"
    assert_match(/-> Integer\z/, port.rbs)
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
  # Array, and the message is the one LÖVE formats. The position is the
  # Integer its int64 holds (rule 14), though LÖVE pushes it as a
  # lua_Number. Each else follows an if that returns, so what it holds
  # follows the if instead, as clang-tidy's readability-else-after-return
  # asks.
  def test_an_io_error_returns_nil_and_its_message_in_an_array
    port = port("File:tell")

    assert_includes port.definition, "Rice::Array w_File_tell(File &file) {\nRice::Array results;"
    assert_includes port.definition, %(if (pos == -1) {\nreturn io_error("Invalid position.");\n})
    assert_match(/\}\nresults\.push\(pos, false\);\nreturn results;\n\}\n\z/, port.definition)
    refute_includes port.definition, "else"
    assert_match(/-> Array\[Integer \| nil \| String\]\z/, port.rbs)
  end

  # w_Source_clone pushes the Source it made and releases its own
  # reference, so the port returns the pointer, keeps the release out,
  # and has Rice give that reference to the Ruby wrapper
  # (Return().takeOwnership(), native/binding.hpp). w_SpriteBatch_getTexture
  # pushes a Texture the batch keeps, so the wrapper retains its own.
  def test_a_pushed_engine_object_is_returned_and_one_the_wrap_function_releases_is_owned
    clone = port("Source:clone")
    texture = port("SpriteBatch:getTexture", main_thread: "Lota::Graphics")

    assert_includes clone.definition, "Source * w_Source_clone(Source &t) {\nSource *clone = nullptr;\n" \
      "clone = t.clone();\nreturn clone;\n}"
    assert_includes clone.registration, "Rice::Return().takeOwnership()"
    assert_equal "def native: () -> Source", clone.rbs
    refute_includes texture.registration, "takeOwnership"
    assert_includes texture.definition, "return t.getTexture();"
    assert_equal "def native: () -> Texture", texture.rbs
  end

  # luax_pushshape pushes a Shape as the class its type names
  # (wrap_Shape.cpp:36-63), as Rice wraps a pointer, so it is a push of the
  # Shape; and w_Body_getShape pushes nil when there is none.
  def test_a_shape_is_pushed_as_an_object_and_nil_as_a_null_pointer
    port = port("Body:getShape")

    assert_includes port.definition, "Shape *s = t.getShape();\nif (s != nullptr) {\nreturn s;\n}\nreturn nullptr;\n}"
    assert_equal "def native: () -> Shape?", port.rbs
    assert_equal "def native: () -> [Shape, Shape]", port("Contact:getShapes").rbs
  end

  # w_Transform_translate pushes its own Transform back for Lua's
  # chaining (lua_pushvalue(L, 1)), which the Ruby wrapper does by
  # returning itself, so the port returns nothing.
  def test_a_method_that_pushes_its_own_object_returns_nothing
    port = port("Transform:translate")

    assert_includes port.definition, "void w_Transform_translate(Transform &t, double x, double y) {\n" \
      "t.translate(static_cast<float>(x), static_cast<float>(y));\n}"
    assert_equal "def native: (Float | Integer x, Float | Integer y) -> nil", port.rbs
  end

  # w_Shape_getBody returns no value when the Shape has no Body, which a
  # Lua caller reads as nil, so the port returns nil there.
  def test_a_form_that_returns_one_object_or_none_returns_nil_for_none
    port = port("Shape:getBody")

    assert_includes port.definition, "if (body == nullptr) {\nreturn nullptr;\n}\nreturn body;"
    assert_equal "def native: () -> Body?", port.rbs
  end

  # w_SoundData_slice declares its SoundData and the slice in one
  # statement, and w_getDesktopDimensions its width and height with their
  # initializers; the port declares each apart, with its own.
  def test_variables_declared_together_with_initializers_are_declared_apart
    assert_includes port("SoundData:slice").definition, "SoundData *c = nullptr;\nc = t.slice(start, length);"
    assert_includes port("love.window.getDesktopDimensions", main_thread: "Lota::Window").definition,
      "int width = 0;\nint height = 0;\n"
  end

  # luax_checkgraphicscreated (wrap_Graphics.cpp:56-61) raises unless the
  # graphics module has a window; the port makes its check where the wrap
  # function calls it.
  def test_a_guard_helper_is_checked_where_it_is_called
    assert_includes port("love.graphics.getFont").definition,
      %(if (!instance()->isCreated()) {\nthrow love::Exception("love.graphics cannot function without a window.");\n})
  end

  # w_newSpriteBatch reads its usage only when it has more than two
  # arguments, which in Ruby is when the third is given.
  def test_a_count_of_the_arguments_tests_whether_one_is_given
    code = port("love.graphics.newSpriteBatch").definition

    assert_includes code, "if (usage.has_value() && "
    assert_includes code, "BufferDataUsage usage_value = BUFFERDATAUSAGE_DYNAMIC;"
    refute_includes code, "lua_gettop"
  end

  # w_setColorMask sets every channel from one boolean when it has at
  # most one argument, and w_setStencilState resets the state when it has
  # at most one and that one is nil, which in Ruby is when the second is
  # not given. A form that reads an argument such a test made optional,
  # with a check where no test guards it, requires it, as LÖVE's check
  # raises without it.
  def test_a_count_of_at_most_some_arguments_tests_whether_the_next_is_left_out
    mask = port("love.graphics.setColorMask").definition
    stencil = port("love.graphics.setStencilState").definition

    assert_includes mask, "if (!g.has_value()) {"
    refute_includes mask, "lua_gettop"
    assert_match(/if \(!comparestr\.has_value\(\) &&\s*!actionstr\.has_value\(\)\) \{/, stencil)
    assert_includes stencil, %(getConstant(required(comparestr, "comparestr").c_str(), s.compare))
    assert_includes stencil, "s.readMask = static_cast<love::uint32>(read_mask.value_or(LOVE_UINT32_MAX));"
  end

  # w_setBlendMode tests its alpha mode's name only when it is given one,
  # in an if whose body is that test alone; the port tests both in one
  # if, as clang-tidy's readability-redundant-nested-if asks.
  def test_an_if_holding_only_an_if_tests_both_conditions_at_once
    code = port("love.graphics.setBlendMode").definition

    assert_includes code, 'if (alphamode.has_value() && !getConstant(required(alphamode, "alphamode").c_str(), '
    assert_equal 2, code.scan(/^if \(/).size
  end

  # The render state's enums and structs (graphics/renderstate.h) and the
  # vertex enums (graphics/vertex.h) are declared outside any class, with
  # the getConstant overloads that read their names, so a file whose
  # ports name them includes those headers, as clang-tidy's
  # misc-include-cleaner asks, and a file whose ports name none does not.
  def test_a_module_file_includes_the_headers_of_the_enums_it_names
    list = Bindings::BindingList.new
    list.generate("love.graphics.setBlendMode")
    list.generate("love.graphics.setMeshCullMode")
    code = BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/graphics.cpp")
    plain = Bindings::BindingList.new
    plain.generate("love.graphics.setLineStyle")

    assert_includes code, %(#include "graphics/renderstate.h")
    assert_includes code, %(#include "graphics/vertex.h")
    refute_includes BindingsHelper.generator(list: plain).files.fetch("ext/lota/native/generated/graphics.cpp"),
      "graphics/renderstate.h"
  end

  # w_newBody tests its type's const char * for truth, and makes it 0
  # where it has none, as w_getSystemCursor starts its Cursor at 0; the
  # port compares the pointer with nullptr and starts it there, as
  # clang-tidy's readability-implicit-bool-conversion and
  # modernize-use-nullptr ask.
  def test_a_pointer_tested_for_truth_is_compared_with_nullptr
    code = port("love.physics.newBody").definition

    assert_includes code, "? nullptr : argument4.value().c_str();"
    assert_includes code, "if (typestr != nullptr && !Body::getConstant(typestr, btype)) {"
    assert_includes port("love.mouse.getSystemCursor").definition, "Cursor *cursor = nullptr;"
  end

  # Rule 4 returns several values as an Array; where every path returns
  # the same ones, its type says which (w_getDesktopDimensions' width and
  # height), and where they differ, as w_SpriteBatch_getDrawRange's do, any
  # of them.
  def test_several_values_every_path_returns_are_a_tuple
    assert_match(/-> \[Integer, Integer\]\z/, port("love.window.getDesktopDimensions", main_thread: "Lota::Window").rbs)
    assert_match(/-> Array\[Integer\]\z/, port("SpriteBatch:getDrawRange", main_thread: "Lota::Graphics").rbs)
  end

  # A string LÖVE holds as a const char * returns as a std::string, alone
  # or among several values, so Rice gives Ruby the same String either way.
  def test_a_c_string_among_several_values_is_pushed_as_a_std_string
    assert_includes port("love.graphics.getDefaultFilter").definition, "results.push(std::string(minstr), false);"
  end

  # Rule 14: w_getMeter pushes the float meter as a Lua integer, which
  # truncates it, so the port returns it as an Integer; a one-byte integer,
  # SamplerState's maxAnisotropy, returns as the int it widens to rather
  # than the character Rice would make of it; and a method's result with a
  # number added (quad->getLayer() + 1) keeps the method's type.
  def test_numbers_take_the_type_the_push_gives_them
    assert_includes port("love.physics.getMeter").definition,
      "long long w_getMeter() {\nreturn static_cast<long long>(Physics::getMeter());\n}"
    assert_includes port("love.graphics.getDefaultFilter").definition, "results.push(static_cast<int>(s.maxAnisotropy), false);"
    assert_equal "def native: () -> [String, String, Integer]", port("love.graphics.getDefaultFilter").rbs.sub("self.", "")
    assert_includes port("Quad:getLayer").definition, "int w_Quad_getLayer(const Quad &quad) {\nreturn quad.getLayer() + 1;"
  end

  # w_Shape_getFilterData fills a C array, which the port declares as a
  # std::array, as clang-tidy's modernize-avoid-c-arrays asks, passes by
  # its data(), and reads with at().
  def test_a_c_array_becomes_a_std_array
    code = port("Shape:getFilterData").definition

    assert_includes code, "std::array<int, 3> v{};\nt.getFilterData(v.data());\nresults.push(v.at(0), false);"
  end

  # A statement the port leaves calling Lua, such as w_print's
  # luax_checkcoloredstring, would not compile, so the port refuses it.
  def test_a_port_that_still_reaches_lua_is_refused
    error = assert_raises(Bindings::Port::Unsupported) { port("love.graphics.print").definition }

    assert_match(/\Alove\.graphics\.print still reaches Lua after its port: /, error.message)
  end

  # A class named as another of LÖVE's modules, as Font is named as
  # love.font, lives under the module that registers it, as
  # Lota::Native::Graphics::Font, since Lota::Native::Font is love.font's.
  # Data, registered by love.data itself, stays where it is.
  def test_a_class_named_as_another_module_lives_under_its_own
    list = Bindings::BindingList.new
    list.generate("Font:getHeight")
    list.generate("Data:getSize")
    files = BindingsHelper.generator(list:).files

    assert_includes files.fetch("ext/lota/native/generated/graphics.cpp"),
      %(Rice::define_class_under<Font>(Rice::define_module_under(native, "Graphics"), "Font"))
    assert_includes files.fetch("ext/lota/native/generated/data.cpp"), %(Rice::define_class_under<Data>(native, "Data"))
    rbs = files.fetch("sig/lota/native/generated.rbs")
    assert_match(/^    module Graphics\n      class Font\n        def height: \(\) -> Float\n      end\n    end$/, rbs)
    assert_match(/^    class Data\n/, rbs)
  end

  # ImageData:encode returns love.filesystem's FileData, whose header is
  # neither love.image's nor common's, but the one another module has.
  def test_a_type_of_another_module_includes_that_modules_header
    list = Bindings::BindingList.new
    list.generate("ImageData:encode")

    assert_includes BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/image.cpp"),
      %(#include "filesystem/FileData.h")
  end

  # What clang-tidy refuses as redundant: a string copied through
  # c_str() into a std::string again, and a cast of a parameter to the
  # pointer type it has.
  def test_redundant_copies_and_casts_are_left_out
    assert_includes port("ImageData:encode").definition, %(std::string filename = "Image." + format;)
    assert_includes port("FileData:getFilename").definition, "return t.getFilename();"
    assert_includes port("ImageData:paste").definition, "t.paste(src, dx, dy, sx, sy,"
  end

  # w_Texture_setWrap fills the sampler state's fields through
  # getConstant, and w_Texture_setDepthSampleMode assigns a field of one
  # of them, so neither may declare the state const.
  def test_a_local_whose_nested_fields_change_is_not_const
    assert_includes port("Texture:setWrap").definition, "\nSamplerState s = t.getSamplerState();"
    assert_includes port("Texture:setDepthSampleMode").definition, "\nSamplerState s = t.getSamplerState();"
    assert_includes port("Texture:getFilter").definition, "const SamplerState &s = t.getSamplerState();"
  end

  # w_Texture_getDebugName pushes a string, or nil for a texture with no
  # name, so its one result is a std::optional that is empty for nil.
  def test_a_value_pushed_or_nil_returns_an_optional
    port = port("Texture:getDebugName")

    assert_includes port.definition, "std::optional<std::string> w_Texture_getDebugName(const Texture &t)"
    assert_includes port.definition, "return std::nullopt;"
    assert_includes port.rbs, "-> String?"
  end

  # w_Texture_getFormat names a PixelFormat, which common/pixelformat.h
  # declares with its getConstant, as clang-tidy's misc-include-cleaner
  # asks.
  def test_a_pixel_format_includes_its_header
    list = Bindings::BindingList.new
    list.generate("Texture:getFormat")

    assert_includes BindingsHelper.generator(list:).files.fetch("ext/lota/native/generated/graphics.cpp"),
      %(#include "common/pixelformat.h")
  end

  # w_Source_setRolloff compares with .0f, a float literal clang-tidy's
  # readability-uppercase-literal-suffix asks to write .0F.
  def test_a_float_literal_with_no_leading_digit_gets_an_uppercase_suffix
    code = port("Source:setRolloff").definition

    assert_includes code, "< .0F"
    refute_includes code, ".0f"
  end

  # w_setDopplerScale reads its scale with luax_checkfloat, which returns
  # a float, so the port casts the double Rice passes to one, as clang-tidy's
  # narrowing-conversions check asks.
  def test_a_float_read_is_cast_to_float
    assert_includes port("love.audio.setDopplerScale").definition, "setDopplerScale(static_cast<float>(scale))"
  end

  # w_Texture_getMipmapFilter pushes the negated lodBias, a float.
  def test_a_negated_field_has_the_fields_type
    assert_includes port("Texture:getMipmapFilter").definition, "results.push(static_cast<double>(-s.lodBias), false);"
  end

  def test_a_pointer_to_what_new_makes_is_declared_auto
    assert_includes port("Transform:__mul").definition, "auto *t3 = new Transform(t1.getMatrix() * t2->getMatrix());"
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
    assert_equal "*", generator.native_name(entry("Transform:__mul"))
    assert_raises(Bindings::Generator::Failure) { generator.native_name(entry("RandomGenerator:_random")) }
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

  # Where LÖVE runs Lua in place of a wrap function's C++, the generator
  # refuses to port the C++, and a hand-written binding of it must say it
  # ports the Lua; a function no Lua replaces cannot claim to.
  def test_a_function_lua_replaces_is_ported_from_the_lua_alone
    generated = Bindings::BindingList.new
    generated.generate("ImageData:getPixel")
    error = assert_raises(Bindings::Generator::Failure) { BindingsHelper.generator(list: generated).files }
    assert_includes error.message, "ImageData:getPixel: LÖVE runs src/modules/image/wrap_ImageData.lua:395 in place " \
      "of its C++ when LÖVE runs on LuaJIT"
    assert_includes error.message, "list it with bound_from_lua"

    by_hand = Bindings::BindingList.new
    by_hand.bound_by_hand("SoundData:getSample", reason: "ports the Lua")
    assert_raises(Bindings::Generator::Failure) { BindingsHelper.generator(list: by_hand).files }

    claimed = Bindings::BindingList.new
    claimed.bound_from_lua("ImageData:paste")
    error = assert_raises(Bindings::Generator::Failure) { BindingsHelper.generator(list: claimed).files }
    assert_includes error.message, "no wrap_*.lua file replaces its C++"

    ported = Bindings::BindingList.new
    ported.bound_from_lua("ImageData:getPixel")
    ported.generate("Data:getSize")
    assert BindingsHelper.generator(list: ported).files
  end

  def test_every_listed_function_is_in_lovees_api_once
    names = BindingsHelper.list.love_names

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
  # generator itself; love.filesystem's init and setSource only Lota::Boot, as they serve
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
    love.math._getRandomGenerator
    love.math.newRandomGenerator
    love.window.showMessageBox
  ].freeze

  def test_lib_defines_the_name_the_rules_give_each_bound_function
    list = BindingsHelper.list
    missing = list.love_names.reject do |love_name|
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

  # The name table Lota::ErrorMessage translates LÖVE's messages with (ADR
  # 001, section 7): every function a rule names, with the Ruby name the
  # rules give it, sorted by LÖVE's name; a function no rule names is not
  # in it.
  def test_the_name_table_gives_each_function_the_name_the_rules_give_it
    table = BindingsHelper.generator.name_table

    assert_equal "Lota::Window.title=", table.fetch("love.window.setTitle")
    assert_equal "Lota::Window.set_mode", table.fetch("love.window.setMode")
    assert_equal "Lota::Graphics::Canvas.new", table.fetch("love.graphics.newCanvas")
    assert_equal "Lota::Image::ImageData#pixel", table.fetch("ImageData:getPixel")
    refute table.key?("love.math._getRandomGenerator")
    assert_equal table.keys.sort, table.keys
  end

  # The table is written as Ruby, a Hash literal that the magic comment
  # makes deeply frozen and so shareable between Ractors, and it reads
  # back as the table itself.
  def test_the_name_table_is_written_as_a_shareable_ruby_hash
    source = BindingsHelper.generator.files.fetch("lib/lota/error_message/names.rb")
    names = in_tree do |root|
      write(root, "names.rb", source)
      load(File.join(root, "names.rb"), wrap = Module.new)
      wrap::Lota::ErrorMessage::NAMES
    end

    assert_includes source, %(  "love.window.setTitle" => "Lota::Window.title=",\n)
    assert_match(/\A# frozen_string_literal: true\n\n#--\n# SPDX-.*#\+\+\n\n# shareable_constant_value: literal\n\n# GENERATED /m, source)
    assert_equal BindingsHelper.generator.name_table, names
    assert Ractor.shareable?(names)
    refute BindingsHelper.generator.files.key?("ext/lota/native/generated/names.hpp")
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
