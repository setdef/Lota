# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.event tests (vendor/love/testing/tests/event.lua),
# translated to Ruby by ADR 001's rules, all six, two of them skipped as
# Lövetest skips them (pump and wait). Like the graphics tests, they run in
# the test suite's own process (test/lovetest/event_test.rb) and under
# lota run (test/lovetest/game). Lövetest runs each test from its
# love.update, after love.run has taken every message from the queue; in
# the suite's own process nothing has, so each test starts with the queue
# empty, as Lövetest's does. The test of quit relies on Lövetest's
# love.quit, which cancels the quit; here the test takes the message out of
# the queue itself, as no loop is there to hand it to a quit callback, and
# as Lota.run's would end the game that runs the test.
class EventTest < Lovetest::TestMethod
  def setup
    super
    Lota::Event.poll { nil }
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.event.clear, love.test.event.poll,
  # and love.test.event.push (vendor/love/testing/tests/event.lua:12-63):
  # the event names become symbols (rule 9), and Lua's for over
  # love.event.poll a block given to poll (rule 15).
  def test_clear
    # push some events first
    Lota::Event.push(:test, 1, 2, 3)
    Lota::Event.push(:test, 1, 2, 3)
    Lota::Event.push(:test, 1, 2, 3)
    # check after calling clear there are no events left
    Lota::Event.clear
    count = 0
    Lota::Event.poll do |_n, _a, _b, _c, _d, _e, _f|
      count += 1
    end
    assert_equal(0, count, "check no events")
  end

  def test_poll
    # push some events first
    Lota::Event.push(:test, 1, 2, 3)
    Lota::Event.push(:test, 1, 2, 3)
    Lota::Event.push(:test, 1, 2, 3)
    # check poll recieves all events
    count = 0
    Lota::Event.poll do |_n, _a, _b, _c, _d, _e, _f|
      count += 1
    end
    assert_equal(3, count, "check 3 events")
  end

  def test_push
    # check pushing some different types
    Lota::Event.push(:add, 1, 2, 3)
    Lota::Event.push(:ignore, 1, 2, 3)
    Lota::Event.push(:add, 1, 2, 3)
    Lota::Event.push(:ignore, 1, 2, 3)
    count = 0
    Lota::Event.poll do |n, a, b, c, _d, _e, _f|
      count = count + a + b + c if n == :add
    end
    assert_equal(12, count, "check total events")
  end

  # Translated to Ruby from love.test.event.pump and love.test.event.wait
  # (event.lua:44-46 and 78-80), which Lövetest skips because they are
  # used internally. wait is deprecated.
  def test_pump
    skip("used internally")
  end

  def test_wait
    skip("used internally")
  end

  # Translated to Ruby from love.test.event.quit (event.lua:67-73). Lövetest
  # sets love.test.module.fakequit, so that its love.quit keeps the quit
  # from ending the program; this test takes the quit message out of the
  # queue before anything can act on it, which is what that does.
  def test_quit
    Lota::Event.quit(0)
    # if it failed we'd have quit here
    assert_equal([[:quit, 0]], Lota::Event.poll.to_a, "check quit hook called")
  end
  # SPDX-SnippetEnd
end
