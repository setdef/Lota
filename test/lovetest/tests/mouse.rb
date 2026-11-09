# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"
require_relative "../held_foreground"

# Lövetest's love.mouse tests (vendor/love/testing/tests/mouse.lua),
# translated to Ruby by ADR 001's rules, all 18 of them. Like the graphics
# tests, they run in the test suite's own process
# (test/lovetest/mouse_test.rb) and under lota run (test/lovetest/game).
class MouseTest < Lovetest::TestMethod
  # Lövetest runs a module's tests in the order of their names
  # (classes/TestModule.lua:68-71), so getCursor, which expects the
  # default cursor, runs before setCursor, which leaves the hand, and
  # getRelativeMode, which leaves relative mode on, before
  # setRelativeMode, which turns it off at its end. Minitest runs them in
  # random order, among the other modules' tests in the suite's own
  # process, which move the mouse, so each test here ends with the default
  # cursor and relative mode off, as getCursor finds them in Lövetest.
  def teardown
    if Lota.mouse
      Lota::Mouse.cursor = nil
      Lota::Mouse.set_relative_mode(false)
    end
    super
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.mouse.getCursor,
  # love.test.mouse.newCursor, and love.test.mouse.setCursor
  # (vendor/love/testing/tests/mouse.lua:13-23 and 102-125): getCursor
  # becomes cursor (rule 3), setCursor the writer cursor= (rule 5), whose
  # call with no cursor is cursor = nil, isCursorSupported
  # cursor_supported? (rule 8), and newCursor Cursor.new (rule 2), and
  # test:skipTest Minitest's skip. Minitest refuses assert_equal with nil,
  # so Lua's assertEquals(nil, ...) becomes assert_nil.
  def test_get_cursor
    cursor = Lota::Mouse.cursor
    assert_nil(cursor, "check nil initially")
    # try setting a cursor to check return if supported
    if Lota::Mouse.cursor_supported?
      Lota::Mouse.cursor = Lota::Mouse.system_cursor(:hand)
      newcursor = Lota::Mouse.cursor
      assert_object(newcursor)
      Lota::Mouse.cursor = nil
    end
  end

  def test_new_cursor
    # new cursor might fail if not supported
    skip("cursor not supported on this system") unless Lota::Mouse.cursor_supported?

    cursor = Lota::Mouse::Cursor.new("resources/love.png", 0, 0)
    assert_object(cursor)
  end

  def test_set_cursor
    # cant set cursor if not supported
    skip("cursor not supported on this system") unless Lota::Mouse.cursor_supported?

    Lota::Mouse.cursor = nil
    assert_nil(Lota::Mouse.cursor, "check reset")
    Lota::Mouse.cursor = Lota::Mouse.system_cursor(:hand)
    assert_object(Lota::Mouse.cursor)
  end

  # Translated to Ruby from love.test.mouse.getRelativeMode
  # (mouse.lua:36-41): getRelativeMode becomes relative_mode (rule 3), and
  # setRelativeMode stays set_relative_mode, as it returns whether it
  # could (rule 7).
  def test_get_relative_mode
    enabled = Lota::Mouse.relative_mode
    assert_equal(false, enabled, "check relative mode")
    Lota::Mouse.set_relative_mode(true)
    assert_equal(true, Lota::Mouse.relative_mode, "check enabling")
  end

  # Translated to Ruby from love.test.mouse.getSystemCursor
  # (vendor/love/testing/tests/mouse.lua:45-50): getSystemCursor becomes
  # system_cursor (rule 3), with the cursor's name a symbol (rule 9). Lua's
  # pcall, which returns false when the call raised, becomes a rescue.
  def test_get_system_cursor
    hand = Lota::Mouse.system_cursor(:hand)
    assert_object(hand)
    ok = begin
      Lota::Mouse.system_cursor(:love)
      true
    rescue ArgumentError
      false
    end
    assert_equal(false, ok, "check invalid cursor")
  end

  # Translated to Ruby from love.test.mouse.isCursorSupported,
  # love.test.mouse.isGrabbed, and love.test.mouse.isVisible
  # (vendor/love/testing/tests/mouse.lua:74-76 and 86-98): isX becomes x?
  # (rule 8), and setVisible the writer visible= (rule 5).
  def test_is_cursor_supported
    assert_not_nil(Lota::Mouse.cursor_supported?)
  end

  # Translated to Ruby from love.test.mouse.getPosition,
  # love.test.mouse.getX, love.test.mouse.getY, love.test.mouse.isDown,
  # love.test.mouse.setPosition, love.test.mouse.setX, and
  # love.test.mouse.setY (vendor/love/testing/tests/mouse.lua:27-32, 54-71,
  # 80-82, 138-147, and 171-187): getPosition becomes position (rule 3),
  # whose two values come back as an Array (rule 4), setPosition the writer
  # position= of an Array (rule 6), getX and getY x and y (rule 3), setX
  # and setY the writers x= and y= (rule 5), and isDown down? (rule 8).
  # Lua's numbers compare equal to Ruby's Integers and Floats alike.
  def test_get_position
    Lota::Mouse.position = 0, 0 # cant predict
    x, y = Lota::Mouse.position
    assert_equal(0, x, "check x pos")
    assert_equal(0, y, "check y pos")
  end

  def test_get_x
    Lota::Mouse.position = 0, 0 # cant predict
    x = Lota::Mouse.x
    assert_equal(0, x, "check x pos")
    Lota::Mouse.x = 10
    assert_equal(10, Lota::Mouse.x, "check set x")
  end

  def test_get_y
    Lota::Mouse.position = 0, 0 # cant predict
    y = Lota::Mouse.y
    assert_equal(0, y, "check x pos")
    Lota::Mouse.y = 10
    assert_equal(10, Lota::Mouse.y, "check set y")
  end

  def test_is_down
    assert_not_nil(Lota::Mouse.down?)
  end

  def test_set_position
    Lota::Mouse.position = 10, 10
    x, y = Lota::Mouse.position
    assert_equal(10, x, "check x position")
    assert_equal(10, y, "check y position")
    Lota::Mouse.position = 15, 20
    x2, y2 = Lota::Mouse.position
    assert_equal(15, x2, "check new x position")
    assert_equal(20, y2, "check new y position")
  end

  def test_set_x
    Lota::Mouse.x = 30
    x = Lota::Mouse.x
    assert_equal(30, x, "check x pos")
    Lota::Mouse.x = 10
    assert_equal(10, Lota::Mouse.x, "check set x")
  end

  def test_set_y
    Lota::Mouse.y = 12
    y = Lota::Mouse.y
    assert_equal(12, y, "check x pos")
    Lota::Mouse.y = 10
    assert_equal(10, Lota::Mouse.y, "check set y")
  end

  def test_is_grabbed
    assert_not_nil(Lota::Mouse.grabbed?)
  end

  def test_is_visible
    visible = Lota::Mouse.visible?
    assert_equal(true, visible, "check visible default")
    Lota::Mouse.visible = false
    assert_equal(false, Lota::Mouse.visible?, "check invisible")
    Lota::Mouse.visible = true
  end

  # Translated to Ruby from love.test.mouse.setGrabbed,
  # love.test.mouse.setRelativeMode, and love.test.mouse.setVisible
  # (vendor/love/testing/tests/mouse.lua:129-134 and 151-167):
  # setGrabbed becomes the writer grabbed= (rule 5), setRelativeMode stays
  # set_relative_mode, as it returns whether it could (rule 7), and
  # getRelativeMode becomes relative_mode (rule 3).
  def test_set_grabbed
    skip(HeldForeground::REASON) if HeldForeground.on?
    assert_equal(false, Lota::Mouse.grabbed?, "check not grabbed")
    Lota::Mouse.grabbed = true
    assert_equal(true, Lota::Mouse.grabbed?, "check now grabbed")
    Lota::Mouse.grabbed = false
  end

  def test_set_relative_mode
    Lota::Mouse.set_relative_mode(true)
    enabled = Lota::Mouse.relative_mode
    assert_equal(true, enabled, "check relative mode")
    Lota::Mouse.set_relative_mode(false)
    assert_equal(false, Lota::Mouse.relative_mode, "check disabling")
  end

  def test_set_visible
    visible = Lota::Mouse.visible?
    assert_equal(true, visible, "check visible default")
    Lota::Mouse.visible = false
    assert_equal(false, Lota::Mouse.visible?, "check invisible")
    Lota::Mouse.visible = true
  end
  # SPDX-SnippetEnd
end
