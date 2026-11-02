# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.timer tests (vendor/love/testing/tests/timer.lua),
# translated to Ruby by ADR 001's rules, all six. Like the graphics tests,
# they run in the test suite's own process (test/lovetest/timer_test.rb)
# and under lota run (test/lovetest/game).
class TimerTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.timer.getAverageDelta,
  # love.test.timer.getDelta, and love.test.timer.getFPS
  # (vendor/love/testing/tests/timer.lua:13-33): the getters drop get
  # (rule 3), and getFPS is fps (rule 13, which makes FPS one word).
  def test_get_average_delta
    assert_not_nil(Lota::Timer.average_delta)
  end

  def test_get_delta
    assert_not_nil(Lota::Timer.delta)
  end

  def test_get_fps
    assert_not_nil(Lota::Timer.fps)
  end

  # Translated to Ruby from love.test.timer.getTime and
  # love.test.timer.sleep (timer.lua:36-50): Lua's assertRange of a value
  # between two bounds is Minitest's assert_includes on the Range of them.
  def test_get_time
    starttime = Lota::Timer.time
    Lota::Timer.sleep(0.1)
    endtime = Lota::Timer.time - starttime
    assert_includes(0.05..1, endtime, "check 0.1s passes")
  end

  def test_sleep
    starttime = Lota::Timer.time
    Lota::Timer.sleep(0.1)
    assert_includes(0.05..1, Lota::Timer.time - starttime, "check 0.1s passes")
  end

  # Translated to Ruby from love.test.timer.step (timer.lua:53-57).
  def test_step
    assert_not_nil(Lota::Timer.step)
  end
  # SPDX-SnippetEnd
end
