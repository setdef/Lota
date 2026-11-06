# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.keyboard tests (vendor/love/testing/tests/keyboard.lua),
# translated to Ruby by ADR 001's rules, all ten. Like the graphics tests,
# they run in the test suite's own process (test/lovetest/keyboard_test.rb)
# and under lota run (test/lovetest/game). The tests of key repeat and text
# input change settings Lövetest leaves changed; these put them back, so
# that a test that follows finds what Lota's loop starts a game with.
class KeyboardTest < Lovetest::TestMethod
  def teardown
    Lota::Keyboard.key_repeat = false
    Lota::Keyboard.text_input = false
    super
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.keyboard.getKeyFromScancode and
  # love.test.keyboard.getScancodeFromKey
  # (vendor/love/testing/tests/keyboard.lua:13-21): getKeyFromScancode
  # becomes key_from_scancode and getScancodeFromKey scancode_from_key
  # (rule 3), and Lua's check that the field is a function Ruby's that the
  # module answers the method.
  def test_get_key_from_scancode
    assert_respond_to(Lota::Keyboard, :key_from_scancode)
  end

  def test_get_scancode_from_key
    assert_respond_to(Lota::Keyboard, :scancode_from_key)
  end

  # Translated to Ruby from love.test.keyboard.hasKeyRepeat,
  # hasScreenKeyboard, and hasTextInput (keyboard.lua:25-42): the
  # predicates drop has and gain ? (rule 8).
  def test_has_key_repeat
    enabled = Lota::Keyboard.key_repeat?
    assert_not_nil(enabled)
  end

  def test_has_screen_keyboard
    enabled = Lota::Keyboard.screen_keyboard?
    assert_not_nil(enabled)
  end

  def test_has_text_input
    enabled = Lota::Keyboard.text_input?
    assert_not_nil(enabled)
  end

  # Translated to Ruby from love.test.keyboard.isDown
  # (vendor/love/testing/tests/keyboard.lua:46-49): isDown becomes down?
  # (rule 8), and the key's name a symbol (rule 9).
  def test_is_down
    keydown = Lota::Keyboard.down?(:a)
    assert_not_nil(keydown)
  end

  # Translated to Ruby from love.test.keyboard.isScancodeDown
  # (keyboard.lua:53-56): isScancodeDown becomes scancode_down? (rule 8).
  def test_is_scancode_down
    keydown = Lota::Keyboard.scancode_down?(:a)
    assert_not_nil(keydown)
  end

  # Translated to Ruby from love.test.keyboard.setKeyRepeat
  # (keyboard.lua:60-64): setKeyRepeat becomes the writer key_repeat=
  # (rule 5).
  def test_set_key_repeat
    Lota::Keyboard.key_repeat = true
    enabled = Lota::Keyboard.key_repeat?
    assert_equal(true, enabled, "check key repeat set")
  end

  # Translated to Ruby from love.test.keyboard.isModifierActive
  # (keyboard.lua:68-77).
  def test_is_modifier_active
    active1 = Lota::Keyboard.modifier_active?(:numlock)
    active2 = Lota::Keyboard.modifier_active?(:capslock)
    active3 = Lota::Keyboard.modifier_active?(:scrolllock)
    active4 = Lota::Keyboard.modifier_active?(:mode)
    assert_not_nil(active1)
    assert_not_nil(active2)
    assert_not_nil(active3)
    assert_not_nil(active4)
  end

  # Translated to Ruby from love.test.keyboard.setTextInput
  # (keyboard.lua:81-84): setTextInput becomes the writer text_input=
  # (rule 5).
  def test_set_text_input
    Lota::Keyboard.text_input = false
    assert_equal(false, Lota::Keyboard.text_input?, "check disable text input")
  end
  # SPDX-SnippetEnd
end
