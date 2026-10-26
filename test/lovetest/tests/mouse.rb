# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.mouse tests (vendor/love/testing/tests/mouse.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/mouse_test.rb) and under lota run (test/lovetest/game).
# Those of getX, setCursor, and getCursor call functions Lota does not
# bind yet (setPosition, setX, getCursor), so they wait for them. That of
# getRelativeMode leaves relative mode on, which the suite's own process,
# whose later tests move the mouse, cannot afford, so it waits until the
# suite runs each module in a process of its own.
class MouseTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
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
