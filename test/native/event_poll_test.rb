# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Event.poll, translated from love.event.poll, whose Lua iterator
# takes the next message out of the queue each time a for loop asks
# (vendor/love/src/modules/event/wrap_Event.lua, and w_poll_i in
# wrap_Event.cpp:52-65), is an Enumerator that also takes a block (ADR
# 001, rule 15). Lota::Event.push and clear queue and drop messages, as
# w_push and w_clear do (lines 85-121).
class EventPollTest < Minitest::Test
  def setup
    EngineHelper.open_window
    Lota::Event.pump
    Lota::Event.clear
  end

  def teardown
    Lota::Event.clear
  end

  def test_with_a_block_poll_yields_each_message_and_empties_the_queue
    Lota::Event.push(:first, 1, "two", true)
    Lota::Event.push(:second)
    polled = []

    assert_nil(Lota::Event.poll { |name, *arguments| polled << [name, arguments] })
    assert_equal [[:first, [1.0, "two", true]], [:second, []]], polled
    assert_empty Lota::Event.poll.to_a
  end

  # Each step of the Enumerator takes one message, so the queue holds what
  # it has not reached yet, as a Lua loop that breaks early leaves the
  # rest in LÖVE's queue.
  def test_without_a_block_poll_returns_an_enumerator_that_takes_one_message_a_step
    Lota::Event.push(:first, 1)
    Lota::Event.push(:second, 2)
    messages = Lota::Event.poll

    assert_kind_of Enumerator, messages
    assert_equal [:first, 1.0], messages.next
    assert_equal [[:second, 2.0]], Lota::Event.poll.to_a
  end

  # A message without arguments steps as its name alone, as a Lua for loop
  # receives the name alone.
  def test_an_enumerator_reads_the_queue_as_it_is_when_it_runs
    messages = Lota::Event.poll
    Lota::Event.push(:later)

    assert_equal [:later], messages.to_a
  end

  # w_push stops at the first nil it reads (wrap_Event.cpp:92-93).
  def test_a_messages_arguments_end_at_the_first_nil
    Lota::Event.push(:test, 1, nil, 3)

    assert_equal [[:test, 1.0]], Lota::Event.poll.to_a
  end

  def test_a_symbol_argument_is_queued_as_its_name
    Lota::Event.push("keypressed", :space, :space, false)

    assert_equal [[:keypressed, :space, :space, false]], Lota::Event.poll.to_a
  end

  # luax_checkvariant cannot store a table (wrap_Event.cpp:97-101).
  def test_an_argument_an_event_cannot_carry_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Event.push(:test, 1, [2]) }

    assert_equal "Argument 3 can't be stored safely\nExpected boolean, number, string or userdata.", error.message
    assert_empty Lota::Event.poll.to_a
  end

  def test_clear_empties_the_queue
    Lota::Event.push(:test)
    Lota::Event.clear

    assert_empty Lota::Event.poll.to_a
  end

  # The exit status love.event.quit queues is an int in love.cpp's runlove
  # (vendor/love/src/love.cpp:282-283), so it leaves the queue an Integer
  # (ADR 001, rule 14), truncated as the C++ cast truncates it.
  def test_a_quits_status_leaves_the_queue_an_integer
    Lota::Event.quit(3)
    Lota::Event.quit(2.7)
    Lota::Event.quit

    statuses = Lota::Event.poll.map { |_name, status| status }

    assert_equal [3, 2, nil], statuses
    assert_equal [Integer, Integer], statuses.first(2).map(&:class)
  end
end
