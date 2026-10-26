# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Keyboard.down?, which reads SDL's keyboard state as
# love.keyboard.isDown does (keyboard/sdl/Keyboard.cpp:56-72). The tests
# set that state through LotaNativeTest.hold, as the parity harness does,
# since a test cannot press a key.
class KeyboardDownTest < Minitest::Test
  # The keys these tests hold.
  KEYS = %i[right left a n].freeze

  def setup
    EngineHelper.open_window
  end

  def teardown
    KEYS.each { |key| LotaNativeTest.hold(scancode(key), false) }
  end

  # The scancode of +key+. The arrow keys have the same scancodes on every
  # layout (SDL_scancode.h); a letter's depends on the layout, which SDL
  # reads once the window is open, and looks the letter up in, as isDown
  # does.
  def scancode(key)
    case key
    when :right then 79
    when :left then 80
    else LotaNativeTest.scancode(key.to_s.ord)
    end
  end

  def test_a_key_is_down_while_held
    refute Lota::Keyboard.down?(:right)

    LotaNativeTest.hold(scancode(:right), true)

    assert Lota::Keyboard.down?(:right)
    refute Lota::Keyboard.down?(:left)
  end

  def test_any_of_several_keys_being_down_is_enough
    LotaNativeTest.hold(scancode(:left), true)

    assert Lota::Keyboard.down?(:right, :left)
    refute Lota::Keyboard.down?(:right, :a)
  end

  def test_no_keys_are_never_down
    LotaNativeTest.hold(scancode(:a), true)

    refute Lota::Keyboard.down?
  end

  def test_a_key_may_be_named_by_a_string_as_in_lua
    LotaNativeTest.hold(scancode(:a), true)

    assert Lota::Keyboard.down?("a")
  end

  # LÖVE 12 reads a name that is no key constant as the key of its first
  # character (keyboard/Keyboard.cpp:36-64), so :nope is the N key.
  def test_a_name_that_is_no_key_constant_is_the_key_of_its_first_character
    LotaNativeTest.hold(scancode(:n), true)

    assert Lota::Keyboard.down?(:nope)
  end

  # A name with no first character, or one that is not UTF-8, names no
  # key, and every name is checked before any key is.
  def test_a_name_of_no_character_raises_loves_error
    LotaNativeTest.hold(scancode(:a), true)

    empty = assert_raises(ArgumentError) { Lota::Keyboard.down?(:a, "") }
    invalid = assert_raises(ArgumentError) { Lota::Keyboard.down?(:a, "\xFF".b) }

    assert_equal "Invalid key constant: ", empty.message
    assert_equal "Invalid key constant: \xFF".b, invalid.message.b
  end

  # LÖVE's thread module forbids only love.window and love.graphics on its
  # threads (thread/LuaThread.cpp:72-73), so love.keyboard runs anywhere.
  def test_it_answers_off_the_main_thread
    LotaNativeTest.hold(scancode(:a), true)

    assert Thread.new { Lota::Keyboard.down?(:a) }.value
  end

  def test_lota_keyboard_is_the_module
    assert_same Lota::Keyboard, Lota.keyboard
  end
end
