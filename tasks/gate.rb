# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require_relative "gate_watchdog"

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
# What is held says nothing while a check runs, so the gate also says, as
# it happens, when each check starts and ends, and at every heartbeat which
# are still running and for how long. A check still running when the
# budget runs out, counted from the gate's start, is timed out: the gate
# prints what it has printed so far, the tree of its processes, and a stack
# of each, then ends its process group, and the gate fails.
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

  # What a check did: +status+ is true when it passed, and +timed_out+ when
  # the gate ended it at the budget.
  Outcome = Data.define(:check, :status, :output, :seconds, :timed_out)

  # The script a check's process runs: rake, with the tasks the gate has
  # already run replaced by nothing, so that a check that depends on a build
  # does not build it again, at the same time as another check does.
  CHILD = File.expand_path("gate_child.rb", __dir__)

  # Seconds from the gate's start by which every lane must have ended,
  # unless told otherwise (LOTA_GATE_LANE_TIMEOUT): three hours, about five
  # times the slowest healthy lane CI has run (rake_tasks' lane, 2246 s)
  # and well past the slowest run of every check one after another
  # (LOTA_GATE_JOBS=1, 6426 s), so that it ends only a check that is hung.
  # CI, whose step GitHub ends sooner, sets its own (.github/workflows/ci.yml).
  LANE_TIMEOUT = 10_800

  # Seconds between the reports of which checks are still running.
  HEARTBEAT = 120

  # Seconds a timed-out check's processes have to end after TERM, before KILL.
  GRACE = 10

  # [prepared] The rake tasks run first, in this process, one at a time.
  # [lanes] Arrays of Checks; a lane's checks run in order.
  # [jobs] How many lanes run at once; 1 runs every check in order.
  # [displays] The X display each lane's checks open their windows on, in
  #            the order of +lanes+ (DISPLAY); a lane past the last keeps
  #            this process's.
  # [root] The directory holding the Rakefile the checks run.
  # [out] Where the report goes.
  # [lane_timeout] Seconds from the gate's start by which every check must
  #                have ended, prepared tasks included, as CI's limit on
  #                its step counts.
  # [heartbeat] Seconds between the reports of the checks still running.
  # [sample_seconds] How long each stack sample of a timed-out check lasts.
  def initialize(prepared:, lanes:, jobs: lanes.size, displays: [], root: Dir.pwd, out: $stdout,
    lane_timeout: LANE_TIMEOUT, heartbeat: HEARTBEAT, sample_seconds: 5
  )
    @prepared = prepared
    @lanes = lanes
    @jobs = jobs
    @displays = displays
    @root = root
    @out = out
    @lane_timeout = lane_timeout
    @heartbeat = heartbeat
    @sample_seconds = sample_seconds
    @failed = false
    @running = {}
    @lock = Mutex.new
    @print = Mutex.new
  end

  # Runs +prepared+ (a block that runs one task by name), then every check,
  # prints the report, and raises Failure unless every check passed.
  def run
    started = now
    @deadline = started + @lane_timeout
    say format("every lane must end within %g s of the gate's start (LOTA_GATE_LANE_TIMEOUT); " \
      "the checks still running are listed every %g s", @lane_timeout, @heartbeat)
    timed = @prepared.map { |name| [name, time { yield name }] }
    outcomes = execute
    report(timed, outcomes, now - started)
    failed = outcomes.reject(&:status)
    raise Failure, "gate failed: #{failed.map { |o| failure(o) }.join(', ')}" if failed.any?

    outcomes
  end

  private def failure(outcome) = outcome.timed_out ? "#{outcome.check.name} (timed out)" : outcome.check.name

  private def execute
    lanes = (@jobs > 1) ? @lanes : [@lanes.flatten]
    pulse = Thread.new { beat }
    outcomes = lanes.each_with_index.map { |lane, index| Thread.new { run_lane(lane, index + 1, @displays[index]) } }
      .flat_map(&:value)
    @lanes.flatten.filter_map { |check| outcomes.find { |outcome| outcome.check == check } }
  ensure
    pulse&.kill
  end

  private def run_lane(lane, number, display)
    environment = display ? { "DISPLAY" => display } : {}
    lane.each_with_object([]) do |check, outcomes|
      break outcomes if failed?

      outcomes << attempt(check, number, environment)
    end
  end

  private def attempt(check, lane, environment)
    started = now
    say "▶ #{check.name} started (lane #{lane})"
    @lock.synchronize { @running[check] = [lane, started] }
    spawned = Spawned.new(environment, command(check), @root)
    status = spawned.wait(@deadline)
    output = status ? spawned.output : time_out(check, lane, spawned, started)
    outcome = Outcome.new(check:, status: status&.success? || false, output:, seconds: now - started,
      timed_out: status.nil?)
    finish(outcome, lane)
  end

  private def finish(outcome, lane)
    @lock.synchronize do
      @running.delete(outcome.check)
      @failed ||= !outcome.status
    end
    say format("%s %s ended (lane %d, %.0f s, %s)", mark(outcome), outcome.check.name, lane, outcome.seconds,
      verdict(outcome))
    outcome
  end

  # Prints what the check printed so far and what its processes are doing,
  # then ends them, and returns what goes in the report in place of its
  # output, which has been printed.
  private def time_out(check, lane, spawned, started)
    exited = spawned.exit_status
    state = exited ? "its process exited with status #{exited.exitstatus || exited}, but a process it started " \
      "still holds its output open" : "it is still running"
    say format("⏰ %s TIMED OUT (lane %d) after %.0f s, past the budget of %g s from the gate's start; %s; " \
      "sampling its processes", check.name, lane, now - started, @lane_timeout, state)
    diagnosis = Diagnosis.new(spawned.pid, sample_seconds: @sample_seconds).to_s
    say "diagnostics of #{check.name}:", "--- output of #{check.name} so far ---", spawned.output,
      "--- processes of #{check.name} (process group #{spawned.pid}) and their stacks ---", diagnosis,
      "--- end of #{check.name}'s diagnostics ---"
    spawned.terminate(GRACE)
    say "ended the process group of #{check.name} (#{spawned.pid})"
    "(timed out: its output so far and its processes were printed when it timed out)"
  end

  private def beat
    loop do
      sleep @heartbeat
      running = @lock.synchronize { @running.dup }
      next if running.empty?

      checks = running.map { |check, (lane, started)| format("%s (lane %d, %.0f s)", check.name, lane, now - started) }
      say "still running: #{checks.join(', ')}"
    end
  end

  # Prints +lines+ to the live log at once, stamped with the time of day,
  # apart from the report the outputs wait for.
  private def say(first, *rest)
    @print.synchronize do
      @out.puts "gate #{Time.now.strftime('%H:%M:%S')}: #{first}", *rest
      @out.flush
    end
  end

  private def command(check)
    [RbConfig.ruby, CHILD, @prepared.join(","), *check.tasks]
  end

  private def failed? = @lock.synchronize { @failed }

  private def mark(outcome)
    if outcome.timed_out then "⏰"
    elsif outcome.status then "✅"
    else "❌"
    end
  end

  private def verdict(outcome)
    if outcome.timed_out then "TIMED OUT"
    elsif outcome.status then "passed"
    else "FAILED"
    end
  end

  private def report(timed, outcomes, total)
    outcomes.each do |outcome|
      @out.puts "\n#{mark(outcome)} gate: #{outcome.check.name} (#{format('%.0f', outcome.seconds)} s)" \
        "#{' TIMED OUT' if outcome.timed_out}"
      @out.puts outcome.output
    end
    @out.puts "\ngate timings"
    timed.each { |name, seconds| @out.puts format("  %-48s %6.0f s", "#{name} (first, in order)", seconds) }
    outcomes.each do |outcome|
      @out.puts format("  %-48s %6.0f s  %s", outcome.check.name, outcome.seconds, verdict(outcome))
    end
    sum = timed.sum(&:last) + outcomes.sum(&:seconds)
    @out.puts format("  %-48s %6.0f s  (the checks one after another: %.0f s)", "total", total, sum)
  end

  private def time
    started = now
    yield
    now - started
  end

  private def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
