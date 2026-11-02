# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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

  # What the queue holds, but for the exposed message every live resize
  # also queues.
  def queued
    Lota::Event.poll.to_a.map { |message| Array(message) } - [[:exposed]]
  end

  def teardown
    Lota::Event.modal_draw_callback = nil
    Lota::Event.clear
  end

  # w_wait (wrap_Event.cpp:74-91) takes the next message SDL has and
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
      /\ALota - Warning: #{Regexp.escape(__FILE__)}:\d+: Using deprecated function Lota::Event.wait \(replaced by wait_timeout parameter in Lota::Event.pump\)\n\z/,
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

  def test_restart_refuses_what_an_event_cannot_carry
    error = assert_raises(ArgumentError) { Lota::Event.restart(1, [2]) }

    assert_equal "Argument 3 can't be stored safely\nExpected boolean, number, string or userdata.", error.message
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

  def test_a_result_an_event_cannot_carry_comes_out_of_the_next_pump
    Lota::Event.modal_draw_callback = -> { Object.new }
    LotaNativeTest.request_modal_draw
    error = assert_raises(RuntimeError) { Lota::Event.pump }

    assert_equal "Error in modal draw callback: it returned Object, which an event cannot carry.", error.message
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
