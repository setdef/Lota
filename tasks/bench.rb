# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"

# rake bench: what a draw call costs in Lota, under the interpreter, YJIT,
# and ZJIT, and what the same call costs a LÖVE game in the reference love
# (Plan 001, story 3; ADR 001, section 8).
#
# Two games do the measuring from inside a real window, one for each
# engine: tasks/bench/lota (with Bench::Recorder, tasks/bench/recorder.rb)
# and tasks/bench/love. Each process runs one Scenario and writes a JSON
# report; this module starts the processes, keeps each scenario's best
# run, and turns the reports into a Report.
module Bench
  ROOT = File.expand_path("..", __dir__)

  # How Ruby runs Lota: its flags for each JIT.
  JITS = { "interpreter" => [], "yjit" => ["--yjit"], "zjit" => ["--zjit"] }.freeze

  # The frame scenarios each engine runs (tasks/bench/lota/main.rb and
  # tasks/bench/love/main.lua say what each does), and +calls+, which
  # times single calls.
  LOTA_SCENARIOS = %w[ruby_noop noop native rectangle set_color color_writer color_reader calls].freeze
  LOVE_SCENARIOS = %w[rectangle set_color color_reader calls].freeze

  # The budgets a frame's share is reported against: 60 and 120 Hz.
  BUDGETS = [1 / 60.0, 1 / 120.0].freeze

  # How long one run may take before it is stopped and fails.
  TIMEOUT = 600

  # Raised when a run fails or writes no report.
  class Failure < StandardError; end

  # How much each run measures: rectangles a frame, untimed frames, timed
  # frames, iterations of each single call, and runs of each scenario.
  class Settings < Data.define(:draws, :warmup, :frames, :calls, :runs)
    DEFAULTS = { draws: 10_000, warmup: 200, frames: 2_000, calls: 200_000, runs: 3 }.freeze

    # The defaults, each overridden by BENCH_DRAWS, BENCH_WARMUP, and so
    # on, when set in +environment+.
    def self.from(environment)
      new(**DEFAULTS.to_h { |name, default| [name, Integer(environment.fetch("BENCH_#{name.upcase}", default))] })
    end

    # The environment a game reads them from.
    def environment
      {
        "LOTA_BENCH_DRAWS" => draws.to_s,
        "LOTA_BENCH_WARMUP" => warmup.to_s,
        "LOTA_BENCH_FRAMES" => frames.to_s,
        "LOTA_BENCH_CALLS" => calls.to_s,
      }
    end
  end

  # One engine, under one JIT, running one scenario. Lota runs under the
  # Ruby running rake, through exe/lota with lib and the test-only
  # extension (tmp/engine/build/lib) on its load path; LÖVE runs under
  # LuaJIT, whose JIT is on by default.
  class Scenario < Data.define(:engine, :jit, :name)
    # Every scenario, Lota's under each JIT, then LÖVE's.
    def self.all
      JITS.keys.product(LOTA_SCENARIOS).map { |jit, name| new(engine: "lota", jit:, name:) } +
        LOVE_SCENARIOS.map { |name| new(engine: "love", jit: "luajit", name:) }
    end

    # The command that runs it, with +love+ the reference love's
    # executable.
    def command(love:)
      return [love, File.join(ROOT, "tasks/bench/love")] if engine == "love"

      [
        RbConfig.ruby,
        *JITS.fetch(jit),
        "-I#{File.join(ROOT, 'lib')}",
        "-I#{File.join(ROOT, 'tmp/engine/build/lib')}",
        File.join(ROOT, "exe/lota"),
        "run",
        File.join(ROOT, "tasks/bench/lota"),
]
    end

    # The environment it runs with, writing its report to +report+.
    def environment(settings, report)
      settings.environment.merge("LOTA_BENCH_SCENARIO" => name, "LOTA_BENCH_REPORT" => report)
    end

    def to_s
      "#{engine} #{name} (#{jit})"
    end
  end

  # The +fraction+ quantile of +values+, by the nearest rank; +nil+ when
  # there are none.
  def self.quantile(values, fraction)
    return nil if values.empty?

    sorted = values.sort
    sorted.fetch(((sorted.size * fraction).ceil - 1).clamp(0, sorted.size - 1))
  end

  # One run's report, read back.
  class Result
    attr_reader :scenario, :data

    def initialize(scenario, data)
      @scenario = scenario
      @data = data
    end

    # Median seconds the draw loop took a frame.
    def draw
      Bench.quantile(data.fetch("draw"), 0.5)
    end

    # Median seconds a whole frame took.
    def frame
      Bench.quantile(data.fetch("frame"), 0.5)
    end

    # The 99th percentile and the longest of the frames, in seconds.
    def frame_p99
      Bench.quantile(data.fetch("frame"), 0.99)
    end

    def frame_max
      data.fetch("frame").max
    end

    # Median seconds per call in the draw loop.
    def per_draw
      draw / data.fetch("draws")
    end

    # What the collector did over the timed frames (Bench::Recorder#gc),
    # or an empty Hash for LÖVE.
    def gc
      data.fetch("gc", {})
    end

    # The longest the collector ran in one frame, in seconds.
    def gc_max
      (data.fetch("frame_gc_ns", []).max || 0) / 1e9
    end

    # Each single call's Hash of "seconds" and, for Lota, "allocations".
    def calls
      data.fetch("calls")
    end

    # What the run should be ranked by: lower is better.
    def rank
      (scenario.name == "calls") ? calls.values.sum { |call| call.fetch("seconds") } : draw
    end
  end

  # Runs each scenario +settings.runs+ times and keeps its best Result,
  # the one with the shortest median draw loop (for +calls+, the shortest
  # calls in all), since anything else running on the machine only ever
  # adds time.
  class Runner
    def initialize(settings:, love:, directory:, out: $stdout)
      @settings = settings
      @love = love
      @directory = directory
      @out = out
    end

    # The best Result of each of +scenarios+.
    def call(scenarios = Scenario.all)
      FileUtils.mkdir_p(@directory)
      scenarios.map do |scenario|
        Array.new(@settings.runs) { |index| run(scenario, index + 1) }.min_by(&:rank)
      end
    end

    # Runs +scenario+ once, as run number +index+, and returns its Result.
    def run(scenario, index)
      @out.puts "Running #{scenario}, run #{index} of #{@settings.runs}"
      report = File.join(@directory, "#{scenario.engine}-#{scenario.jit}-#{scenario.name}-#{index}.json")
      FileUtils.rm_f(report)
      output, status = Bench.spawn(scenario.environment(@settings, report), scenario.command(love: @love))
      unless status&.success? && File.exist?(report)
        raise Failure, "#{scenario} failed (#{status.inspect}):\n#{output}"
      end

      data = JSON.parse(File.read(report))
      # A Ruby built without ZJIT or YJIT warns at --zjit or --yjit and
      # runs the interpreter, and LuaJIT can start with its JIT off, so a
      # run that reports another JIT fails rather than being labeled with
      # the one it was asked for.
      ran = data.fetch("jit")
      raise Failure, "#{scenario} ran under #{ran}, not #{scenario.jit}:\n#{output}" unless ran == scenario.jit

      Result.new(scenario, data)
    end
  end

  # Runs +command+ with +environment+ added to this process's, and returns
  # its output and status, or a +nil+ status if it ran past +timeout+
  # seconds and was killed, with every process it started.
  def self.spawn(environment, command, timeout: TIMEOUT)
    Open3.popen2e(environment, *command, pgroup: true) do |stdin, output, wait|
      stdin.close
      reader = Thread.new { output.read }
      finished = wait.join(timeout)
      stop(wait.pid) unless finished
      [reader.value, finished && wait.value]
    rescue Interrupt
      # A run in its own process group hears no Control-C, so it is stopped
      # here when rake is.
      stop(wait.pid)
      raise
    end
  end

  # Kills the process group +pid+ leads, unless it is already gone (or,
  # on macOS, only its zombies are left, which EPERM reports).
  def self.stop(pid)
    Process.kill(:KILL, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # What the numbers were measured on, so they can be measured again.
  class Machine
    # [capture] Runs a command and returns its output, stripped, or +nil+
    #   when it fails.
    def initialize(capture: method(:capture))
      @capture = capture
    end

    # Lines naming the machine, its system, its power, and the commits.
    def lines
      [
        "Machine: #{@capture.call('sysctl', '-n', 'hw.model')}, #{@capture.call('sysctl', '-n',
          'machdep.cpu.brand_string')}, #{memory} GB",
        "System: macOS #{@capture.call('sw_vers', '-productVersion')} " \
          "(#{@capture.call('sw_vers', '-buildVersion')})",
        "Power: #{power}",
        "Lota: #{commit(ROOT)}; LÖVE: #{commit(File.join(ROOT, 'vendor/love'))}",
      ]
    end

    private def memory
      (@capture.call("sysctl", "-n", "hw.memsize").to_i / (1024 ** 3)).to_s
    end

    private def power
      @capture.call("pmset", "-g", "ps").to_s.lines.first.to_s.strip.delete_prefix("Now drawing from ")
    end

    private def commit(dir)
      head = @capture.call("git", "-C", dir, "rev-parse", "--short", "HEAD")
      changes = @capture.call("git", "-C", dir, "status", "--porcelain", "--untracked-files=no").to_s
      changes.empty? ? head.to_s : "#{head} with uncommitted changes"
    end

    private def capture(*command)
      output, status = Open3.capture2(*command, err: File::NULL)
      status.success? ? output.strip : nil
    end
  end

  # The numbers, as plain-text tables, with how they were measured.
  class Report
    # [results] The best Result of each scenario.
    # [settings] What each run measured.
    # [machine] Lines describing the machine (Machine#lines).
    def initialize(results, settings:, machine:)
      @results = results
      @settings = settings
      @machine = machine
    end

    def to_s
      [header, draws, breakdown, calls, collector].join("\n\n") << "\n"
    end

    private def find(engine, jit, name)
      @results.find { |result| result.scenario == Scenario.new(engine:, jit:, name:) }
    end

    private def lota_jits
      JITS.keys.select { |jit| @results.any? { |result| result.scenario.jit == jit } }
    end

    private def header
      rubies = lota_jits.filter_map { |jit| find("lota", jit, "rectangle")&.data&.fetch("ruby") }.uniq
      love = @results.find { |result| result.scenario.engine == "love" }&.data
      lines = @machine + rubies.map { |ruby| "Ruby: #{ruby}" }
      lines += ["LÖVE: #{love.fetch('lua')}, renderer #{love.fetch('renderer')}"] if love
      (["rake bench (Plan 001, story 3)", ""] + lines + ["", method]).join("\n")
    end

    private def method
      <<~METHOD.chomp
        Method: each scenario runs in its own process, in an 800 by 600 window
        without vertical sync, under lota run (tasks/bench/lota) or the reference
        love (tasks/bench/love). Its draw callback makes #{@settings.draws} calls a frame.
        The first #{@settings.warmup} frames are untimed, so the JITs have compiled the loop
        (each compiles a method after 30 calls); the next #{@settings.frames} are timed: the
        draw loop alone, and the whole frame from one draw to the next, which
        includes clearing, presenting, events, and the loop's 1 ms sleep.
        Medians are shown; each scenario's best of #{@settings.runs} runs is kept (the
        shortest median draw loop). Images are not bound yet, so a draw is
        love.graphics.rectangle("fill", x, y, 4, 4). Single calls are timed
        #{@settings.calls} times over, the best of 5, with allocations counted from
        GC.stat(:total_allocated_objects); the empty block is the timing loop's
        own cost, included in every other row.
      METHOD
    end

    private def draws
      rows = lota_jits.flat_map do |jit|
        %w[ruby_noop noop native rectangle].filter_map { |name| find("lota", jit, name) }
      end
      rows += [find("love", "luajit", "rectangle")].compact
      table("Draw loop, #{@settings.draws} calls a frame (medians)",
        ["scenario", "JIT", "draw ms", "ns/call", "of 16.7 ms", "of 8.3 ms", "frame ms", "frame - draw ms"],
        rows.map { |result| draw_row(result) })
    end

    private def draw_row(result)
      [
        label(result),
        result.scenario.jit,
        ms(result.draw),
        ns(result.per_draw),
        *BUDGETS.map { |budget| percent(result.draw / budget) },
        ms(result.frame),
        ms(result.frame - result.draw),
]
    end

    private def label(result)
      "#{(result.scenario.engine == 'love') ? 'LÖVE' : 'Lota'} #{result.scenario.name}"
    end

    private def breakdown
      love = find("love", "luajit", "rectangle")
      rows = lota_jits.filter_map do |jit|
        ruby, noop, native, public = %w[ruby_noop noop native rectangle].map { |name| find("lota", jit, name) }
        next unless ruby && noop && native && public

        [
          jit,
          ns(ruby.per_draw),
          ns(noop.per_draw - ruby.per_draw),
          ns(native.per_draw - noop.per_draw),
          ns(public.per_draw - native.per_draw),
          ns(public.per_draw),
          love ? ns(love.per_draw) : "-",
]
      end
      table("Where a Lota draw call's time goes (ns per call, differences of medians)",
        [
          "JIT",
          "Ruby loop + Ruby call",
          "into C++ (Rice)",
          "LÖVE's rectangle",
          "Lota::Graphics wrapper",
          "Lota total",
          "LÖVE total (LuaJIT)",
],
        rows)
    end

    private def calls
      lota = lota_jits.map { |jit| find("lota", jit, "calls") }
      love = find("love", "luajit", "calls")
      names = lota.compact.flat_map { |result| result.calls.keys }.uniq
      rows = names.map do |name|
        cells = lota.flat_map do |result|
          call = result&.calls&.[](name)
          call ? [ns(call.fetch("seconds")), format("%.2f", call.fetch("allocations"))] : ["-", "-"]
        end
        [name, *cells, ""]
      end
      love&.calls&.each { |name, call| rows << [name, *([""] * lota.size * 2), ns(call.fetch("seconds"))] }
      table("Single calls (ns and objects allocated per call)",
        ["call", *lota_jits.flat_map { |jit| ["#{jit} ns", "allocs"] }, "LuaJIT ns"], rows)
    end

    private def collector
      rows = lota_jits.flat_map do |jit|
        %w[native rectangle set_color color_writer color_reader].filter_map { |name| find("lota", jit, name) }
      end
      rows += %w[set_color color_reader].filter_map { |name| find("love", "luajit", name) }
      table("Allocations and the collector over #{@settings.frames} frames",
        [
          "scenario",
          "JIT",
          "draw ms",
          "objects/frame",
          "GCs (minor/major)",
          "GC ms total",
          "GC ms max/frame",
          "frame ms p50/p99/max",
],
        rows.map { |result| collector_row(result) })
    end

    private def collector_row(result)
      gc = result.gc
      frames = result.data.fetch("frame").size
      collected = if gc.empty?
        ["-", "-", "-", "-"]
      else
        [
          (gc.fetch("total_allocated_objects") / frames).to_s,
          "#{gc.fetch('count')} (#{gc.fetch('minor_gc_count')}/#{gc.fetch('major_gc_count')})",
          ms(gc.fetch("time_ns") / 1e9),
          ms(result.gc_max),
]
      end
      [
        label(result),
        result.scenario.jit,
        ms(result.draw),
        *collected,
        [result.frame, result.frame_p99, result.frame_max].map { |seconds| ms(seconds) }.join("/"),
]
    end

    private def table(title, headings, rows)
      widths = headings.each_index.map { |index| ([headings] + rows).map { |row| row[index].to_s.size }.max }
      line = -> (row) { row.each_with_index.map { |cell, index| cell.to_s.ljust(widths[index]) }.join("  ").rstrip }
      [title, line.(headings), line.(widths.map { |width| "-" * width }), *rows.map(&line)].join("\n")
    end

    private def ms(seconds)
      format("%.3f", seconds * 1e3)
    end

    private def ns(seconds)
      format("%.0f", seconds * 1e9)
    end

    private def percent(fraction)
      format("%.1f%%", fraction * 100)
    end
  end
end
