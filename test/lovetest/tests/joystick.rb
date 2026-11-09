# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.joystick tests (vendor/love/testing/tests/joystick.lua),
# translated to Ruby by the rules of doc/contributors/design/translation.md, all
# six. Lövetest notes that the module cannot be tested fully without the
# hardware, and LÖVE's CI runs them with none attached;
# test/native/joystick_test.rb plugs in joysticks SDL makes in software. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/joystick_test.rb) and under lota run (test/lovetest/game).
class JoystickTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.joystick.getGamepadMappingString,
  # getJoystickCount, and getJoysticks (vendor/love/testing/tests/
  # joystick.lua:12-30): the getters drop get (rule 3), Lua's table of
  # joysticks is an Array, and assertGreaterEqual(0, n), which checks that
  # n is at least 0, is assert_operator(n, :>=, 0).
  def test_get_gamepad_mapping_string
    mapping = Lota::Joystick.gamepad_mapping_string("faker")
    assert_nil(mapping, "check no mapping for fake gui")
  end

  def test_get_joystick_count
    count = Lota::Joystick.joystick_count
    assert_operator(count, :>=, 0, "check number")
  end

  def test_get_joysticks
    joysticks = Lota::Joystick.joysticks
    assert_operator(joysticks.size, :>=, 0, "check is count")
  end

  # Translated to Ruby from love.test.joystick.loadGamepadMappings and
  # saveGamepadMappings (joystick.lua:34-46): Lua's pcall, which returns
  # false when the call raised, becomes a rescue, and # the String's size.
  def test_load_gamepad_mappings
    ok = begin
      Lota::Joystick.load_gamepad_mappings("fakefile.txt")
      true
    rescue RuntimeError
      false
    end
    assert_equal(false, ok, "check invalid file")
    Lota::Joystick.load_gamepad_mappings("resources/mappings.txt")
  end

  def test_save_gamepad_mappings
    Lota::Joystick.load_gamepad_mappings("resources/mappings.txt")
    mapping = Lota::Joystick.save_gamepad_mappings
    assert_operator(mapping.size, :>=, 0, "check something mapped")
  end

  # Translated to Ruby from love.test.joystick.setGamepadMapping
  # (joystick.lua:50-84): setGamepadMapping returns whether SDL took the
  # mapping, so it stays a method (rule 7), its names are symbols (rule
  # 9), and Lua's nil for the hat's direction is Ruby's.
  def test_set_gamepad_mapping
    guid = "030000005e040000130b000011050000"
    mappings = [
      Lota::Joystick.set_gamepad_mapping(guid, :a, :button, 1, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :b, :button, 2, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :x, :button, 3, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :y, :button, 4, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :back, :button, 5, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :start, :button, 6, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :guide, :button, 7, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :leftstick, :button, 8, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :leftshoulder, :button, 9, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :rightstick, :button, 10, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :rightshoulder, :button, 11, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :dpup, :button, 12, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :dpdown, :button, 13, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :dpleft, :button, 14, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :dpright, :button, 15, nil),
      Lota::Joystick.set_gamepad_mapping(guid, :dpup, :button, 12, :u),
      Lota::Joystick.set_gamepad_mapping(guid, :dpdown, :button, 13, :d),
      Lota::Joystick.set_gamepad_mapping(guid, :dpleft, :button, 14, :l),
      Lota::Joystick.set_gamepad_mapping(guid, :dpright, :button, 15, :r),
      Lota::Joystick.set_gamepad_mapping(guid, :dpup, :hat, 12, :lu),
      Lota::Joystick.set_gamepad_mapping(guid, :dpdown, :hat, 13, :ld),
      Lota::Joystick.set_gamepad_mapping(guid, :dpleft, :hat, 14, :ru),
      Lota::Joystick.set_gamepad_mapping(guid, :dpright, :hat, 15, :rd),
      Lota::Joystick.set_gamepad_mapping(guid, :leftstick, :axis, 8, :c),
    ]
    mappings.each_with_index do |mapping, m|
      assert_equal(true, mapping, "check mapping ##{m + 1}")
    end
  end
  # SPDX-SnippetEnd
end
