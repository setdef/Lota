# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The rest of Lota::Keyboard, translated from love.keyboard
# (vendor/love/src/modules/keyboard/wrap_Keyboard.cpp): scancodes, key
# repeat, text input, and the conversions between a key and the scancode
# that types it. Lövetest checks only that these answer
# (test/lovetest/tests/keyboard.rb); these check what they answer. They
# set the keyboard state through LotaNativeTest.hold, as keyboard_test.rb
# does, and never touch the person's keyboard.
class KeyboardSettingsTest < Minitest::Test
  # SDL_SCANCODE_A, B, and SPACE, the same on every layout (SDL_scancode.h).
  SCANCODES = { a: 4, b: 5, space: 44 }.freeze

  def setup
    EngineHelper.open_window
  end

  def teardown
    SCANCODES.each_value { |scancode| LotaNativeTest.hold(scancode, false) }
    Lota::Keyboard.key_repeat = false
    Lota::Keyboard.text_input = false
  end

  def test_a_scancode_is_down_while_held
    refute Lota::Keyboard.scancode_down?(:a)

    LotaNativeTest.hold(SCANCODES.fetch(:a), true)

    assert Lota::Keyboard.scancode_down?(:a)
    refute Lota::Keyboard.scancode_down?(:b)
  end

  def test_any_of_several_scancodes_being_down_is_enough_and_none_is_never_down
    LotaNativeTest.hold(SCANCODES.fetch(:space), true)

    assert Lota::Keyboard.scancode_down?(:a, :space)
    refute Lota::Keyboard.scancode_down?(:a, :b)
    refute Lota::Keyboard.scancode_down?
  end

  # LÖVE reads its keys from one table when the first argument is one
  # (wrap_Keyboard.cpp:49-62 and 89-102), which Ruby passes as an Array.
  def test_a_table_of_keys_or_scancodes_is_an_array
    LotaNativeTest.hold(SCANCODES.fetch(:a), true)
    LotaNativeTest.hold(SCANCODES.fetch(:space), true)

    assert Lota::Keyboard.scancode_down?(%i[b a])
    refute Lota::Keyboard.scancode_down?([:b])
    assert Lota::Keyboard.down?(%i[left space])
    refute Lota::Keyboard.down?([:left])
    refute Lota::Keyboard.down?([])
  end

  def test_a_scancode_may_be_named_by_a_string_as_in_lua
    LotaNativeTest.hold(SCANCODES.fetch(:a), true)

    assert Lota::Keyboard.scancode_down?("a")
  end

  # Every name is checked before the module is asked (wrap_Keyboard.cpp:
  # 106-108), whichever the held scancode.
  def test_a_name_that_is_no_scancode_raises_loves_error
    LotaNativeTest.hold(SCANCODES.fetch(:a), true)

    error = assert_raises(ArgumentError) { Lota::Keyboard.scancode_down?(:a, :nope) }

    assert_equal "Invalid scancode: nope", error.message
  end

  def test_key_repeat_is_off_until_a_game_turns_it_on
    refute_predicate Lota::Keyboard, :key_repeat?

    Lota::Keyboard.key_repeat = true

    assert_predicate Lota::Keyboard, :key_repeat?

    Lota::Keyboard.key_repeat = false

    refute_predicate Lota::Keyboard, :key_repeat?
  end

  def test_text_input_follows_the_writer
    Lota::Keyboard.text_input = false

    refute_predicate Lota::Keyboard, :text_input?

    Lota::Keyboard.text_input = true

    assert_predicate Lota::Keyboard, :text_input?
  end

  # The form with a rectangle (wrap_Keyboard.cpp:166-174) turns text input
  # on or off as well as placing it, and wants all four numbers, which it
  # reads in order, so the first one missing is the one named.
  # Keyboard::setTextInput (keyboard/sdl/Keyboard.cpp:147-165) converts
  # them from DPI-scaled units to the window's coordinates, through the
  # window's pixels, and truncates them for SDL.
  def test_text_input_with_a_rectangle
    Lota::Keyboard.text_input = false, 10, 20, 100, 30

    refute_predicate Lota::Keyboard, :text_input?
    assert_equal [10, 20, 100, 30].map { |n| window_coordinate(n) }, LotaNativeTest.text_input_area

    Lota::Keyboard.text_input = true, 10.5, 21.75, 101, 33

    assert_predicate Lota::Keyboard, :text_input?
    assert_equal [10.5, 21.75, 101, 33].map { |n| window_coordinate(n) }, LotaNativeTest.text_input_area
    error = assert_raises(ArgumentError) { Lota::Keyboard.text_input = true, 10, 20 }

    assert_equal "Missing argument. Name: w.", error.message
  end

  # +units+ as Window::DPIToWindowCoords converts them (window/sdl/
  # Window.cpp:1375-1390) and the SDL_Rect truncates them.
  private def window_coordinate(units)
    width, = Lota::Window.mode
    (units * Lota::Window.dpi_scale * width / Lota::Graphics.pixel_width).to_i
  end

  def test_a_computer_has_no_screen_keyboard_showing
    assert_includes [true, false], Lota::Keyboard.screen_keyboard?
    refute_predicate Lota::Keyboard, :screen_keyboard_visible?
  end

  # A key with the same name as its scancode on every layout, and a key that
  # types a character, which round-trips on the layout the tests run on.
  def test_keys_and_scancodes_convert_to_each_other_as_symbols
    assert_equal :space, Lota::Keyboard.scancode_from_key(:space)
    assert_equal :space, Lota::Keyboard.key_from_scancode(:space)
    assert_equal :left, Lota::Keyboard.scancode_from_key("left")
    assert_equal :a, Lota::Keyboard.key_from_scancode(Lota::Keyboard.scancode_from_key(:a))
  end

  def test_a_name_that_is_neither_raises_loves_error
    assert_equal "Invalid key constant: ", assert_raises(ArgumentError) { Lota::Keyboard.scancode_from_key("") }.message
    assert_equal "Invalid scancode: nope", assert_raises(ArgumentError) { Lota::Keyboard.key_from_scancode(:nope) }.message
    assert_equal "Invalid modifier keys: nope", assert_raises(ArgumentError) { Lota::Keyboard.modifier_active?(:nope) }.message
  end

  def test_a_modifier_is_a_lock_that_is_on_or_off
    %i[numlock capslock scrolllock mode].each do |modifier|
      assert_includes [true, false], Lota::Keyboard.modifier_active?(modifier), modifier.to_s
    end
  end
end

# KeyboardSettingsTest ends each test with text input off, as a window
# opens with it (Lota::Keyboard.text_input=), so that a test run after it,
# in the same process, finds it as a game starts. Without that, this
# fails with text input on, where the test it runs left it.
class KeyboardSettingsTextInputTest < Minitest::Test
  def test_a_keyboard_settings_test_leaves_text_input_off
    EngineHelper.open_window
    Lota::Keyboard.text_input = false

    assert_predicate KeyboardSettingsTest.new("test_text_input_follows_the_writer").run, :passed?

    refute_predicate Lota::Keyboard, :text_input?
  ensure
    Lota::Keyboard.text_input = false
  end
end
