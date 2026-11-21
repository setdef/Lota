# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/bench"
require_relative "../../tasks/bench/recorder"
require "open3"
require "stringio"

# rake bench's own code, without a window: the recorder and the per-call
# timer each game uses, the runner against a stand-in love that writes a
# report as the real games do, and the report's arithmetic.
# test/parity/bench_games_test.rb runs the real games briefly.
class BenchTest < Minitest::Test
  include TreeHelper

  # A clock that advances by the next of +steps+ each time it is read.
  def clock(*steps)
    now = 0.0
    -> { now += steps.shift || 0.0 }
  end

  def test_settings_default_to_ten_thousand_draws_and_read_overrides_from_the_environment
    assert_equal 10_000, Bench::Settings.from({}).draws
    settings = Bench::Settings.from("BENCH_FRAMES" => "7", "BENCH_RUNS" => "2")

    assert_equal [7, 2, 200], [settings.frames, settings.runs, settings.warmup]
    assert_equal({
      "LOTA_BENCH_DRAWS" => "10000",
      "LOTA_BENCH_WARMUP" => "200",
      "LOTA_BENCH_FRAMES" => "7",
      "LOTA_BENCH_CALLS" => "200000",
    }, settings.environment)
  end

  def test_every_lota_scenario_runs_under_each_jit_and_loves_under_luajit
    scenarios = Bench::Scenario.all

    assert_equal (3 * Bench::LOTA_SCENARIOS.size) + Bench::LOVE_SCENARIOS.size, scenarios.size
    zjit = scenarios.find { |scenario| scenario.jit == "zjit" && scenario.name == "noop" }
    command = zjit.command(love: "/love")

    assert_equal [RbConfig.ruby, "--zjit"], command.first(2)
    assert_equal ["exe/lota", "run", "tasks/bench/lota"],
      command.last(3).map { |path| path.delete_prefix("#{Bench::ROOT}/") }
    assert_includes command, "-I#{Bench::ROOT}/tmp/engine/build/lib"
    love = Bench::Scenario.new(engine: "love", jit: "luajit", name: "rectangle")

    assert_equal ["/love", "#{Bench::ROOT}/tasks/bench/love"], love.command(love: "/love")
    assert_equal "rectangle", love.environment(Bench::Settings.from({}), "/r.json").fetch("LOTA_BENCH_SCENARIO")
  end

  def test_bench_scenarios_picks_scenarios_by_name_in_every_engine_and_jit
    picked = Bench::Scenario.from("BENCH_SCENARIOS" => "flash_blip, calls")

    assert_equal Bench::Scenario.all.select { |scenario| %w[flash_blip calls].include?(scenario.name) }, picked
    assert_equal 8, picked.size
    assert_equal Bench::Scenario.all, Bench::Scenario.from({})
    error = assert_raises(Bench::Failure) { Bench::Scenario.from("BENCH_SCENARIOS" => "flash_blip,blip") }

    assert_includes error.message, "BENCH_SCENARIOS names no scenario blip"
  end

  def test_a_game_runs_through_each_side_of_the_parity_harness
    lota = Bench::Scenario.new(engine: "lota", jit: "yjit", name: "flash_blip").command(love: "/love")

    assert_equal [RbConfig.ruby, "--yjit"], lota.first(2)
    assert_includes lota, "-r#{Bench::ROOT}/test/parity/probe.rb"
    assert_equal ["exe/lota", "run", "test/games/flash_blip"], lota.last(3).map { |path| path.delete_prefix("#{Bench::ROOT}/") }
    love = Bench::Scenario.new(engine: "love", jit: "luajit", name: "flash_blip")

    assert_equal ["/love", "#{Bench::ROOT}/test/parity/lua"], love.command(love: "/love")
  end

  def test_a_game_runs_its_parity_script_in_the_timing_mode_with_the_harness_libraries
    in_tree do |dir|
      report = File.join(dir, "flash_blip.json")
      game = Bench::GAMES.fetch("flash_blip")
      linux = game.environment(report, Bench::Settings.from({}), linux: true)

      assert_equal %w[900 60 1600000000], linux.values_at("LOTA_PARITY_FRAMES", "LOTA_PARITY_FPS", "LOTA_PARITY_CLOCK")
      assert_equal "40:300-300,44:400-400,44:440-440", linux.fetch("LOTA_PARITY_PRESS").split(",").first(3).join(",")
      assert_equal 11, linux.fetch("LOTA_PARITY_PRESS").split(",").size
      assert_equal report, linux.fetch("LOTA_PARITY_TIMES")
      assert_equal "#{Bench::ROOT}/test/fixtures/flash_blip/game", linux.fetch("LOTA_PARITY_GAME")
      assert_equal %w[liblota_loopback.so liblota_offline.so liblota_dialogs.so],
        linux.fetch("LD_PRELOAD").split.map { |path| File.basename(path) }
      assert_path_exists linux.fetch("HOME")
      assert_equal File.join(linux.fetch("HOME"), ".local/share"), linux.fetch("XDG_DATA_HOME")
      macos = game.environment(report, Bench::Settings.from("BENCH_GAME_FRAMES" => "30"), linux: false)

      assert_equal "30", macos.fetch("LOTA_PARITY_FRAMES")
      assert_equal %w[liblota_loopback.dylib liblota_offline.dylib],
        macos.fetch("DYLD_INSERT_LIBRARIES").split(":").map { |path| File.basename(path) }
      assert_equal macos.fetch("HOME"), macos.fetch("CFFIXED_USER_HOME")
    end
  end

  def test_the_report_compares_a_games_frames_in_lota_with_loves
    game = frames(0.0, 0.0, [0, 2_000_000]).merge("update" => [0.002, 0.003, 0.004], "draw" => [0.004, 0.005, 0.006],
      "frame" => [0.016, 0.017, 0.020])
    results = [
      result("lota", "yjit", "flash_blip", game),
      result("love", "luajit", "flash_blip", "update" => [0.001] * 3, "draw" => [0.003] * 3, "frame" => [0.017] * 3,
        "lua" => "LuaJIT 2.1", "renderer" => "Vulkan"),
    ]
    text = Bench::Report.new(results, settings: Bench::Settings.from({}), machine: []).to_s

    assert_includes text, "flash_blip, whole, 900 frames of its parity script at 60 Hz"
    refute_includes text, "Draw loop", "a table with no rows is left out"
    assert_match(%r{^Lota +yjit +8\.000/10\.000/10\.000 +3 +2\.00x +17\.000/20\.000/20\.000 +3333 +3 \(2/1\) +oldmalloc 1 +4\.000 +2\.000$},
      text)
    assert_match(%r{^LÖVE +luajit +4\.000/4\.000/4\.000 +1 +1\.00x +17\.000/17\.000/17\.000 +- +- +- +- +-$}, text)
  end

  def test_lota_also_runs_each_game_timing_its_native_calls
    plain = Bench::Scenario.new(engine: "lota", jit: "yjit", name: "flash_blip")
    wrapped = Bench::Scenario.new(engine: "lota", jit: "yjit", name: "flash_blip_native_calls")

    assert_includes Bench::LOTA_SCENARIOS, wrapped.name
    refute_includes Bench::LOVE_SCENARIOS, wrapped.name
    assert_equal plain.command(love: "/love"), wrapped.command(love: "/love")
    in_tree do |dir|
      settings = Bench::Settings.from({})

      assert_equal "1", wrapped.environment(settings, File.join(dir, "w.json")).fetch("LOTA_PARITY_NATIVE_TIMES")
      refute plain.environment(settings, File.join(dir, "p.json")).key?("LOTA_PARITY_NATIVE_TIMES")
    end
  end

  def test_the_report_splits_a_games_update_and_draw_into_native_calls_and_ruby
    timed = { "update" => [0.002] * 3, "draw" => [0.006] * 3, "frame" => [0.020] * 3 }
    results = [
      result("lota", "yjit", "flash_blip", frames(0.0, 0.0).merge(timed)),
      result("lota", "yjit", "flash_blip_native_calls",
        frames(0.0, 0.0).merge(timed, "native" => [0.003, 0.002, 0.004], "native_calls" => [2600, 2600, 2610])),
    ]
    text = Bench::Report.new(results, settings: Bench::Settings.from({}), machine: []).to_s

    assert_includes text, "Where flash_blip's update and draw spend their time in Lota"
    assert_match(/^yjit +2600 +8\.000 +3\.000 +5\.000 +62\.5% +25\.0% +20\.000$/, text)
  end

  def test_quantile_takes_the_nearest_rank
    assert_equal 3, Bench.quantile([5, 1, 3, 2, 4], 0.5)
    assert_equal 100, Bench.quantile((1..100).to_a, 0.99) + 1
    assert_nil Bench.quantile([], 0.5)
  end

  def test_the_recorder_times_frames_only_after_the_warm_up
    recorder = Bench::Recorder.new(warmup: 2, frames: 2, clock: clock(1, 1, 5, 2, 10, 3, 20))
    ran = 0
    finished = Array.new(5) { recorder.draw { ran += 1 } }

    assert_equal [false, false, false, false, true], finished
    assert_equal 4, ran, "the last call runs no frame"
    # Frame 3 starts at 1 + 1 + 5 = 7 and its loop ends at 9; frame 4
    # starts at 19 and ends at 22; the last call starts at 42.
    assert_equal [2.0, 3.0], recorder.draw_times
    assert_equal [12.0, 23.0], recorder.frame_times
  end

  def test_the_recorder_counts_the_collectors_work_in_each_frame
    recorder = Bench::Recorder.new(warmup: 0, frames: 2)
    recorder.draw { 10.times { Object.new } }
    recorder.draw { GC.start(full_mark: false) }
    recorder.draw { flunk "the frames are over" }

    assert_equal [0, 1], recorder.gc_counts
    assert_operator recorder.gc.fetch("count"), :>=, 1
    assert_operator recorder.gc.fetch("total_allocated_objects"), :>=, 10
    assert_equal recorder.gc_times.size, recorder.to_h.fetch("frame_gc_ns").size
  end

  # rake bench's game times the collector by the wall clock
  # (LotaNativeTest.gc_wall_time), since GC.total_time advances only at
  # Windows' clock tick there; the clock it reads is the recorder's
  # gc_clock, read as the timed frames start, as each opens, and as each
  # closes.
  def test_the_recorder_reads_the_collectors_time_from_its_gc_clock
    recorder = Bench::Recorder.new(warmup: 0, frames: 2, gc_clock: clock(5, 3, 4, 10, 2))
    3.times { recorder.draw { nil } }

    assert_equal [4.0, 2.0], recorder.gc_times
    assert_in_delta 19.0, recorder.gc.fetch("time_ns")
  end

  # GC.start's full collection is a major one Ruby says it was forced to,
  # and the minor one before it has no such cause.
  def test_the_recorder_names_what_caused_each_major_collection_in_its_frames
    recorder = Bench::Recorder.new(warmup: 1, frames: 3)
    recorder.draw { GC.start }
    recorder.draw { GC.start(full_mark: false) }
    recorder.draw { GC.start }
    recorder.draw { 2.times { GC.start } }
    recorder.draw { flunk "the frames are over" }

    assert_equal({ "force" => 2, "unseen" => 1 }, recorder.major_causes)
    assert_equal recorder.major_causes, recorder.to_h.fetch("gc_major_by")
  end

  # The first two steps of the clock time the untimed run that warms the
  # call sites, which is not kept even though it is the fastest.
  def test_per_call_counts_allocations_and_keeps_the_fastest_run
    _, nothing = Bench.per_call(iterations: 2_000) { nil }
    _, arrays = Bench.per_call(iterations: 2_000) { Array.new(4) }
    seconds, = Bench.per_call(iterations: 2_000, repetitions: 3, clock: clock(0, 1, 0, 8, 0, 2, 0, 4)) { nil }

    assert_in_delta 0.0, nothing
    assert_in_delta 1.0, arrays
    assert_in_delta 2.0 / 2_000, seconds
  end

  # The first time Ruby runs a call site it allocates the site's inline
  # cache, so a process's first measurement, with one run, counts only
  # the block's own allocations because an untimed run warms every call
  # site first.
  def test_a_first_measurement_in_a_process_counts_only_the_blocks_allocations
    script = <<~RUBY
      require #{File.expand_path('../../tasks/bench/recorder', __dir__).dump}
      _, allocated = Bench.per_call(iterations: 2_000, repetitions: 1) { nil }
      print allocated
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "--disable-gems", "-e", script)

    assert status.success?, output
    assert_in_delta 0.0, Float(output)
  end

  # A stand-in love that writes the report a frame scenario writes, with
  # a draw time read from +draws+, one line a run, and +jit+ as the JIT
  # that ran.
  def stand_in_love(dir, draws, jit: "luajit")
    write(dir, "draws", draws.join("\n"))
    path = write(dir, "love", <<~SH)
      #!/bin/sh
      draw=$(head -n 1 #{dir}/draws); tail -n +2 #{dir}/draws > #{dir}/rest; mv #{dir}/rest #{dir}/draws
      [ "$draw" = fail ] && { echo broken; exit 3; }
      echo "a warning about the JIT"
      printf '{"scenario":"%s","jit":"#{jit}","draws":10,"draw":[%s],"frame":[1]}' "$LOTA_BENCH_SCENARIO" "$draw" > "$LOTA_BENCH_REPORT"
    SH
    File.chmod(0o755, path)
    path
  end

  def test_the_runner_keeps_the_run_with_the_shortest_draw_loop
    in_tree do |dir|
      love = stand_in_love(dir, [0.3, 0.1, 0.2])
      settings = Bench::Settings.from("BENCH_RUNS" => "3")
      out = StringIO.new
      scenario = Bench::Scenario.new(engine: "love", jit: "luajit", name: "rectangle")
      results = Bench::Runner.new(settings:, love:, directory: File.join(dir, "runs"), out:).call([scenario])

      assert_in_delta 0.1, results.first.draw
      assert_in_delta 0.01, results.first.per_draw
      assert_includes out.string, "Running love rectangle (luajit), run 3 of 3"
    end
  end

  def test_the_runner_fails_with_the_output_of_a_failed_run
    in_tree do |dir|
      love = stand_in_love(dir, ["fail"])
      runner = Bench::Runner.new(settings: Bench::Settings.from("BENCH_RUNS" => "1"), love:,
        directory: File.join(dir, "runs"), out: StringIO.new)
      scenario = Bench::Scenario.new(engine: "love", jit: "luajit", name: "rectangle")
      error = assert_raises(Bench::Failure) { runner.call([scenario]) }

      assert_includes error.message, "broken"
    end
  end

  # Ruby built without ZJIT (or YJIT) warns at --zjit and runs the
  # interpreter, and LuaJIT can start with its JIT off, so a run reports
  # the JIT that ran, and a report from any other JIT fails the run
  # rather than being labeled with the JIT that was asked for.
  def test_the_runner_fails_a_run_that_reports_another_jit_than_it_was_asked_for
    in_tree do |dir|
      love = stand_in_love(dir, [0.1], jit: "luajit, JIT off")
      runner = Bench::Runner.new(settings: Bench::Settings.from("BENCH_RUNS" => "1"), love:,
        directory: File.join(dir, "runs"), out: StringIO.new)
      scenario = Bench::Scenario.new(engine: "love", jit: "luajit", name: "rectangle")
      error = assert_raises(Bench::Failure) { runner.call([scenario]) }

      assert_includes error.message, "love rectangle (luajit) ran under luajit, JIT off"
      assert_includes error.message, "a warning about the JIT"
    end
  end

  # The run has ten seconds, not a fraction of one, to print before it is
  # killed, so a busy machine that is slow to start sh does not kill it
  # before it has printed anything; its sleep outlasts any machine.
  def test_spawn_kills_a_run_that_takes_too_long
    output, status = Bench.spawn({}, ["sh", "-c", "echo started; sleep 600"], timeout: 10)

    assert_nil status
    assert_equal "started\n", output
  end

  # Before it kills a run that took too long, spawn asks it with SIGUSR1
  # to say where it is, as the parity probe's timing mode does by printing
  # its frame and every thread's backtrace, and gives it a few seconds to.
  def test_spawn_asks_a_run_that_takes_too_long_where_it_is_before_killing_it
    script = 'trap "echo where; exit 0" USR1; echo started; while :; do sleep 1; done'
    output, status = Bench.spawn({}, ["sh", "-c", script], timeout: 10)

    assert_nil status
    assert_equal "started\nwhere\n", output
  end

  # A stand-in love that plays a game's frames into its progress file and
  # then hangs, as a game stuck in a frame does. It is a script of this
  # Ruby's, not of a shell's, and starts no other program, since a game's
  # run loads the harness's libraries (Bench::Game#environment), built for
  # this Ruby's architecture: macOS's own programs are arm64e, which dyld
  # refuses to load an arm64 library into wherever System Integrity
  # Protection is off and leaves DYLD_INSERT_LIBRARIES in place, as on
  # GitHub's macOS runners.
  def hanging_love(dir)
    path = write(dir, "love", <<~RUBY)
      #!#{RbConfig.ruby} --disable-gems
      $stdout.sync = true
      puts "frame 7 of the script"
      File.write(ENV.fetch("LOTA_PARITY_PROGRESS"), "7\\n")
      sleep 600
    RUBY
    File.chmod(0o755, path)
    path
  end

  def test_the_runner_says_how_long_a_stopped_run_ran_what_it_printed_and_where_it_got_to
    in_tree do |dir|
      runner = Bench::Runner.new(settings: Bench::Settings.from("BENCH_RUNS" => "1"), love: hanging_love(dir),
        directory: File.join(dir, "runs"), out: StringIO.new, timeout: 10)
      scenario = Bench::Scenario.new(engine: "love", jit: "luajit", name: "flash_blip")
      error = assert_raises(Bench::Failure) { runner.call([scenario]) }

      assert_includes error.message, "love flash_blip (luajit) ran past 10 s and was stopped after frame 7"
      assert_includes error.message, "frame 7 of the script"
    end
  end

  def result(engine, jit, name, data)
    Bench::Result.new(Bench::Scenario.new(engine:, jit:, name:), { "draws" => 10_000, "ruby" => "ruby 4", **data })
  end

  def frames(draw, frame, gc_ns = [0])
    {
      "draw" => [draw],
      "frame" => [frame],
      "frame_gc_ns" => gc_ns,
      "gc" => {
        "count" => 3,
        "minor_gc_count" => 2,
        "major_gc_count" => 1,
        "total_allocated_objects" => 10_000,
        "time_ns" => 4_000_000,
      },
      "gc_major_by" => { "oldmalloc" => 1 },
    }
  end

  def report
    results = [
      result("lota", "yjit", "ruby_noop", frames(0.001, 0.003)),
      result("lota", "yjit", "noop", frames(0.006, 0.008)),
      result("lota", "yjit", "native", frames(0.007, 0.009)),
      result("lota", "yjit", "rectangle", frames(0.008, 0.010, [0, 2_000_000])),
      result("lota", "yjit", "calls", "calls" => { "Lota::Graphics.color" => { "seconds" => 7e-7, "allocations" => 1.0 } }),
      result("love", "luajit", "rectangle", "draw" => [0.0005], "frame" => [0.002], "lua" => "LuaJIT 2.1",
        "renderer" => "Metal"),
      result("love", "luajit", "calls", "calls" => { "love.graphics.getColor" => { "seconds" => 2e-8 } }),
    ]
    Bench::Report.new(results, settings: Bench::Settings.from({}), machine: ["Machine: a test"]).to_s
  end

  def test_the_report_shows_each_draw_loop_per_frame_per_call_and_as_a_share_of_a_frame
    text = report

    assert_includes text, "Machine: a test\nRuby: ruby 4\nLÖVE: LuaJIT 2.1, renderer Metal"
    assert_match(/^Lota rectangle +yjit +8\.000 +800 +48\.0% +96\.0% +10\.000 +2\.000$/, text)
    assert_match(/^LÖVE rectangle +luajit +0\.500 +50 +3\.0% +6\.0% +2\.000 +1\.500$/, text)
  end

  def test_the_report_splits_a_draw_call_into_ruby_rice_love_and_the_wrapper
    assert_match(/^yjit +100 +500 +100 +100 +800 +50$/, report)
  end

  def test_the_report_shows_single_calls_and_the_collectors_work
    text = report

    assert_match(/^Lota::Graphics\.color +700 +1\.00$/, text)
    assert_match(/^love\.graphics\.getColor +20$/, text)
    assert_match(%r{^Lota rectangle +yjit +8\.000 +10000 +3 \(2/1\) +oldmalloc 1 +4\.000 +2\.000 +10\.000/10\.000/10\.000$},
      text)
  end

  def test_the_report_says_no_major_collection_had_a_cause_when_there_was_none
    data = frames(0.008, 0.010).merge("gc_major_by" => {})
    data["gc"] = data.fetch("gc").merge("major_gc_count" => 0)
    text = Bench::Report.new([result("lota", "yjit", "frame", data)], settings: Bench::Settings.from({}),
      machine: []).to_s

    assert_match(%r{^Lota frame +yjit +8\.000 +10000 +3 \(2/0\) +none +4\.000 }, text)
  end

  def test_the_machine_names_the_processor_the_system_and_the_commits
    lines = Bench::Machine.new.lines.join("\n")

    if RUBY_PLATFORM.include?("linux")
      assert_includes lines, `lscpu`[/^Model name:\s*(.+)$/, 1] || `uname -m`.strip
      assert_includes lines, "#{`nproc`.strip} processors"
      assert_includes lines, "(Linux #{`uname -r`.strip})"
    else
      assert_includes lines, `sysctl -n machdep.cpu.brand_string`.strip
      assert_includes lines, "macOS #{`sw_vers -productVersion`.strip}"
    end
    assert_includes lines, `git -C #{ROOT} rev-parse --short HEAD`.strip
  end
end
