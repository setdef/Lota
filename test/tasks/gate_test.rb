# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "stringio"
require_relative "../../tasks/gate"

# Runs the gate's checks through real rake processes, over a Rakefile of
# small tasks.
class GateTest < Minitest::Test
  include TreeHelper

  RAKEFILE = <<~RUBY
    task(:built) { File.write("built.log", File.read("built.log").succ) if File.exist?("built.log") }
    task(:ok) { puts "ok ran" }
    task(:slow) { sleep 1; File.write("slow.at", Time.now.to_f.to_s); puts "slow ran" }
    task(:quick) { File.write("quick.at", Time.now.to_f.to_s); puts "quick ran" }
    task(:bad) { puts "bad output"; abort "bad failed" }
    task(:needs_built => :built) { puts "needs built" }
    task(:display) { puts "display \#{ENV.fetch('DISPLAY', 'none')}" }
    task(:hang) do
      File.write("child.pid", spawn("sleep", "20").to_s)
      File.write("hang.pid", Process.pid.to_s)
      puts "hang began"
      $stdout.flush
      sleep 20
    end
    task(:orphan) do
      spawn("sleep", "20")
      puts "orphan exited"
    end
  RUBY

  def gate(root, lanes, jobs: lanes.size, displays: [], **)
    write(root, "Rakefile", RAKEFILE)
    out = StringIO.new
    [Gate.new(prepared: %w[built], lanes:, jobs:, displays:, root:, out:, **), out]
  end

  def check(*tasks) = Gate::Check.of(*tasks)

  def gone?(pid)
    Process.kill(0, pid)
    false
  rescue Errno::ESRCH
    true
  end

  def eventually_gone?(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.05 until gone?(pid) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    gone?(pid)
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def test_prints_each_check_whole_in_declared_order_with_timings
    in_tree do |root|
      gate, out = gate(root, [[check("slow")], [check("ok")]])
      gate.run { nil }

      report = out.string

      assert_operator report.index("gate: slow"), :<, report.index("slow ran")
      assert_operator report.index("slow ran"), :<, report.index("gate: ok")
      assert_operator report.index("gate: ok"), :<, report.index("ok ran")
      assert_match(/gate timings.*slow\s+\d+ s\s+passed.*ok\s+\d+ s\s+passed.*total/m, report)
    end
  end

  def test_lanes_run_at_the_same_time_and_a_lane_runs_in_order
    in_tree do |root|
      gate, = gate(root, [[check("slow"), check("quick")], [check("ok")]])
      gate.run { nil }

      assert_operator File.read(File.join(root, "slow.at")).to_f, :<, File.read(File.join(root, "quick.at")).to_f
    end
  end

  def test_one_job_runs_every_check_in_one_lane
    in_tree do |root|
      gate, out = gate(root, [[check("slow")], [check("quick")]], jobs: 1)
      gate.run { nil }

      assert_operator File.read(File.join(root, "slow.at")).to_f, :<, File.read(File.join(root, "quick.at")).to_f
      assert_includes out.string, "slow ran"
    end
  end

  def test_a_failure_raises_after_printing_its_output_and_starts_no_more_of_its_lane
    in_tree do |root|
      gate, out = gate(root, [[check("bad"), check("quick")], [check("ok")]])
      error = assert_raises(Gate::Failure) { gate.run { nil } }

      assert_equal "gate failed: bad", error.message
      assert_includes out.string, "❌ gate: bad"
      assert_includes out.string, "bad output"
      assert_includes out.string, "FAILED"
      refute_path_exists File.join(root, "quick.at")
    end
  end

  def test_a_prepared_task_is_not_run_again_by_a_check_that_needs_it
    in_tree do |root|
      gate, out = gate(root, [[check("needs_built")]])
      File.write(File.join(root, "built.log"), "0")
      gate.run { |name| assert_equal "built", name }

      assert_includes out.string, "needs built"
      assert_equal "0", File.read(File.join(root, "built.log"))
    end
  end

  # Each lane's checks open their windows on the lane's own display, and a
  # lane past the last display keeps the gate's.
  def test_each_lane_runs_on_its_own_display
    in_tree do |root|
      gate, out = gate(root, [[check("display"), check("ok")], [check("ok", "display")], [check("quick", "display")]],
        displays: %w[:97 :96])
      gate.run { nil }

      assert_equal ["display :97", "display :96", "display #{ENV.fetch('DISPLAY', 'none')}"],
        out.string.scan(/^display .*$/)
    end
  end

  # The live log says when each check starts and ends as it happens, apart
  # from the output the report holds, and says the budget.
  def test_prints_each_start_and_end_as_it_happens
    in_tree do |root|
      gate, out = gate(root, [[check("slow")], [check("ok")]], lane_timeout: 30)
      gate.run { nil }

      report = out.string

      assert_match(/^gate \d\d:\d\d:\d\d: every lane must end within 30 s of the gate's start/, report)
      assert_match(/^gate \d\d:\d\d:\d\d: ▶ slow started \(lane 1\)$/, report)
      assert_match(/^gate \d\d:\d\d:\d\d: ✅ ok ended \(lane 2, \d+ s, passed\)$/, report)
      assert_operator report.index("slow ended (lane 1"), :<, report.index("✅ gate: slow")
      assert_operator report.index("ok ended"), :<, report.index("slow ended")
    end
  end

  # While checks run, the live log names each, with its lane and how long
  # it has run, at every heartbeat.
  def test_a_heartbeat_names_the_checks_still_running
    in_tree do |root|
      gate, out = gate(root, [[check("slow")], [check("ok")]], heartbeat: 0.3)
      gate.run { nil }

      assert_match(/^gate \d\d:\d\d:\d\d: still running: slow \(lane 1, \d+ s\)$/, out.string)
    end
  end

  # A check still running when its lane's budget runs out is timed out:
  # its output so far, its processes, and their stacks are printed, its
  # process group is ended, and the gate fails, while the other lanes are
  # untouched.
  def test_a_check_past_the_budget_is_timed_out_after_its_diagnostics
    in_tree do |root|
      gate, out = gate(root, [[check("hang"), check("quick")], [check("ok")]], lane_timeout: 2, sample_seconds: 1)
      error = nil
      seconds = timed { error = assert_raises(Gate::Failure) { gate.run { nil } } }

      report = out.string

      assert_equal "gate failed: hang (timed out)", error.message
      assert_operator seconds, :<, 15
      assert_match(/⏰ hang TIMED OUT \(lane 1\) after \d+ s, past the budget of 2 s from the gate's start/, report)
      assert_match(/output of hang so far.*hang began/m, report)
      assert_match(/processes of hang.*PID\s+PPID\s+PGID.*gate_child\.rb.*sleep 20/m, report)
      assert_match(/stack of #{File.read(File.join(root, 'hang.pid'))} /, report)
      assert_match(/ended the process group of hang/, report)
      assert_match(/⏰ gate: hang \(\d+ s\) TIMED OUT/, report)
      assert_match(/hang\s+\d+ s\s+TIMED OUT/, report)
      assert_match(/✅ gate: ok/, report)
      assert eventually_gone?(Integer(File.read(File.join(root, "hang.pid"))))
      assert eventually_gone?(Integer(File.read(File.join(root, "child.pid"))))
      refute_path_exists File.join(root, "quick.at")
    end
  end

  # A check whose process has exited, but which left a process holding its
  # output open, would keep the gate waiting for the end of that output;
  # the watchdog times it out too, and says which it was.
  def test_a_check_whose_output_stays_open_after_it_exits_is_timed_out
    in_tree do |root|
      gate, out = gate(root, [[check("orphan")]], lane_timeout: 2, sample_seconds: 1)
      error = nil
      seconds = timed { error = assert_raises(Gate::Failure) { gate.run { nil } } }

      assert_equal "gate failed: orphan (timed out)", error.message
      assert_operator seconds, :<, 15
      assert_match(/its process exited with status 0, but a process it started still holds its output open/, out.string)
      assert_match(/output of orphan so far.*orphan exited/m, out.string)
    end
  end
end
