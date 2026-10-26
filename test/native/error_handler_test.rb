# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"

# Lota.errorhandler, translated from love.errorhandler
# (vendor/love/src/modules/love/callbacks.lua:221-349), in this process's
# window. No published LÖVE game crashes on purpose, and the Lua side of a
# parity test must not be written for it, so these tests check the
# translation against the lines of callbacks.lua each cites: what it
# prints, the text it shows and copies, where and in what colors it draws
# it, and how its frame answers the player.
class ErrorHandlerTest < Minitest::Test
  include CallbackHelper

  ESCAPE = 41
  LCTRL = 224

  # An error raised in a game's update, with the backtrace Lota's loop
  # gives one: the game's frame, Lota's callbacks.rb and boot.rb, and the
  # lota executable.
  def error(message = "boom")
    RuntimeError.new(message).tap do |error|
      error.set_backtrace([
        "/game/main.rb:3:in 'Lota.update'",
        "/lota/lib/lota/callbacks.rb:56:in 'Lota::Callbacks.call'",
        "/lota/lib/lota/boot.rb:119:in 'Lota::Boot#call'",
        "/lota/exe/lota:5:in '<main>'",
      ])
    end
  end

  # The window opens first, so that CallbackHelper takes away the
  # Lota.errorhandler test/lovetest/conf.rb defines when it boots.
  def setup
    EngineHelper.open_window
    super
    Lota::Event.pump
    Lota::Event.clear
    @font = Lota::Graphics.font
    @default_filter = Lota::Graphics.default_filter
    @line_style = Lota::Graphics.line_style
  end

  # The handler resets the drawing state (line 258); the tests that share
  # this process expect what Lövetest's love.load set.
  def teardown
    LotaNativeTest.hold(LCTRL, false)
    Lota::Event.clear
    Lota::Graphics.reset
    Lota::Graphics.font = @font
    Lota::Graphics.default_filter = @default_filter
    Lota::Graphics.line_style = @line_style
    Lota::Graphics.line_width = 1
    super
  end

  # The handler and its first frame, with what the handler printed.
  def handled(error = self.error)
    frame = nil
    out, = capture_io { frame = Lota.errorhandler(error) }
    [frame, out]
  end

  # error_printer (lines 217-219 and 224): "Error: ", the error, and the traceback
  # without its last line.
  def test_the_handler_prints_the_error_and_its_traceback_without_the_last_frame
    _, out = handled

    assert_equal <<~OUT, out
      Error: /game/main.rb:3:in 'Lota.update': boom (RuntimeError)
      stack traceback:
      \t/game/main.rb:3:in 'Lota.update'
      \t/lota/lib/lota/callbacks.rb:56:in 'Lota::Callbacks.call'
      \t/lota/lib/lota/boot.rb:119:in 'Lota::Boot#call'
    OUT
  end

  # Lines 263-293: "Error", the message, and the traceback under
  # "Traceback", without boot.rb's frames and without tabs, which Ctrl+C
  # copies (lines 304-309 and 324-325).
  def test_ctrl_c_copies_the_error_and_its_traceback
    frame, = handled
    LotaNativeTest.hold(LCTRL, true)
    LotaNativeTest.press_key(LotaNativeTest.scancode("c".ord), true)

    assert_nil frame.call
    assert_equal "Error\n\n/game/main.rb:3:in 'Lota.update': boom (RuntimeError)\n\n\nTraceback\n\n" \
      "/game/main.rb:3:in 'Lota.update'\n/lota/lib/lota/callbacks.rb:56:in 'Lota::Callbacks.call'\n" \
      "/lota/exe/lota:5:in '<main>'", Lota::System.clipboard_text
  end

  # c without Ctrl copies nothing (line 324).
  def test_c_alone_copies_nothing
    Lota::System.clipboard_text = "before"
    frame, = handled
    LotaNativeTest.press_key(LotaNativeTest.scancode("c".ord), true)

    assert_nil frame.call
    assert_equal "before", Lota::System.clipboard_text
  end

  # Lines 267-280: bytes that start no UTF-8 character are dropped, and a
  # line says so.
  def test_an_error_whose_text_is_not_utf8_is_shown_without_its_stray_bytes
    frame, = handled(error("bad \xFF byte".b))
    LotaNativeTest.hold(LCTRL, true)
    LotaNativeTest.press_key(LotaNativeTest.scancode("c".ord), true)
    frame.call

    assert Lota::System.clipboard_text.start_with?("Error\n\n/game/main.rb:3:in 'Lota.update': bad  byte " \
      "(RuntimeError)\nInvalid UTF-8 string in error message.\n\n\nTraceback\n\n"), Lota::System.clipboard_text
  end

  # Lines 318-323: Escape and a quit end the screen, a quit
  # with its own status or 1.
  def test_escape_ends_the_screen_with_1
    frame, = handled
    LotaNativeTest.press_key(ESCAPE, true)

    assert_equal 1, frame.call
  end

  def test_a_quit_ends_the_screen_with_its_status_or_1
    frame, = handled
    Lota::Event.quit(4)

    assert_equal 4, frame.call

    Lota::Event.quit

    assert_equal 1, frame.call
  end

  # Lines 296-302 and 342-346: each frame clears the window to LÖVE's blue
  # and prints the text in white from (60, 60), then sleeps.
  def test_the_frame_draws_the_text_in_white_on_loves_blue_from_60_60
    frame, = handled
    frames = []
    Lota::Native::Graphics.capture_screenshot(-> (image) { frames << Lota::Image::ImageData.from_native(image) })

    assert_nil frame.call
    image = frames.fetch(0)
    blue = [89 / 255.0, 157 / 255.0, 220 / 255.0, 1.0]
    [[0, 0], [59, 59], [image.width - 1, image.height - 1]].each do |x, y|
      image.pixel(x, y).zip(blue).each { |actual, expected| assert_in_delta expected, actual, 0.5 / 255 }
    end
    text = (60...80).flat_map { |y| (60...110).map { |x| image.pixel(x, y) } }

    assert(text.any? { |r, g, b, _a| [r, g, b].all? { |component| component > 0.99 } }, "the word Error in white")
  end

  # Lines 241-261: the mouse is shown and set free, and the
  # drawing state reset, before the screen draws in a font of 15 pixels.
  def test_the_handler_resets_the_mouse_and_the_drawing_state
    Lota::Mouse.visible = false
    Lota::Graphics.color = 1, 0, 0, 0.5
    Lota::Graphics.line_width = 3
    handled

    assert_predicate Lota::Mouse, :visible?
    refute_predicate Lota::Mouse, :grabbed?
    refute Lota::Mouse.relative_mode
    assert_equal [1.0, 1.0, 1.0, 1.0], Lota::Graphics.color
    assert_in_delta 1.0, Lota::Graphics.line_width
    assert_equal :smooth, Lota::Graphics.line_style
  end

  # boot.lua calls love.errorhandler, or love.errhand only without it
  # (boot.lua:476), and love.errhand is the same handler
  # (callbacks.lua:351-352).
  def test_errhand_is_the_same_handler
    errhand = Lota::DefaultCallbacks.instance_method(:errhand)

    assert_equal :errorhandler, errhand.original_name
    assert_equal Lota::DefaultCallbacks.instance_method(:errorhandler), errhand
  end
end
