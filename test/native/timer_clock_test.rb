# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The rest of Lota::Timer, translated from love.timer
# (vendor/love/src/modules/timer/Timer.cpp): the clock that only moves
# forward, and the frame rate and average step the timer works out once a
# second. Lövetest checks only that they answer
# (test/lovetest/tests/timer.rb).
class TimerClockTest < Minitest::Test
  include NativeHelper

  def setup
    EngineHelper.open_window
  end

  # Lota::Timer.sleep lets go of Ruby's GVL, as Ruby's own sleep does, so
  # another thread runs while it sleeps, and so, in another Ractor, does
  # Ruby's collector (test/native/thread_test.rb).
  def test_sleep_lets_other_threads_run
    counted = 0
    counter = Thread.new { loop { counted += 1 } }
    Thread.pass until counted.positive?
    before = counted
    Lota::Timer.sleep(0.2)
    during = counted - before
    counter.kill.join

    assert_operator during, :>, 1000
  end

  def test_time_counts_seconds_and_only_moves_forward
    before = Lota::Timer.time
    Lota::Timer.sleep(0.02)
    after = Lota::Timer.time

    assert_kind_of Float, before
    assert_includes 0.015..0.5, after - before
  end

  # w_getTime calls Timer::getTime, which is static (Timer.h:78), so it
  # answers before the timer module is open, where every other function
  # of the module raises. A process of its own, which opens nothing,
  # shows it.
  def test_time_answers_before_the_timer_module_is_open
    script = "require #{File.join(__dir__, '../../lib/lota').dump}; p Lota::Native::Timer.open?, " \
      "Lota::Timer.time.class; begin; Lota::Timer.delta; rescue RuntimeError => e; p e.message; end"
    output, status = capture2e({}, RbConfig.ruby, "-e", script)

    assert_predicate status, :success?, output
    assert_equal "false\nFloat\n\"Lota::Timer is not open.\"\n", output
  end

  # Timer::step (Timer.cpp:57-80) works the frame rate out of the steps
  # since the last time it did, once more than a second has passed since:
  # the steps divided by the seconds, rounded, and the seconds divided by
  # the steps.
  def test_frame_rate_and_average_step_are_worked_out_after_a_second
    Lota::Timer.step
    Lota::Timer.sleep(1.02)
    Lota::Timer.step

    assert_kind_of Integer, Lota::Timer.fps
    assert_kind_of Float, Lota::Timer.average_delta
    assert_operator Lota::Timer.fps, :>=, 1
    assert_operator Lota::Timer.average_delta, :>, 0
    assert_in_delta 1.0 / Lota::Timer.average_delta, Lota::Timer.fps, 0.5
  end

  def test_the_timer_is_the_module_it_is_translated_from
    assert_same Lota::Timer, Lota.timer
  end
end
