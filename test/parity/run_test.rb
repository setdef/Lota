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

  # The pointer is the computer's: a run that moves or clicks it waits for
  # the desktop input lock (the desktop_input_lock gem) while another process
  # holds it, and one that does not goes on. The holder is a process of
  # its own, since the threads of one process share the lock. The lock is
  # a file of the test's own, so the test waits for its holder alone, not
  # for every test on the computer that holds the real one.
  def test_a_run_that_moves_the_pointer_waits_for_the_lock_and_one_that_does_not_goes_on
    Dir.mktmpdir("lota-run-test-") do |dir|
      lock = File.join(dir, "lock")
      marker = File.join(dir, "away")
      input = DesktopInputLock.new(lock:, marker:)
      holder = "DesktopInputLock.new(lock: #{lock.dump}, marker: #{marker.dump}).hold(speak: false) " \
        "{ puts 'held'; $stdout.flush; $stdin.read }"
      Open3.popen2(RbConfig.ruby, "-rdesktop_input_lock", "-e", holder,
        err: File::NULL) do |stdin, stdout, wait|
        assert_equal "held\n", stdout.gets
        plain = Parity.run({}, "echo", "plain", side: "Lota", desktop_input: input) { 1 }
        moving = Thread.new do
          Parity.run({ "LOTA_PARITY_MOVE" => "1:10:10" }, "echo", "moved", side: "Lota", desktop_input: input) { 1 }
        end

        assert_equal "plain\n", plain.text
        assert_nil moving.join(1)

        stdin.close
        wait.join

        assert_equal "moved\n", moving.value.text
      end
    end
  end
end
