# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/bench"
require_relative "../../tasks/bench/recorder"
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

  def test_per_call_counts_allocations_and_keeps_the_fastest_run
    _, nothing = Bench.per_call(iterations: 2_000) { nil }
    _, arrays = Bench.per_call(iterations: 2_000) { Array.new(4) }
    seconds, = Bench.per_call(iterations: 2_000, repetitions: 3, clock: clock(0, 8, 0, 2, 0, 4)) { nil }

    assert_in_delta 0.0, nothing
    assert_in_delta 1.0, arrays
    assert_in_delta 2.0 / 2_000, seconds
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

  def test_spawn_kills_a_run_that_takes_too_long
    output, status = Bench.spawn({}, ["sh", "-c", "echo started; sleep 10"], timeout: 0.5)

    assert_nil status
    assert_equal "started\n", output
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
    assert_match(%r{^Lota rectangle +yjit +8\.000 +10000 +3 \(2/1\) +4\.000 +2\.000 +10\.000/10\.000/10\.000$}, text)
  end

  def test_the_machine_names_the_processor_the_system_and_the_commits
    lines = Bench::Machine.new.lines.join("\n")

    assert_includes lines, `sysctl -n machdep.cpu.brand_string`.strip
    assert_includes lines, "macOS #{`sw_vers -productVersion`.strip}"
    assert_includes lines, `git -C #{ROOT} rev-parse --short HEAD`.strip
  end
end
