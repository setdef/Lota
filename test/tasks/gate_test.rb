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
    task(:fine) { File.write("fine.pid", Process.pid.to_s); puts "fine ran" }
    SLEEPER = [RbConfig.ruby, "-e", "File.write('sleeper.pid', Process.pid.to_s); sleep"].freeze
    task(:hang) { puts "hang started"; system(*SLEEPER) }
    task(:linger) do
      Process.detach(spawn(*SLEEPER))
      sleep 0.01 until File.exist?("sleeper.pid")
      puts "linger left"
      File.write("linger.pid", Process.pid.to_s)
    end
    task(:held) { sleep 0.01 until File.exist?("release"); puts "held ran" }
  RUBY

  # Time limits for the real ps and sample that no load reaches: a test
  # that reads what they print must not turn on how fast a busy machine
  # runs them. The limits themselves are tested with fake tools.
  PATIENT = { ps: 600, sample: 600 }.freeze

  # How long a process the gate ended may take to be gone, however busy
  # the machine.
  ENDING = 600

  # A clock that stands still until +ready+ says the lanes are where the
  # test wants them, then jumps past every budget, so a lane times out
  # when the test knows what it is doing, however slowly the machine
  # started it.
  class StuckClock
    def initialize(&ready)
      @ready = ready
    end

    def now = @ready.call ? 1_000_000.0 : 0.0
  end

  def gate(root, lanes, jobs: lanes.size, displays: [], lane_timeout: Gate::LANE_TIMEOUT, heartbeat: Gate::HEARTBEAT,
    clock: Gate, tool_timeouts: PATIENT
  )
    write(root, "Rakefile", RAKEFILE)
    out = StringIO.new
    gate = Gate.new(prepared: %w[built], lanes:, jobs:, displays:, lane_timeout:, heartbeat:, root:, out:, clock:,
      tool_timeouts:)
    [gate, out]
  end

  def check(*tasks) = Gate::Check.of(*tasks)

  # The pid a task wrote to +name+ under +root+, once it has written it.
  def written_pid(root, name)
    path = File.join(root, name)
    Integer(File.read(path), exception: false) if File.exist?(path)
  end

  # Whether the process +name+ names has ended and been reaped: macOS
  # answers EPERM for a zombie, so only ESRCH means gone.
  def reaped?(root, name)
    pid = written_pid(root, name) or return false
    Process.kill(0, pid)
    false
  rescue Errno::ESRCH
    true
  rescue Errno::EPERM
    false
  end

  # The process the hanging task left asleep, which must be gone once the
  # gate has ended its lane.
  def sleeper(root) = written_pid(root, "sleeper.pid")

  # Runs the block with +dir+ first on the PATH.
  def with_path(dir)
    path = ENV.fetch("PATH")
    ENV["PATH"] = "#{dir}#{File::PATH_SEPARATOR}#{path}"
    yield
  ensure
    ENV["PATH"] = path
  end

  def assert_ended(pid)
    deadline = Gate.now + ENDING
    gone = loop do
      Process.kill(0, pid)
      break false if Gate.now > deadline

      sleep 0.1
    rescue Errno::ESRCH
      break true
    end
    assert gone, "process #{pid} is still running"
  end

  # A lane past its budget is sampled while it hangs, then ended, and the
  # gate fails it, while the other lane passes as if nothing happened. The
  # budget runs out only once the hanging task's sleeper is asleep and the
  # other lane's check has ended.
  def test_a_lane_past_its_budget_is_diagnosed_ended_and_marked_timed_out
    in_tree do |root|
      clock = StuckClock.new { sleeper(root) && reaped?(root, "fine.pid") }
      gate, out = gate(root, [[check("hang"), check("quick")], [check("fine")]], lane_timeout: 3, clock:)
      error = assert_raises(Gate::Failure) { gate.run { nil } }
      report = out.string
      pid = sleeper(root)

      assert_equal "gate failed: hang (timed out)", error.message
      assert_match(/^gate \S+Z: lane 1 TIMED OUT: hang ran past the lane's budget of 3 s/, report)
      diagnostics = report[/^--- lane 1 diagnostics: hang ---$.*^--- end of lane 1 diagnostics ---$/m]

      refute_nil diagnostics, report
      assert_match(/the check's process, \d+, is still running/, diagnostics, report)
      assert_match(/^--- its output so far ---\nhang started$/, diagnostics, report)
      assert_match(/^--- its processes \(ps\) ---\n *PID +PPID +PGID +ELAPSED +STAT +COMMAND$/, diagnostics)
      assert_match(/^ *#{pid} +\d+ +\d+ +\S+ +\S+ +\S*ruby -e File\.write/, diagnostics)
      assert_match(/^--- stack of #{pid}: /, diagnostics)
      if RUBY_PLATFORM.include?("darwin")
        assert_match(/Analysis of sampling ruby \(pid #{pid}\).*Call graph:/m, diagnostics)
        refute_includes diagnostics, "Binary Images:"
      end
      assert_match(/❌ gate: hang \(\d+ s, TIMED OUT\)/, report)
      assert_match(/^  hang +\d+ s  TIMED OUT$/, report)
      assert_match(/✅ gate: fine \(\d+ s\)\nfine ran/, report)
      assert_match(/^  fine +\d+ s  passed$/, report)
      refute_path_exists File.join(root, "quick.at")
      assert_ended pid
    end
  end

  # A check whose process has ended while something it started still holds
  # its output open keeps its lane running; the diagnostics say so. The
  # budget runs out only once the check's process has been reaped.
  def test_a_check_whose_output_outlives_its_process_times_out
    in_tree do |root|
      clock = StuckClock.new { reaped?(root, "linger.pid") }
      gate, out = gate(root, [[check("linger")]], lane_timeout: 3, clock:)

      assert_raises(Gate::Failure) { gate.run { nil } }
      assert_match(/the check's process exited \(pid \d+ exit 0\), but its output is still open/, out.string)
      assert_includes out.string, "linger left"
      assert_ended sleeper(root)
    end
  end

  # When ps fails, the diagnosis says how, with what it printed, rather
  # than list nothing, and still samples the check's own process. In run
  # 1 of this change's gate, ps ran past its time, the diagnosis printed
  # an empty listing, and nothing said why.
  def test_a_failing_ps_is_reported_and_the_check_is_still_sampled
    in_tree do |root|
      write(root, "bin/ps", "#!/bin/sh\necho 'ps: broken' >&2\nexit 3\n")
      File.chmod(0o755, File.join(root, "bin/ps"))
      clock = StuckClock.new { sleeper(root) }
      gate, out = gate(root, [[check("hang")]], lane_timeout: 3, clock:)
      with_path(File.join(root, "bin")) { assert_raises(Gate::Failure) { gate.run { nil } } }
      diagnostics = out.string[/^--- lane 1 diagnostics.*^--- end of lane 1 diagnostics ---$/m]

      assert_equal 2, diagnostics.scan(/^ps failed \(pid \d+ exit 3\); it printed this:\nps: broken$/).size, diagnostics
      assert_match(/^--- stack of \d+: the check's process ---$/, diagnostics)
      assert_match(/Analysis of sampling ruby/, diagnostics) if RUBY_PLATFORM.include?("darwin")
      assert_ended sleeper(root)
    end
  end

  # A diagnostic tool that runs past its time is ended, and says so. Its
  # time runs out only once it has printed and is asleep for good.
  def test_a_tool_past_its_time_is_ended_and_says_so
    in_tree do |root|
      ready = File.join(root, "ready")
      script = "puts 'begun'; $stdout.flush; File.write(ARGV[0], ''); sleep"
      tool = Gate::Tool.run([RbConfig.ruby, "-e", script, ready], timeout: 1, clock: StuckClock.new { File.exist?(ready) })

      assert tool.timed_out
      refute_predicate tool, :ok?
      assert_equal "#{RbConfig.ruby} took more than its time and was ended; it printed this:\nbegun", tool.failure
    end
  end

  # A check that ends while finish_by asks the clock has finished. The
  # process waits for the clock to be asked, and the clock answers only
  # once the process has exited and its output has closed, so both threads
  # that watch it have ended between finish_by's look at them and its wait
  # on one. In CI's x86_64 Linux gate, a check ended in that moment, and
  # finish_by called join on the nil that no live thread left it.
  def test_a_check_that_ends_while_the_clock_is_asked_has_finished
    in_tree do |root|
      asked = File.join(root, "asked")
      child = Gate::Child.new([RbConfig.ruby, "-e", "sleep 0.01 until File.exist?(ARGV[0])", asked])
      clock = Object.new
      clock.define_singleton_method(:now) do
        File.write(asked, "")
        sleep 0.01 until child.status && !child.open?
        0.0
      end

      assert child.finish_by(ENDING, clock:)
      assert_predicate child.status, :success?
    end
  end

  # The live log says when each check starts and ends, as it happens, and
  # the heartbeat names what is still running and for how long. The held
  # check runs until the heartbeat has named it alone, after the other
  # lane's check has ended, on a clock that never moves, so no budget runs
  # out however slow the machine is.
  def test_starts_ends_and_a_heartbeat_print_as_they_happen
    in_tree do |root|
      gate, out = gate(root, [[check("held")], [check("ok")]], lane_timeout: 30, heartbeat: 0.1,
        clock: StuckClock.new { false })
      beat = /^gate \S+Z: running: lane 1 held \(check 0m00s, lane 0m00s of 0m30s\)$/
      releaser = Thread.new do
        deadline = Gate.now + ENDING
        sleep 0.05 until out.string.split(/^.*lane 2 ended ok.*$/, 2)[1]&.match?(beat) || Gate.now > deadline
        File.write(File.join(root, "release"), "")
      end
      gate.run { nil }
      releaser.join
      report = out.string
      held = report.index("\n✅ gate: held")

      assert_match(/^gate \S+Z: each lane may run 30 s \(LOTA_GATE_LANE_TIMEOUT\)/, report)
      [
        /^gate \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ: lane 1 started held$/,
        /^gate \S+Z: lane 2 started ok$/,
        /^gate \S+Z: lane 2 ended ok: passed in \d+ s$/,
        beat,
        /^gate \S+Z: lane 1 ended held: passed in \d+ s$/,
      ].each { |line| assert_operator report =~ line, :<, held, "#{line.inspect} not live in:\n#{report}" }
    end
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
end
