# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# Runs the gate's checks, each in its own rake process, and reports how long
# each took.
#
# The checks fall into lanes. Lanes run at the same time; the checks in one
# lane run one after another, because they share something only one can use
# at a time, such as the window that needs keyboard focus. Each check's
# output is held until it ends, then printed whole, in the order the checks
# are declared, so a failure's output is never interleaved with another's.
# A lane starts no more checks once any check has failed; checks already
# running finish.
#
# What is held tells nothing while it is held, so the gate also prints, as
# it happens, a timestamped line as each check starts and ends, and every
# +heartbeat+ seconds a line naming the checks still running and how long
# each has run. A lane that runs longer than +lane_timeout+ seconds is
# diagnosed (Gate::Diagnosis: its output so far, its processes, and a stack
# sample of each), then ended, and its check fails as TIMED OUT, so that a
# check that hangs fails with what it was doing printed, before CI's own
# time limit ends the gate with nothing printed.
#
# On Linux the checks' windows open on an X display, and under X11 a warp
# of the pointer reaches SDL only as the motion the X server sends to the
# window on top where the pointer lands (SDL 3.4.10,
# src/video/x11/SDL_x11mouse.c, X11_WarpMouseInternal), so a window of one
# lane's tests that opens over another's takes the moves Lövetest's mouse
# tests make, and they read back where the pointer was before. A display
# for each lane keeps one lane's windows from opening over another's.
class Gate
  # Raised when a check fails, after every output and the timings have been
  # printed.
  class Failure < StandardError; end

  # One check: the rake tasks one process runs, in order.
  class Check < Data.define(:name, :tasks)
    # The check named for its tasks, as the gate lists them.
    def self.of(*tasks) = new(name: tasks.join(" + "), tasks:)
  end

  # What a check did: +status+ is :passed, :failed, or :timed_out.
  class Outcome < Data.define(:check, :status, :output, :seconds)
    # Whether the check passed.
    def passed? = status == :passed
  end

  # The script a check's process runs: rake, with the tasks the gate has
  # already run replaced by nothing, so that a check that depends on a build
  # does not build it again, at the same time as another check does.
  CHILD = File.expand_path("gate_child.rb", __dir__)

  # How long, in seconds, a lane may run before the gate diagnoses and ends
  # it (LOTA_GATE_LANE_TIMEOUT). The bound is CI's: the macOS Gate step
  # may run 55 minutes, 3300 s (.github/workflows/ci.yml), and by then the
  # lane must have been sampled and ended and the report printed. The gate
  # has spent up to 207 s fixing and building before the lanes start, and
  # the diagnosis can take up to about 130 s (two listings of processes of
  # up to 30 s each, samples of up to 60 s taken together, and 5 s to end
  # the group), which leaves 2963 s; two minutes more for the report and
  # whatever else is slow that day leaves 47 minutes. The slowest lane on
  # CI, test:shard:rake_tasks's, has taken 16 to 37 minutes (2246 s), most
  # of it one test that runs the sanitized suite; a run on a
  # contributor's Mac takes about seven.
  LANE_TIMEOUT = 47 * 60

  # How often, in seconds, the gate names the checks still running
  # (LOTA_GATE_HEARTBEAT).
  HEARTBEAT = 60

  # [prepared] The rake tasks run first, in this process, one at a time.
  # [lanes] Arrays of Checks; a lane's checks run in order.
  # [jobs] How many lanes run at once; 1 runs the lanes one after another.
  # [displays] The X display each lane's checks open their windows on, in
  #            the order of +lanes+ (DISPLAY); a lane past the last keeps
  #            this process's. With +jobs+ 1, every lane uses the first.
  # [lane_timeout] Seconds a lane may run before it is diagnosed and ended.
  # [heartbeat] Seconds between the lines that name the checks running.
  # [root] The directory holding the Rakefile the checks run.
  # [out] Where the report goes.
  # [clock] What tells the time, in seconds, through +now+: Gate's own
  #         monotonic clock, or one a test moves past a lane's budget once
  #         the lane is provably stuck.
  # [tool_timeouts] Seconds each diagnostic tool may take (+:ps+,
  #                 +:sample+; Diagnosis::TIMEOUTS has the defaults).
  def initialize(prepared:, lanes:, jobs: lanes.size, displays: [], lane_timeout: LANE_TIMEOUT,
    heartbeat: HEARTBEAT, root: Dir.pwd, out: $stdout, clock: Gate, tool_timeouts: {}
  )
    @clock = clock
    @tool_timeouts = Diagnosis.timeouts(tool_timeouts)
    @prepared = prepared
    @lanes = lanes
    @jobs = jobs
    @displays = displays
    @lane_timeout = lane_timeout
    @heartbeat = heartbeat
    @root = root
    @out = out
    @failed = false
    @running = {}
    @lock = Mutex.new
    @print = Mutex.new
  end

  # Runs +prepared+ (a block that runs one task by name), then every check,
  # prints the report, and raises Failure unless every check passed.
  def run
    started = @clock.now
    timed = @prepared.map { |name| [name, time { yield name }] }
    outcomes = execute
    report(timed, outcomes, @clock.now - started)
    failed = outcomes.reject(&:passed?)
    raise Failure, "gate failed: #{failed.map { |o| failure(o) }.join(', ')}" if failed.any?

    outcomes
  end

  # The monotonic clock, in seconds.
  def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  private def failure(outcome) = (outcome.status == :timed_out) ? "#{outcome.check.name} (timed out)" : outcome.check.name

  private def execute
    say "each lane may run #{seconds(@lane_timeout)} s (LOTA_GATE_LANE_TIMEOUT) before the gate samples its " \
      "processes and ends it; the running checks are named every #{seconds(@heartbeat)} s (LOTA_GATE_HEARTBEAT)"
    heartbeat = Thread.new { beat }
    outcomes = lanes.flat_map(&:value)
    @lanes.flatten.filter_map { |check| outcomes.find { |outcome| outcome.check == check } }
  ensure
    heartbeat&.kill
  end

  # A Thread per lane, whose value is the lane's outcomes; with one job,
  # each runs the lane before it returns.
  private def lanes
    @lanes.each_with_index.map do |lane, index|
      display = (@jobs > 1) ? @displays[index] : @displays.first
      thread = Thread.new { run_lane(lane, index + 1, display) }
      thread.join if @jobs == 1
      thread
    end
  end

  # A lane with a display of its own gives it to the parity harness's games
  # too (LOTA_PARITY_DISPLAY, Parity.display), so that each lane that runs
  # a parity shard runs its games where no other lane's windows open.
  private def run_lane(lane, number, display)
    environment = display ? { "DISPLAY" => display, "LOTA_PARITY_DISPLAY" => display } : {}
    deadline = @clock.now + @lane_timeout
    lane.each_with_object([]) do |check, outcomes|
      break outcomes if failed?

      outcomes << attempt(check, number, environment, deadline)
    end
  ensure
    @lock.synchronize { @running.delete(number) }
  end

  private def attempt(check, lane, environment, deadline)
    started = @clock.now
    @lock.synchronize { @running[lane] = [check, started, deadline - @lane_timeout] }
    say "lane #{lane} started #{check.name}"
    child = Child.new(command(check), environment:, chdir: @root)
    status = finish(child, check, lane, deadline)
    @lock.synchronize { @failed ||= status != :passed }
    outcome = Outcome.new(check:, status:, output: child.output, seconds: @clock.now - started)
    say "lane #{lane} ended #{check.name}: #{status.to_s.tr('_', ' ')} in #{seconds(outcome.seconds)} s"
    outcome
  end

  private def finish(child, check, lane, deadline)
    if child.finish_by(deadline, clock: @clock)
      return child.status.success? ? :passed : :failed
    end

    say "lane #{lane} TIMED OUT: #{check.name} ran past the lane's budget of #{seconds(@lane_timeout)} s; " \
      "its diagnostics follow, then the gate ends it"
    emit Diagnosis.new(child, lane:, name: check.name, timeouts: @tool_timeouts).to_s
    child.end_group
    :timed_out
  end

  private def beat
    loop do
      sleep @heartbeat
      running = @lock.synchronize { @running.sort.map { |lane, entry| [lane, *entry] } }
      next if running.empty?

      described = running.map do |lane, check, started, lane_started|
        "lane #{lane} #{check.name} (check #{minutes(@clock.now - started)}, " \
          "lane #{minutes(@clock.now - lane_started)} of #{minutes(@lane_timeout)})"
      end
      say "running: #{described.join(', ')}"
    end
  end

  private def command(check)
    [RbConfig.ruby, CHILD, @prepared.join(","), *check.tasks]
  end

  private def failed? = @lock.synchronize { @failed }

  # Prints one line of the live log at once, stamped with the time.
  private def say(message) = emit("gate #{Time.now.utc.strftime('%FT%TZ')}: #{message}")

  private def emit(text)
    @print.synchronize do
      @out.puts text
      @out.flush
    end
  end

  private def report(timed, outcomes, total)
    outcomes.each do |outcome|
      mark = outcome.passed? ? "✅" : "❌"
      timed_out = (outcome.status == :timed_out) ? ", TIMED OUT" : ""
      @out.puts "\n#{mark} gate: #{outcome.check.name} (#{format('%.0f', outcome.seconds)} s#{timed_out})"
      @out.puts(timed_out.empty? ? outcome.output : "(its output so far is printed with its diagnostics above)")
    end
    @out.puts "\ngate timings"
    timed.each { |name, seconds| @out.puts format("  %-48s %6.0f s", "#{name} (first, in order)", seconds) }
    outcomes.each do |outcome|
      @out.puts format("  %-48s %6.0f s  %s", outcome.check.name, outcome.seconds, verdict(outcome))
    end
    sum = timed.sum(&:last) + outcomes.sum(&:seconds)
    @out.puts format("  %-48s %6.0f s  (the checks one after another: %.0f s)", "total", total, sum)
  end

  private def verdict(outcome) = { passed: "passed", failed: "FAILED", timed_out: "TIMED OUT" }.fetch(outcome.status)

  private def seconds(value) = format("%.0f", value)

  private def minutes(value) = format("%dm%02ds", *value.round.divmod(60))

  private def time
    started = @clock.now
    yield
    @clock.now - started
  end
end

require_relative "gate_process"
