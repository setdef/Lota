# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.touch tests (vendor/love/testing/tests/touch.lua),
# translated to Ruby by ADR 001's rules, all three. Lövetest notes that
# the module cannot be tested fully without the hardware, so they check
# only that its functions are there; test/native/touch_test.rb checks
# what they do with fingers pushed through SDL's queue. Like the graphics
# tests, they run in the test suite's own process
# (test/lovetest/touch_test.rb) and under lota run (test/lovetest/game).
class TouchTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.touch.getPosition,
  # love.test.touch.getPressure, and love.test.touch.getTouches
  # (vendor/love/testing/tests/touch.lua:13-31): the getters drop get
  # (rule 3), and Lua's checks that the field is not nil and is a
  # function become Ruby's that the module answers the method.
  def test_get_position
    assert_respond_to(Lota::Touch, :position)
  end

  def test_get_pressure
    assert_respond_to(Lota::Touch, :pressure)
  end

  def test_get_touches
    assert_respond_to(Lota::Touch, :touches)
  end
  # SPDX-SnippetEnd
end
