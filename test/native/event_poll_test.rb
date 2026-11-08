# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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

  # w_push raises when luax_checkvariant makes a Variant of unknown type
  # (wrap_Event.cpp:101-107), as it makes of a function.
  def test_an_argument_an_event_cannot_carry_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Event.push(:test, 1, -> {}) }

    assert_equal "Argument 3 can't be stored safely\nExpected boolean, number, string or userdata.", error.message
    assert_raises(ArgumentError) { Lota::Event.push(:test, Object.new) }
    assert_empty Lota::Event.poll.to_a
  end

  # luax_checkvariant reads a table as a SharedTable of its keys and values,
  # each read as an argument is (runtime.cpp:758-808), and luax_pushvariant
  # makes a table of it again (runtime.cpp:837-853). An Array is the table
  # whose keys are 1 to n, and comes back an Array; numbers come back as
  # Floats, Symbols as their names, and Strings as UTF-8.
  def test_an_array_is_carried_as_a_table_and_comes_back_an_array
    Lota::Event.push(:test, [1, "café", :name, true, [2.5, []]])

    message = Lota::Event.poll.to_a

    assert_equal [[:test, [1.0, "café", "name", true, [2.5, []]]]], message
    assert_equal Encoding::UTF_8, message.dig(0, 1, 1).encoding
  end

  # A table whose keys are not 1 to n comes back a Hash, its keys converted
  # as its values are: they are data, not LÖVE's names, so a Symbol key
  # comes back a String (ADR 001, rule 9, is for enum strings).
  def test_a_hash_is_carried_as_a_table_and_comes_back_a_hash
    Lota::Event.push(:test, { :name => "Ada", "level" => 3, 0 => false, true => [1], 2.5 => { inner: nil } })

    expected = { "name" => "Ada", "level" => 3.0, 0.0 => false, true => [1.0], 2.5 => { "inner" => nil } }

    assert_equal [[:test, expected]], Lota::Event.poll.to_a
  end

  # Lua has one kind of table, so whatever its keys are, a table whose keys
  # are exactly 1 to n is a sequence, and the empty table is one too.
  def test_a_table_whose_keys_are_one_to_n_comes_back_an_array_whatever_it_was
    Lota::Event.push(:test, { 2 => "b", 1 => "a" }, {}, { 1 => "a", 3 => "c" }, { 1.5 => "x" })

    assert_equal [[:test, %w[a b], [], { 1.0 => "a", 3.0 => "c" }, { 1.5 => "x" }]], Lota::Event.poll.to_a
  end

  # Unlike an argument, a value in a table does not end the table at nil:
  # the SharedTable holds each pair Ruby has.
  def test_a_nil_in_a_table_is_carried
    Lota::Event.push(:test, [1, nil, 3], { nil => 1, "gone" => nil })

    assert_equal [[:test, [1.0, nil, 3.0], { nil => 1.0, "gone" => nil }]], Lota::Event.poll.to_a
  end

  # A table with a key or value of unknown type is one itself
  # (runtime.cpp:784-808), which w_push refuses.
  def test_a_table_holding_a_proc_cannot_be_stored
    error = assert_raises(ArgumentError) { Lota::Event.push(:test, 1, [[-> {}]]) }

    assert_equal "Argument 3 can't be stored safely\nExpected boolean, number, string or userdata.", error.message
    assert_raises(ArgumentError) { Lota::Event.push(:test, { 1.method(:+) => 1 }) }
    assert_empty Lota::Event.poll.to_a
  end

  # luax_checkvariant keeps the tables it is inside of and raises when one
  # holds itself (runtime.cpp:768-774), but reads a table twice when it is
  # only shared.
  def test_a_table_that_holds_itself_raises_and_a_shared_one_is_carried
    cycle = [1]
    cycle << { again: cycle }
    error = assert_raises(RuntimeError) { Lota::Event.push(:test, cycle) }

    assert_equal "Cycle detected in table", error.message

    shared = [1]
    Lota::Event.push(:test, [shared, shared])

    assert_equal [[:test, [[1.0], [1.0]]]], Lota::Event.poll.to_a
  end

  def test_a_value_in_a_table_that_lua_has_no_counterpart_of_raises_type_error
    error = assert_raises(TypeError) { Lota::Event.push(:test, [1..2]) }

    assert_equal "wrong argument type Range (expected nil, true, false, a number, a String, a Symbol, an Array, " \
      "a Hash, or a Proc)", error.message
    assert_empty Lota::Event.poll.to_a
  end

  # Lota::Native reads only the tokens Lota::Variant writes, and refuses
  # any others rather than read past them.
  def test_the_engine_refuses_tokens_that_are_not_one_value
    [[], [:table], [:table, 1, 1.0], [1.0, 2.0], [:table, 2, 1.0, 2.0]].each do |tokens|
      assert_raises(ArgumentError, tokens.inspect) { Lota::Native::Event.push("test", [tokens]) }
    end
    assert_empty Lota::Event.poll.to_a
  end

  # Lua's own stack bounds how deep a table can be. Ruby's bounds Lota's,
  # which raises SystemStackError rather than overflow the machine's.
  def test_a_table_too_deep_for_the_stack_raises_system_stack_error
    deep = 1_000_000.times.reduce([]) { |inner, _| [inner] }

    assert_raises(SystemStackError) { Lota::Event.push(:test, deep) }
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
