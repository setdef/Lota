# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"

# Events reach a game's callbacks with the numbers LÖVE's C++ holds as
# integers as Integers, and the rest as Floats (ADR 001, rule 14). Each
# test pushes an event into SDL's queue, where LÖVE's own Event::convert
# (vendor/love/src/modules/event/sdl/Event.cpp) turns it into a message,
# and Lota's loop then calls the callback.
class EventArgumentsTest < Minitest::Test
  include CallbackHelper

  def setup
    super
    EngineHelper.open_window
    drain
  end

  # Runs one frame of Lota's loop after the block and returns the arguments
  # +callback+ received, or fails if it was not called.
  def received(callback)
    arguments = nil
    define_callback(callback) { |*all| arguments = all }
    yield
    Lota.run.call
    arguments or flunk "#{callback} was not called"
  end

  # Empties the queue of what the system reported before the test, so
  # that a frame handles only what the test pushed.
  def drain
    Lota::Event.pump
    nil while Lota::Callbacks.poll
  end

  # The button is an int and the clicks a Uint8 (Event.cpp:358-379); the
  # position is SDL's float, in DPI-scaled units.
  def test_a_mouse_press_numbers_its_button_and_clicks_with_integers
    x, y, button, istouch, presses = received(:mousepressed) { LotaNativeTest.press_mouse(3) }

    assert_equal [Float, Float], [x.class, y.class]
    assert_equal [2, 2], [button, presses]
    assert_equal [Integer, Integer], [button.class, presses.class]
    refute istouch
  end

  # SDL's Sint32 start and length (Event.cpp:326-327).
  def test_a_text_edit_gives_its_start_and_length_as_integers
    text, start, length = received(:textedited) { LotaNativeTest.edit_text }

    assert_equal "lota", text
    assert_equal [1, -1], [start, length]
    assert_equal [Integer, Integer], [start.class, length.class]
  end

  # The graphics module's int width and height (Event.cpp:811-835).
  def test_a_resize_gives_the_graphics_size_as_integers
    width, height = received(:resize) { LotaNativeTest.resize_window }

    assert_equal Lota::Graphics.dimensions, [width, height]
    assert_equal [Integer, Integer], [width.class, height.class]
  end

  # A key event gives the key's and the scancode's names, which are names
  # in LÖVE and so symbols (Event.cpp:284-317; ADR 001, rule 9). Escape's
  # scancode is 41 on every layout (SDL_scancode.h).
  def test_a_key_press_gives_its_key_and_scancode_as_symbols
    key, scancode, isrepeat = received(:keypressed) { LotaNativeTest.press_key(41, true) }

    assert_equal %i[escape escape], [key, scancode]
    assert_equal false, isrepeat
  end

  def test_a_key_release_gives_its_key_and_scancode_as_symbols
    key, scancode = received(:keyreleased) { LotaNativeTest.press_key(41, false) }

    assert_equal %i[escape escape], [key, scancode]
  end

  # The display's index counts from 1 (Event.cpp:507).
  def test_a_display_rotation_gives_its_display_index_as_an_integer
    display, orientation = received(:displayrotated) { LotaNativeTest.rotate_display }

    assert_equal 1, display
    assert_instance_of Integer, display
    assert_equal :landscape, orientation
  end
end
