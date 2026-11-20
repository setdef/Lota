# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"

# rake bench: what a draw call costs in Lota, under the interpreter, YJIT,
# and ZJIT, and what the same call costs a LÖVE game in the reference love
# (doc/contributors/design/engine.md), and what a frame of a published
# LÖVE game costs in each (GAMES).
#
# Two games do the measuring from inside a real window, one for each
# engine: tasks/bench/lota (with Bench::Recorder, tasks/bench/recorder.rb)
# and tasks/bench/love. The published games are timed by the parity
# harness's two sides instead (Game). Each process runs one Scenario and
# writes a JSON report; this module starts the processes, keeps each
# scenario's best run, and turns the reports into a Report.
module Bench
  ROOT = File.expand_path("..", __dir__)

  # How Ruby runs Lota: its flags for each JIT.
  JITS = { "interpreter" => [], "yjit" => ["--yjit"], "zjit" => ["--zjit"] }.freeze

  # A published LÖVE game, a parity fixture (doc/contributors/parity.md),
  # that both engines run whole: the game in +fixture+ in LÖVE, unchanged,
  # and its Ruby translation in +translation+ in Lota, each through its
  # side of the parity harness (test/parity/lua/conf.lua and
  # test/parity/probe.rb) in the harness's timing mode, which times every
  # frame and takes no screenshot. Both get the same +frames+ at a fixed
  # +fps+, the same clock, and the same key +presses+, each an SDL scancode
  # and the frames it is down in, so both do the same work.
  class Game < Data.define(:fixture, :translation, :frames, :fps, :presses)
    # The build tree the harness's libraries are in.
    LIB = File.join(ROOT, "tmp/engine/build/lib")

    # The clock both engines stand at, as the parity harness's (Parity::CLOCK).
    CLOCK = 1_600_000_000

    # The environment the harness's two sides read, for a run that writes
    # its times to +report+ and keeps what else it writes, its home among
    # them, beside it. It loads the harness's libraries as the parity
    # harness does (Parity.loopback): its audio device, mixed on the game's
    # time, which keeps the game's sounds out of the machine's speakers;
    # the library that keeps the game off the network; and on Linux the
    # one that answers dialogs, such as LÖVE's warning that a game was made
    # for another version, which on macOS the two sides answer themselves.
    def environment(report, settings, linux: RbConfig::CONFIG["host_os"].include?("linux"))
      base = report.delete_suffix(".json")
      home = "#{base}-home"
      FileUtils.mkdir_p([home, "#{base}-frames"])
      {
**script(frames_under(settings)),
**libraries(linux),
"LOTA_LOOPBACK_FILE" => "#{base}.f32",
"LOTA_PARITY_GAME" => File.join(ROOT, fixture),
"LOTA_PARITY_TIMES" => report,
"LOTA_PARITY_FRAMES_DIR" => "#{base}-frames",
"LOTA_PARITY_REPORT" => "#{base}-parity.json",
"LOTA_PARITY_MISMATCH_DIR" => "#{base}-mismatch",
"LOTA_PARITY_PROGRESS" => "#{base}-progress",
"HOME" => home,
(linux ? "XDG_DATA_HOME" : "CFFIXED_USER_HOME") => (linux ? File.join(home, ".local/share") : home),
"ALSOFT_CONF" => File.join(ROOT, "test/alsoft.conf"),
"SDL_MAC_BACKGROUND_APP" => "1",
"SDL_WINDOW_ACTIVATE_WHEN_SHOWN" => "0",
"SDL_WINDOW_ACTIVATE_WHEN_RAISED" => "0",
      }
    end

    # The frames a run under +settings+ plays: the script's, unless
    # +settings+ asks for fewer.
    def frames_under(settings)
      settings.game_frames.positive? ? settings.game_frames : frames
    end

    private def script(frames)
      {
        "LOTA_PARITY_FRAMES" => frames.to_s,
        "LOTA_PARITY_FPS" => fps.to_s,
        "LOTA_PARITY_CLOCK" => CLOCK.to_s,
        "LOTA_PARITY_HOLD" => "",
        "LOTA_PARITY_MOVE" => "",
        "LOTA_PARITY_CLICK" => "",
        "LOTA_PARITY_SOUNDS" => "",
        "LOTA_PARITY_PRESS" => presses.map { |scancode, range| "#{scancode}:#{range.first}-#{range.last}" }.join(","),
      }
    end

    private def libraries(linux)
      extension = linux ? "so" : "dylib"
      names = %w[loopback offline] + (linux ? %w[dialogs] : [])
      paths = names.map { |name| File.join(LIB, "liblota_#{name}.#{extension}") }
      linux ? { "LD_PRELOAD" => paths.join(" ") } : { "DYLD_INSERT_LIBRARIES" => paths.join(":") }
    end
  end

  # SDL's scancodes for Return and the space bar (SDL_scancode.h).
  RETURN = 40
  SPACE = 44

  # The games, by scenario name. FLASH-BLIP, the heaviest of the parity
  # fixtures, draws every frame through four shaders and its text a
  # rectangle a pixel; it runs here under its parity test's script
  # (test/parity/flash_blip_test.rb): it plays itself under its menu
  # until Return, in frame 300, starts a game, in which the space bar
  # blips every 40 frames from frame 400 until an obstacle ends it.
  GAMES = {
    "flash_blip" => Game.new(fixture: "test/fixtures/flash_blip/game", translation: "test/games/flash_blip",
      frames: 900, fps: 60, presses: [
        [RETURN, 300..300],
        *Array.new(10) { |press| [SPACE, (400 + (40 * press))..(400 + (40 * press))] },
      ]),
  }.freeze

  # What a Game's scenario name ends with when its run times the game's
  # calls into Lota's extension (Parity::Probe::NativeCalls), which only
  # Lota runs.
  NATIVE = "_native_calls"

  # The frame scenarios each engine runs (tasks/bench/lota/main.rb and
  # tasks/bench/love/main.lua say what each does), +calls+, which times
  # single calls, and the GAMES, which Lota also runs timing its native
  # calls.
  LOTA_SCENARIOS = (%w[ruby_noop noop native rectangle set_color color_writer color_reader frame calls] +
    GAMES.keys + GAMES.keys.map { |name| name + NATIVE }).freeze
  LOVE_SCENARIOS = (%w[rectangle set_color color_reader calls] + GAMES.keys).freeze

  # The budgets a frame's share is reported against: 60 and 120 Hz.
  BUDGETS = [1 / 60.0, 1 / 120.0].freeze

  # How long one run may take before it is stopped and fails.
  TIMEOUT = 600

  # Raised when a run fails or writes no report.
  class Failure < StandardError; end

  # How much each run measures: rectangles a frame, untimed frames, timed
  # frames, iterations of each single call, and runs of each scenario, and
  # the frames of each Game, where 0 runs its whole script.
  class Settings < Data.define(:draws, :warmup, :frames, :calls, :runs, :game_frames)
    DEFAULTS = { draws: 10_000, warmup: 200, frames: 2_000, calls: 200_000, runs: 3, game_frames: 0 }.freeze

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

    # Every scenario, or when +environment+ sets BENCH_SCENARIOS, those it
    # names, separated by commas or spaces, in every engine and JIT that
    # runs them. Raises Failure for a name no scenario has.
    def self.from(environment)
      names = environment.fetch("BENCH_SCENARIOS", "").split(/[\s,]+/).reject(&:empty?)
      return all if names.empty?

      unknown = names - LOTA_SCENARIOS - LOVE_SCENARIOS
      raise Failure, "BENCH_SCENARIOS names no scenario #{unknown.join(', ')}" unless unknown.empty?

      all.select { |scenario| names.include?(scenario.name) }
    end

    # The command that runs it, with +love+ the reference love's
    # executable.
    def command(love:)
      if engine == "love"
        return [love, File.join(ROOT, game ? "test/parity/lua" : "tasks/bench/love")]
      end

      [
        RbConfig.ruby,
        *JITS.fetch(jit),
        "-I#{File.join(ROOT, 'lib')}",
        "-I#{File.join(ROOT, 'tmp/engine/build/lib')}",
        *(game ? ["-r#{File.join(ROOT, 'test/parity/probe.rb')}"] : []),
        File.join(ROOT, "exe/lota"),
        "run",
        File.join(ROOT, game ? game.translation : "tasks/bench/lota"),
]
    end

    # The environment it runs with, writing its report to +report+.
    def environment(settings, report)
      if game
        environment = game.environment(report, settings)
        return native_calls? ? environment.merge("LOTA_PARITY_NATIVE_TIMES" => "1") : environment
      end

      settings.environment.merge("LOTA_BENCH_SCENARIO" => name, "LOTA_BENCH_REPORT" => report)
    end

    # The Game it runs, or +nil+ for a scenario of rake bench's own games.
    def game
      GAMES[name.delete_suffix(NATIVE)]
    end

    # Whether it runs a Game timing the game's native calls.
    def native_calls?
      !game.nil? && name.end_with?(NATIVE)
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

    # How many major collections each cause set off over the timed frames
    # (Bench::Recorder#major_causes), or an empty Hash for LÖVE.
    def major_causes
      data.fetch("gc_major_by", {})
    end

    # The longest the collector ran in one frame, in seconds.
    def gc_max
      (data.fetch("frame_gc_ns", []).max || 0) / 1e9
    end

    # Each single call's Hash of "seconds" and, for Lota, "allocations".
    def calls
      data.fetch("calls")
    end

    # For a Game, the seconds each frame's update and draw took together,
    # the game's own work, frame by frame.
    def work
      data.fetch("update").zip(data.fetch("draw")).map(&:sum)
    end

    # What the run should be ranked by: lower is better.
    def rank
      return calls.values.sum { |call| call.fetch("seconds") } if scenario.name == "calls"
      return Bench.quantile(work, 0.5) if scenario.game

      draw
    end
  end

  # Runs each scenario +settings.runs+ times and keeps its best Result,
  # the one with the shortest median draw loop (for +calls+, the shortest
  # calls in all, and for a Game, the shortest median update and draw),
  # since anything else running on the machine only ever adds time.
  class Runner
    # [timeout] Seconds a run may take before it is stopped and fails.
    def initialize(settings:, love:, directory:, out: $stdout, timeout: TIMEOUT)
      @timeout = timeout
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
      environment = scenario.environment(@settings, report)
      output, status = Bench.spawn(environment, scenario.command(love: @love), timeout: @timeout)
      raise Failure, "#{scenario} #{stopped(environment)}; it printed:\n#{output}" unless status
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

    # How a run with +environment+ that ran too long was stopped, and for
    # a Game, after which frame, by the progress file the parity harness's
    # sides write.
    private def stopped(environment)
      progress = environment["LOTA_PARITY_PROGRESS"]
      frame = (progress && File.exist?(progress)) ? File.read(progress).strip : nil
      "ran past #{@timeout} s and was stopped#{frame ? " after frame #{frame}" : ''}"
    end
  end

  # How long a run that ran too long has, once asked where it is, to say.
  WHERE = 5

  # Runs +command+ with +environment+ added to this process's, and returns
  # its output and status, or a +nil+ status if it ran past +timeout+
  # seconds and was killed, with every process it started. Before it is
  # killed, a run is sent SIGUSR1 and given WHERE seconds, so one that
  # says where it is when asked, as the parity probe's timing mode does,
  # says so in its output.
  def self.spawn(environment, command, timeout: TIMEOUT)
    Open3.popen2e(environment, *command, pgroup: true) do |stdin, output, wait|
      stdin.close
      reader = Thread.new { output.read }
      finished = wait.join(timeout)
      unless finished
        ask_where(wait.pid)
        wait.join(WHERE)
        stop(wait.pid)
      end
      [reader.value, finished && wait.value]
    rescue Interrupt
      # A run in its own process group hears no Control-C, so it is stopped
      # here when rake is.
      stop(wait.pid)
      raise
    end
  end

  # Sends SIGUSR1 to the process +pid+, unless it is already gone.
  def self.ask_where(pid)
    Process.kill(:USR1, pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
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
    # [linux] Whether the machine runs Linux rather than macOS, whose
    #   tools describe it.
    def initialize(capture: method(:capture), linux: RbConfig::CONFIG["host_os"].include?("linux"))
      @capture = capture
      @linux = linux
    end

    # Lines naming the machine, its system, its power, and the commits.
    def lines
      [*(@linux ? linux : macos), "Lota: #{commit(ROOT)}; LÖVE: #{commit(File.join(ROOT, 'vendor/love'))}"]
    end

    private def macos
      [
        "Machine: #{@capture.call('sysctl', '-n', 'hw.model')}, #{@capture.call('sysctl', '-n',
          'machdep.cpu.brand_string')}, #{memory} GB",
        "System: macOS #{@capture.call('sw_vers', '-productVersion')} " \
          "(#{@capture.call('sw_vers', '-buildVersion')})",
        "Power: #{power}",
      ]
    end

    # Linux names the processor in lscpu's report, or where that names no
    # model, as in a virtual machine, by its architecture; its memory in
    # /proc/meminfo; and the distribution in /etc/os-release; and keeps no
    # one place that says what powers the machine.
    private def linux
      processor = @capture.call("lscpu").to_s[/^Model name:\s*(.+)$/, 1] || @capture.call("uname", "-m")
      kibibytes = File.read("/proc/meminfo")[/^MemTotal:\s*(\d+)/, 1].to_i
      release = File.read("/etc/os-release")[/^PRETTY_NAME="?([^"\n]+)/, 1]
      [
        "Machine: #{processor}, #{@capture.call('nproc')} processors, #{kibibytes / (1024 ** 2)} GB",
        "System: #{release} (Linux #{@capture.call('uname', '-r')})",
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
      [header, draws, breakdown, calls, collector, *games].compact.join("\n\n") << "\n"
    end

    # Two tables for each Game that ran (#game_table and #shares).
    private def games
      GAMES.flat_map { |name, game| [game_table(name, game), shares(name)].compact }
    end

    # The game's update and draw, together, and the whole frame, the
    # median, 99th percentile, and longest, in Lota under each JIT and in
    # LÖVE, how many times LÖVE's median Lota's is, and what Ruby's
    # collector did over the frames.
    private def game_table(name, game)
      rows = [*lota_jits.map { |jit| find("lota", jit, name) }, find("love", "luajit", name)].compact
      return if rows.empty?

      love = find("love", "luajit", name)
      table("#{name}, whole, #{game.frames_under(@settings)} frames of its parity script at #{game.fps} Hz",
        [
          "engine",
          "JIT",
          "update+draw ms p50/p99/max",
          "max in frame",
          "of LÖVE's",
          "frame ms p50/p99/max",
          "objects/frame",
          "GCs (minor/major)",
          "major causes",
          "GC ms total",
          "GC ms max/frame",
],
        rows.map { |result| game_row(result, love) })
    end

    # Where the game's update and draw spend their time in Lota, under
    # each JIT that ran both runs: medians of the run without wrappers, for
    # the update and draw and the frame, and of the run that timed its
    # native calls, for those; Ruby's is the difference.
    private def shares(name)
      rows = lota_jits.filter_map do |jit|
        plain, wrapped = [name, name + NATIVE].map { |scenario| find("lota", jit, scenario) }
        next unless plain && wrapped

        work = Bench.quantile(plain.work, 0.5)
        native = Bench.quantile(wrapped.data.fetch("native"), 0.5)
        ruby = work - native
        frame = Bench.quantile(plain.data.fetch("frame"), 0.5)
        [
          jit,
          Bench.quantile(wrapped.data.fetch("native_calls"), 0.5).to_s,
          ms(work),
          ms(native),
          ms(ruby),
          percent(ruby / work),
          percent(ruby / frame),
          ms(frame),
]
      end
      return if rows.empty?

      table("Where #{name}'s update and draw spend their time in Lota (medians; ms)",
        [
          "JIT",
          "native calls/frame",
          "update+draw",
          "in native calls",
          "in Ruby",
          "Ruby of update+draw",
          "Ruby of frame",
          "frame",
],
        rows)
    end

    private def game_row(result, love)
      gc = result.gc
      collected = if gc.empty?
        ["-"] * 5
      else
        [
          (gc.fetch("total_allocated_objects") / result.work.size).to_s,
          "#{gc.fetch('count')} (#{gc.fetch('minor_gc_count')}/#{gc.fetch('major_gc_count')})",
          causes(result.major_causes),
          ms(gc.fetch("time_ns") / 1e9),
          ms(result.gc_max),
]
      end
      median = Bench.quantile(result.work, 0.5)
      [
        (result.scenario.engine == "love") ? "LÖVE" : "Lota",
        result.scenario.jit,
        spread(result.work),
        (result.work.index(result.work.max) + 1).to_s,
        love ? format("%.2fx", median / Bench.quantile(love.work, 0.5)) : "-",
        spread(result.data.fetch("frame")),
        *collected,
]
    end

    # The median, 99th percentile, and longest of +seconds+, in ms.
    private def spread(seconds)
      [Bench.quantile(seconds, 0.5), Bench.quantile(seconds, 0.99), seconds.max].map { |value| ms(value) }.join("/")
    end

    private def find(engine, jit, name)
      @results.find { |result| result.scenario == Scenario.new(engine:, jit:, name:) }
    end

    private def lota_jits
      JITS.keys.select { |jit| @results.any? { |result| result.scenario.jit == jit } }
    end

    private def header
      rubies = @results.filter_map { |result| result.data["ruby"] if result.scenario.engine == "lota" }.uniq
      love = @results.find { |result| result.scenario.engine == "love" }&.data
      lines = @machine + rubies.map { |ruby| "Ruby: #{ruby}" }
      lines += ["LÖVE: #{love.fetch('lua')}, renderer #{love.fetch('renderer')}"] if love
      (["rake bench", ""] + lines + ["", method]).join("\n")
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
        own cost, included in every other row. Each game runs whole, the
        published game in LÖVE and its translation in Lota, through the parity
        harness's two sides with a fixed dt and the same scripted keys, in the
        window its own settings ask for, and no screenshots; every frame is timed,
        from the first, and the best of #{@settings.runs} runs is kept (the shortest
        median update and draw).
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
        %w[native rectangle set_color color_writer color_reader frame].filter_map { |name| find("lota", jit, name) }
      end
      rows += %w[set_color color_reader].filter_map { |name| find("love", "luajit", name) }
      table("Allocations and the collector over #{@settings.frames} frames",
        [
          "scenario",
          "JIT",
          "draw ms",
          "objects/frame",
          "GCs (minor/major)",
          "major causes",
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
        ["-", "-", "-", "-", "-"]
      else
        [
          (gc.fetch("total_allocated_objects") / frames).to_s,
          "#{gc.fetch('count')} (#{gc.fetch('minor_gc_count')}/#{gc.fetch('major_gc_count')})",
          causes(result.major_causes),
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

    # "oldmalloc 17, nofree 1", the most frequent first, or "none".
    private def causes(counts)
      return "none" if counts.empty?

      counts.sort_by { |cause, count| [-count, cause] }.map { |cause, count| "#{cause} #{count}" }.join(", ")
    end

    # A table, or +nil+ when it has no +rows+, which the report leaves out.
    private def table(title, headings, rows)
      return if rows.empty?

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
