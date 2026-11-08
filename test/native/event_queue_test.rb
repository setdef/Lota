# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The rest of Lota::Event, translated from love.event
# (vendor/love/src/modules/event/wrap_Event.cpp): waiting for a message,
# restarting, and the callable that draws the window while the system
# resizes it. Lövetest skips wait and pump and checks neither restart nor
# the modal draw (test/lovetest/tests/event.rb). Messages come into SDL's
# queue through LotaNativeTest, as in event_arguments_test.rb, and never
# from the person's keyboard.
class EventQueueTest < Minitest::Test
  # SDL_SCANCODE_SPACE.
  SPACE = 44

  def setup
    EngineHelper.open_window
    Lota::Event.clear
  end

  # Draws, as the system's live resize does: the event reaches the pump from
  # inside it (LotaNativeTest.request_modal_draw), which calls the callback
  # and passes on its results, and the window's exposed message follows
  # whatever the callback queued.
  def resize_and_pump
    LotaNativeTest.request_modal_draw
    Lota::Event.pump
  end

  # The messages the system sends a window on its own, as the window is
  # shown, covered, resized, or given focus (event/sdl/Event.cpp,
  # convertWindowEvent). Which of them arrive, and when, is up to the
  # system, so a test that asks what a callback queued cannot count them:
  # CI's runner sent an occluded message in the middle of two of these
  # tests, and an exposed message follows every live resize.
  WINDOW_MESSAGES = %i[exposed occluded visible focus mousefocus resize displayrotated themechanged].freeze

  # What the queue holds, but for the messages the system sends a window
  # on its own.
  def queued
    Lota::Event.poll.to_a.map { |message| Array(message) }.reject { |message| WINDOW_MESSAGES.include?(message.first) }
  end

  def teardown
    Lota::Event.modal_draw_callback = nil
    Lota::Event.clear
  end

  # w_wait (wrap_Event.cpp:74-88) takes the next message SDL has and
  # returns its name and arguments, after marking itself deprecated. SDL
  # may hold a message of the system's first, as a mouse the person moves,
  # so this waits until the key arrives.
  def test_wait_returns_the_next_message_as_one_array_and_says_it_is_deprecated
    Lota::Deprecation.instance_variable_get(:@deprecated).delete("Lota::Event.wait")
    LotaNativeTest.press_key(SPACE, true)
    message = nil
    printed, = capture_io do
      20.times do
        message = Lota::Event.wait
        break if message&.first == :keypressed
      end
    end

    assert_equal [:keypressed, :space, :space, false], message
    assert_match(
      /\ALota - Warning: #{Regexp.escape(__FILE__)}:\d+: Using deprecated function Lota::Event.wait \(replaced by waitTimeout parameter in Lota::Event.pump\)\n\z/,
      printed,
    )
  ensure
    LotaNativeTest.press_key(SPACE, false)
  end

  # w_restart (wrap_Event.cpp:138-153) queues a quit message whose first
  # argument is "restart", then the arguments it was given.
  def test_restart_queues_a_quit_message_that_says_restart
    assert Lota::Event.restart
    assert Lota::Event.restart(1, "two", true, :three)

    assert_equal [[:quit, "restart"], [:quit, "restart", 1.0, "two", true, "three"]], Lota::Event.poll.to_a
  end

  # Unlike w_push, w_restart reads every argument up to lua_gettop, so a
  # nil, even the last, is carried and does not end the list.
  def test_restart_carries_every_nil_it_is_given
    Lota::Event.restart(nil, 2, nil)

    assert_equal [[:quit, "restart", nil, 2.0, nil]], Lota::Event.poll.to_a
  end

  # luax_checkvariant makes a function a Variant of unknown type
  # (runtime.cpp:722-812), which w_restart keeps without complaint, unlike
  # w_push, and luax_pushvariant gives back as nil (runtime.cpp:854-857).
  def test_restart_keeps_a_proc_as_a_value_that_carries_nothing
    Lota::Event.restart(-> {}, 1.method(:+), 3)

    assert_equal [[:quit, "restart", nil, nil, 3.0]], Lota::Event.poll.to_a
  end

  # luax_checkvariant reads a table as a SharedTable (runtime.cpp:758-808):
  # one whose keys are 1 to n comes back an Array, and any other a Hash.
  def test_restart_carries_a_table
    Lota::Event.restart([1, { level: "two" }], {})

    assert_equal [[:quit, "restart", [1.0, { "level" => "two" }], []]], Lota::Event.poll.to_a
  end

  # A table with a function in it is of unknown type, as the function is
  # (runtime.cpp:784-808), which w_restart keeps, and which leaves the
  # queue as nil.
  def test_restart_keeps_a_table_holding_a_proc_as_a_value_that_carries_nothing
    Lota::Event.restart([1, [-> {}]], { 1.method(:+) => 2 })

    assert_equal [[:quit, "restart", nil, nil]], Lota::Event.poll.to_a
  end

  def test_restart_raises_for_a_table_that_holds_itself
    cycle = {}
    cycle[:self] = cycle
    error = assert_raises(RuntimeError) { Lota::Event.restart(cycle) }

    assert_equal "Cycle detected in table", error.message
    assert_empty Lota::Event.poll.to_a
  end

  # LÖVE also carries its own objects; Lota does not put a Lota::Object in
  # a message yet, nor a value Lua has no counterpart of, in a table or not.
  def test_restart_refuses_what_lota_does_not_carry
    error = assert_raises(TypeError) { Lota::Event.restart(1, Object.new) }

    assert_equal "wrong argument type Object (expected nil, true, false, a number, a String, a Symbol, an Array, " \
      "a Hash, or a Proc)", error.message
    assert_raises(TypeError) { Lota::Event.restart([1..2]) }
    assert_raises(TypeError) { Lota::Event.restart({ Object.new => 1 }) }
    # LÖVE reads a pair's value even when its key is a function.
    assert_raises(TypeError) { Lota::Event.restart({ -> {} => Object.new }) }
    assert_empty Lota::Event.poll.to_a
  end

  # Event::modalDraw (event/Event.cpp:108-130) calls the callable the game
  # set, and does nothing when there is none.
  def test_the_modal_draw_callback_is_called_for_a_live_resize
    calls = 0
    Lota::Event.modal_draw_callback = -> { calls += 1 }
    resize_and_pump

    assert_equal 1, calls

    Lota::Event.modal_draw_callback = nil
    resize_and_pump

    assert_equal 1, calls
  end

  # drawCallback (wrap_Event.cpp:174-199) is given what the frame of a
  # game returns: an exit status, or several values. Event::pump turns them
  # into a quit message in front of the queue (event/sdl/Event.cpp:
  # 184-199), whose third argument says that the callback has handled the
  # quit already.
  def test_what_the_callback_returns_becomes_a_quit_message_at_the_front_of_the_queue
    Lota::Event.push(:later)
    Lota::Event.modal_draw_callback = -> { 3 }
    resize_and_pump

    assert_equal [[:quit, 3, nil, true], [:later]], queued
  end

  def test_several_results_are_an_array
    Lota::Event.modal_draw_callback = -> { [4, "restart"] }
    resize_and_pump

    assert_equal [[:quit, 4, "restart", true]], queued
  end

  # A callable that returns nothing queues nothing, and the callback is
  # called again for each live resize frame: Event::modalDraw skips a draw
  # only while a result or an error waits for the pump (Event.cpp:111-117).
  def test_a_callback_that_returns_nothing_queues_nothing_and_is_called_again
    calls = 0
    Lota::Event.modal_draw_callback = -> { calls += 1; nil }
    resize_and_pump
    resize_and_pump

    assert_equal 2, calls
    assert_empty queued
  end

  def test_an_error_the_callback_raises_comes_out_of_the_next_pump
    Lota::Event.modal_draw_callback = -> { raise "broken draw" }
    LotaNativeTest.request_modal_draw
    error = assert_raises(RuntimeError) { Lota::Event.pump }

    assert_equal "Error in modal draw callback: broken draw", error.message
    Lota::Event.pump # the error was taken
  end

  # drawCallbackInner reads the results with luax_checkvariant
  # (wrap_Event.cpp:161-173), whose error lua_cpcall turns into the
  # callback's (176-193). Lota refuses what Event.restart refuses.
  def test_a_result_lota_cannot_read_comes_out_of_the_next_pump
    Lota::Event.modal_draw_callback = -> { Object.new }
    LotaNativeTest.request_modal_draw
    error = assert_raises(RuntimeError) { Lota::Event.pump }

    assert_equal "Error in modal draw callback: wrong argument type Object (expected nil, true, false, a number, " \
      "a String, a Symbol, an Array, a Hash, or a Proc)", error.message
  end

  # drawCallbackInner reads a table it returns as luax_checkvariant reads
  # one (wrap_Event.cpp:161-173): the Array of results holds each.
  def test_a_table_the_callback_returns_is_carried
    Lota::Event.modal_draw_callback = -> { [[1, 2], { score: 3 }] }
    resize_and_pump

    assert_equal [[:quit, [1.0, 2.0], { "score" => 3.0 }, true]], queued
  end

  def test_a_table_that_holds_itself_comes_out_of_the_next_pump
    cycle = []
    cycle << cycle
    Lota::Event.modal_draw_callback = -> { [cycle] }
    LotaNativeTest.request_modal_draw
    error = assert_raises(RuntimeError) { Lota::Event.pump }

    assert_equal "Error in modal draw callback: Cycle detected in table", error.message
  end

  # A function the callback returns is a Variant of unknown type, which is
  # not nil, so Event::pump queues the quit (event/sdl/Event.cpp:184-199),
  # and it leaves the queue as nil. A Symbol is its name.
  def test_a_proc_or_a_symbol_the_callback_returns_is_read_as_restart_reads_it
    Lota::Event.modal_draw_callback = -> { -> {} }
    resize_and_pump

    assert_equal [[:quit, nil, nil, true]], queued

    Lota::Event.modal_draw_callback = -> { [0, :restart] }
    resize_and_pump

    assert_equal [[:quit, 0, "restart", true]], queued
  end

  # Lua leaves a function only by returning or by an error, which
  # lua_cpcall catches, so a throw out of the callable is an error of the
  # callback's too, rather than an exit that skips the pump.
  def test_a_throw_out_of_the_callback_comes_out_of_the_next_pump
    Lota::Event.modal_draw_callback = -> { throw :out }
    error = catch(:out) do
      LotaNativeTest.request_modal_draw
      assert_raises(RuntimeError) { Lota::Event.pump }
    end

    assert_kind_of RuntimeError, error
    assert_equal "Error in modal draw callback: Unexpected throw", error.message
  end

  def test_anything_that_answers_call_may_draw
    drawer = Object.new
    def drawer.call = 7

    Lota::Event.modal_draw_callback = drawer
    resize_and_pump

    assert_equal [[:quit, 7, nil, true]], queued
  end

  def test_the_callback_must_answer_call
    error = assert_raises(TypeError) { Lota::Event.modal_draw_callback = 1 }

    assert_equal "wrong argument type Integer (expected a callable)", error.message
  end
end
