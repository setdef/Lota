# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# Parity.run stops a run that stands still, not one that is slow: a
# command that keeps showing frames runs to its end however long it
# takes, and one that shows no new frame for the stall window is killed
# within moments of it, with a line saying which side stood still, after
# which frame, and for how long. Each command is started with exec, so the
# process killed is the one holding its output open.
class RunTest < Minitest::Test
  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def test_a_slow_run_that_keeps_showing_frames_runs_to_its_end
    shown = 0
    started = now
    output = Parity.run({}, "sh", "-c", "sleep 3; exec echo done", side: "Lota", stall: 1) { shown += 1 }

    assert_predicate output.status, :success?, output.text
    assert_equal "done\n", output.text
    assert_operator now - started, :>=, 3
  end

  def test_a_run_that_stops_showing_frames_is_stopped_promptly_and_says_where
    started = now
    output = Parity.run({}, "sh", "-c", "exec sleep 60", side: "Lota", stall: 0.5) { 1 }

    assert_operator now - started, :<, 30
    assert_equal 9, output.status.termsig, output.text
    assert output.text.end_with?("Lota showed no new frame for 0.5 seconds, after frame 1, and was stopped.\n"),
      output.text
  end

  def test_a_run_that_never_shows_a_frame_is_stopped_after_starting
    output = Parity.run({}, "sh", "-c", "exec sleep 60", side: "The reference love", stall: 0.5) { 0 }

    assert_equal 9, output.status.termsig, output.text
    assert output.text.end_with?("The reference love showed no new frame for 0.5 seconds, after starting, " \
      "and was stopped.\n"), output.text
  end
end
