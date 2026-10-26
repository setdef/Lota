# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# ADR 001, section 7: where LÖVE's own C++ raises a message that names a
# Lua module, Lota rewrites the name by rule 1, and a function by the name
# the rules give it in the binding generator's name table, and leaves the
# rest of the message word for word (ext/lota/native/errors.hpp).
class ErrorTranslationTest < Minitest::Test
  include NativeHelper

  PNG = File.binread(File.join(ROOT, "vendor/love/testing/output/expected/love.test.graphics.clear-1.png"))

  # Every message in the LÖVE C++ that Lota compiles that names a Lua
  # module or a method, with what Lota raises instead. The %s in
  # vendor/love/src/modules/event/sdl/Event.cpp:250 is filled in with
  # love.event.pump, love.event.wait, or love.event.clear (lines 129, 213,
  # and 225).
  SURVEYED = {
    # vendor/love/src/modules/image/ImageData.cpp:116
    "love.image must be loaded in order to decode an ImageData." =>
      "Lota::Image must be loaded in order to decode an ImageData.",
    # ImageData.cpp:185
    "love.image must be loaded in order to encode an ImageData." =>
      "Lota::Image must be loaded in order to encode an ImageData.",
    # ImageData.cpp:224
    "love.filesystem must be loaded in order to write an encoded ImageData to a file." =>
      "Lota::Filesystem must be loaded in order to write an encoded ImageData to a file.",
    # vendor/love/src/modules/window/sdl/Window.cpp:477
    "love.window.setMode cannot be called while a render target is active in love.graphics." =>
      "Lota::Window.set_mode cannot be called while a render target is active in Lota::Graphics.",
    # Window.cpp:813
    "love.window.close cannot be called while a render target is active in love.graphics." =>
      "Lota::Window.close cannot be called while a render target is active in Lota::Graphics.",
    # Window.cpp:851
    "love.window.setFullscreen cannot be called while a render target is active in love.graphics." =>
      "Lota::Window.set_fullscreen cannot be called while a render target is active in Lota::Graphics.",
    # vendor/love/src/modules/event/sdl/Event.cpp:250 with line 129
    "love.event.pump cannot be called while a render target is active in love.graphics." =>
      "Lota::Event.pump cannot be called while a render target is active in Lota::Graphics.",
    # Event.cpp:250 with line 213
    "love.event.wait cannot be called while a render target is active in love.graphics." =>
      "Lota::Event.wait cannot be called while a render target is active in Lota::Graphics.",
    # Event.cpp:250 with line 225
    "love.event.clear cannot be called while a render target is active in love.graphics." =>
      "Lota::Event.clear cannot be called while a render target is active in Lota::Graphics.",
    # vendor/love/src/modules/graphics/GraphicsReadback.cpp:152; the bare
    # readbackTexture names no module, so it stays.
    "The love.image module must be loaded for readbackTexture." =>
      "The Lota::Image module must be loaded for readbackTexture.",
    # vendor/love/src/modules/graphics/Graphics.cpp:493
    "love.graphics.readbackBuffer failed." => "Lota::Graphics.readback_buffer failed.",
    # Graphics.cpp:513
    "love.graphics.readbackTexture failed." => "Lota::Graphics.readback_texture failed.",
    # ImageData.cpp:535, with the format's name for %s
    "ImageData:setPixel does not currently support the r16 pixel format." =>
      "Lota::Image::ImageData#pixel= does not currently support the r16 pixel format.",
    # ImageData.cpp:549
    "ImageData:getPixel does not currently support the r16 pixel format." =>
      "Lota::Image::ImageData#pixel does not currently support the r16 pixel format.",
    # ImageData.cpp:760
    "ImageData:paste does not currently support converting from the r16 pixel format." =>
      "Lota::Image::ImageData#paste does not currently support converting from the r16 pixel format.",
  }.freeze

  # The C++ Lota compiles from LÖVE, as the engine's source list names it.
  def self.engine_sources
    list = File.read(File.join(ROOT, "ext/lota/engine/sources_macos.cmake"))
    list.scan(%r{\$\{ENGINE_SOURCE_DIR\}/(\S+)}).flatten.map { |path| File.join(ROOT, "vendor/love", path) }
  end

  # Every function a string in that C++ names, in LÖVE's notation, has the
  # Ruby name the rules give it in the generator's name table, which the
  # translation looks it up in. Names of a module's implementation, such as
  # love.graphics.metal (graphics/metal/Graphics.mm:271), are what
  # Module::getName returns, not functions, and no message names them.
  def test_every_function_the_engines_strings_name_is_in_the_name_table
    names = ErrorTranslationTest.engine_sources.flat_map do |path|
      File.read(path).scan(/"[^"\n]*"/).flat_map { |literal| literal.scan(/\b(?:love\.[a-z]+\.[A-Za-z]\w*|[A-Z]\w*:[a-z]\w*)/) }
    end
    functions = names.uniq.sort.grep_v(/\Alove\.[a-z]+\.(?:sdl|null|openal|physfs|freetype|metal|opengl|vulkan|magpie|lullaby|theora|box)\z/)

    assert_equal %w[
      ImageData:getPixel
      ImageData:paste
      ImageData:setPixel
      love.event.clear
      love.event.pump
      love.event.wait
      love.graphics.readbackBuffer
      love.graphics.readbackTexture
      love.window.close
      love.window.setFullscreen
      love.window.setMode
    ], functions
    functions.each do |name|
      refute_equal name, LotaNativeTest.translate_love_names(name), "#{name} is not in the name table"
    end
  end

  # A name the rules give differently from a snake_case of LÖVE's: a factory
  # becomes a constructor (rule 2), a setter a writer (rule 5), and a
  # predicate drops its "is" (rule 8).
  def test_a_function_takes_the_exact_name_the_rules_give_it
    assert_equal "Lota::Graphics::Canvas.new failed; Lota::Window.title= and Lota::Window.open?",
      LotaNativeTest.translate_love_names("love.graphics.newCanvas failed; love.window.setTitle and love.window.isOpen")
  end

  # A function the name table does not know keeps LÖVE's spelling after
  # its module's Ruby name, and a method it does not know stays as written.
  def test_a_name_the_table_does_not_know_keeps_loves_spelling
    assert_equal "Lota::Graphics.noSuchFunction and Texture:noSuchMethod, at Error: x",
      LotaNativeTest.translate_love_names("love.graphics.noSuchFunction and Texture:noSuchMethod, at Error: x")
  end

  def test_each_surveyed_message_translates
    SURVEYED.each do |love, lota|
      assert_equal lota, LotaNativeTest.translate_love_names(love)
    end
  end

  def test_a_message_without_a_love_name_is_unchanged
    message = "Could not decode file 'x.png' to ImageData: unsupported file format"

    assert_equal message, LotaNativeTest.translate_love_names(message)
  end

  def test_only_a_name_that_starts_a_word_translates
    assert_equal "glove.image and xlove.graphics", LotaNativeTest.translate_love_names("glove.image and xlove.graphics")
  end

  def test_love_alone_or_followed_by_no_module_is_unchanged
    assert_equal "love. love.Image love", LotaNativeTest.translate_love_names("love. love.Image love")
  end

  def test_a_name_at_the_very_end_translates
    assert_equal "in Lota::Graphics", LotaNativeTest.translate_love_names("in love.graphics")
  end

  def test_every_name_in_a_message_translates
    assert_equal "Lota::Image, Lota::Window.set_mode, and (Lota::Graphics)",
      LotaNativeTest.translate_love_names("love.image, love.window.setMode, and (love.graphics)")
  end

  # The real error, from LÖVE's own ImageData constructor, in the test
  # bundle's copy of the engine, where love.image is never opened.
  def test_the_image_data_error_reaches_ruby_translated
    file_data = Lota::Filesystem::FileData.new(PNG, "clear-1.png")
    error = assert_raises(RuntimeError) { LotaNativeTest.decode_without_the_image_module(file_data.native) }

    assert_instance_of RuntimeError, error
    assert_equal "Lota::Image must be loaded in order to decode an ImageData.", error.message
  end

  # The real error, from LÖVE's own Event::pump (Event.cpp:129 and 250),
  # through Lota::Native.
  def test_pumping_events_while_drawing_to_a_canvas_raises_the_engines_error_translated
    EngineHelper.open_window
    Lota::Graphics.canvas = Lota::Graphics::Canvas.new(4, 4)
    error = assert_raises(RuntimeError) { Lota::Native::Event.pump }

    assert_instance_of RuntimeError, error
    assert_equal "Lota::Event.pump cannot be called while a render target is active in Lota::Graphics.",
      error.message
  ensure
    Lota::Graphics.canvas = nil
  end

  # The real error, from LÖVE's own Window::setWindow (Window.cpp:477),
  # through Lota::Native.
  def test_setting_the_mode_while_drawing_to_a_canvas_raises_the_engines_error_translated
    EngineHelper.open_window
    Lota::Graphics.canvas = Lota::Graphics::Canvas.new(4, 4)
    error = assert_raises(RuntimeError) do
      Lota::Native::Window.set_mode(360, 240, Lota::Native::WindowSettings.new)
    end

    assert_equal "Lota::Window.set_mode cannot be called while a render target is active in Lota::Graphics.",
      error.message
  ensure
    Lota::Graphics.canvas = nil
  end

  # Rice's own errors are not LÖVE's, and pass through with their class
  # and message.
  def test_other_errors_keep_their_class_and_message
    error = assert_raises(TypeError) { Lota::Native::Graphics.set_canvas(Object.new) }

    assert_instance_of TypeError, error
    assert_equal "Wrong argument type. Expected Lota::Native::Texture. Received Object.", error.message
  end
end
