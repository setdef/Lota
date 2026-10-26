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
# bind yet (setPosition, setX, getCursor, isCursorSupported), so they wait
# for them.
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
  # SPDX-SnippetEnd
end
