# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
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

  # What a check did: +status+ is true when it passed.
  Outcome = Data.define(:check, :status, :output, :seconds)

  # The script a check's process runs: rake, with the tasks the gate has
  # already run replaced by nothing, so that a check that depends on a build
  # does not build it again, at the same time as another check does.
  CHILD = File.expand_path("gate_child.rb", __dir__)

  # [prepared] The rake tasks run first, in this process, one at a time.
  # [lanes] Arrays of Checks; a lane's checks run in order.
  # [jobs] How many lanes run at once; 1 runs every check in order.
  # [displays] The X display each lane's checks open their windows on, in
  #            the order of +lanes+ (DISPLAY); a lane past the last keeps
  #            this process's.
  # [root] The directory holding the Rakefile the checks run.
  # [out] Where the report goes.
  def initialize(prepared:, lanes:, jobs: lanes.size, displays: [], root: Dir.pwd, out: $stdout)
    @prepared = prepared
    @lanes = lanes
    @jobs = jobs
    @displays = displays
    @root = root
    @out = out
    @failed = false
    @lock = Mutex.new
  end

  # Runs +prepared+ (a block that runs one task by name), then every check,
  # prints the report, and raises Failure unless every check passed.
  def run
    started = now
    timed = @prepared.map { |name| [name, time { yield name }] }
    outcomes = execute
    report(timed, outcomes, now - started)
    failed = outcomes.reject(&:status)
    raise Failure, "gate failed: #{failed.map { |o| o.check.name }.join(', ')}" if failed.any?

    outcomes
  end

  private def execute
    lanes = (@jobs > 1) ? @lanes : [@lanes.flatten]
    outcomes = lanes.each_with_index.map { |lane, index| Thread.new { run_lane(lane, @displays[index]) } }
      .flat_map(&:value)
    @lanes.flatten.filter_map { |check| outcomes.find { |outcome| outcome.check == check } }
  end

  private def run_lane(lane, display)
    environment = display ? { "DISPLAY" => display } : {}
    lane.each_with_object([]) do |check, outcomes|
      break outcomes if failed?

      outcomes << attempt(check, environment)
    end
  end

  private def attempt(check, environment)
    output = nil
    status = nil
    seconds = time { output, status = Open3.capture2e(environment, *command(check), in: File::NULL, chdir: @root) }
    @lock.synchronize { @failed ||= !status.success? }
    Outcome.new(check:, status: status.success?, output:, seconds:)
  end

  private def command(check)
    [RbConfig.ruby, CHILD, @prepared.join(","), *check.tasks]
  end

  private def failed? = @lock.synchronize { @failed }

  private def report(timed, outcomes, total)
    outcomes.each do |outcome|
      @out.puts "\n#{outcome.status ? '✅' : '❌'} gate: #{outcome.check.name} (#{format('%.0f', outcome.seconds)} s)"
      @out.puts outcome.output
    end
    @out.puts "\ngate timings"
    timed.each { |name, seconds| @out.puts format("  %-48s %6.0f s", "#{name} (first, in order)", seconds) }
    outcomes.each do |outcome|
      @out.puts format("  %-48s %6.0f s  %s", outcome.check.name, outcome.seconds, outcome.status ? "passed" : "FAILED")
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
