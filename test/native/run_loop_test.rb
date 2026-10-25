# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"

# Lota.run, translated from love.run
# (vendor/love/src/modules/love/callbacks.lua:168-206), run a frame at a
# time in this process's window: load once, then each frame handles the
# queued events, updates, and draws, and a quit event ends the game
# unless the quit callback cancels it.
class RunLoopTest < Minitest::Test
  include CallbackHelper

  def setup
    super
    EngineHelper.open_window
    @calls = []
  end

  def record(name, &body)
    calls = @calls
    define_callback(name) do |*arguments|
      calls << name
      body&.call(*arguments)
    end
  end

  def test_run_calls_load_with_the_game_arguments_and_returns_the_frame
    saved = [Lota::Callbacks.parsed_game_arguments, Lota::Callbacks.raw_game_arguments]
    Lota::Callbacks.parsed_game_arguments = ["2"]
    Lota::Callbacks.raw_game_arguments = ["game", "2"]
    received = nil
    define_callback(:load) { |arguments, raw_arguments| received = [arguments, raw_arguments] }

    frame = Lota.run

    assert_equal [["2"], ["game", "2"]], received
    assert_predicate frame, :lambda?
  ensure
    Lota::Callbacks.parsed_game_arguments, Lota::Callbacks.raw_game_arguments = saved
  end

  def test_a_frame_updates_then_draws_and_returns_nil
    record(:update)
    record(:draw)

    assert_nil Lota.run.call
    assert_equal %i[update draw], @calls
  end

  def test_update_receives_the_seconds_since_the_last_step
    received = nil
    define_callback(:update) { |dt| received = dt }

    Lota.run.call

    assert_instance_of Float, received
    assert_operator received, :>=, 0
  end

  def test_a_quit_event_ends_the_game_with_its_status
    record(:update)
    Lota::Event.quit(3)

    assert_equal 3, Lota.run.call
    assert_empty @calls, "a frame that quits does not update"
  end

  def test_a_quit_event_without_a_status_ends_with_0
    Lota::Event.quit

    assert_equal 0, Lota.run.call
  end

  def test_the_quit_callback_runs_before_the_game_ends
    record(:quit) { nil }
    Lota::Event.quit(1)

    assert_equal 1, Lota.run.call
    assert_equal [:quit], @calls
  end

  def test_a_truthy_quit_callback_cancels_quitting_and_the_frame_goes_on
    record(:quit) { true }
    record(:update)
    record(:draw)
    Lota::Event.quit(1)

    assert_nil Lota.run.call
    assert_equal %i[quit update draw], @calls
  end

  def test_events_are_handled_before_update
    record(:quit) { :cancel }
    record(:update)
    frame = Lota.run
    frame.call
    @calls.clear

    Lota::Event.quit
    frame.call

    assert_equal %i[quit update], @calls
  end
end
