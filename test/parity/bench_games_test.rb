# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"
require_relative "../../tasks/bench"
require "stringio"

# rake bench's two games (tasks/bench/lota and tasks/bench/love), each
# scenario run for a few frames of a few draws, and each published game
# it runs whole (Bench::GAMES) for its first frames, through the parity
# harness's timing mode, so the gate knows they still run and report what
# the benchmark reads, without running the benchmark itself. It lives
# with the parity harness because the LÖVE side needs the reference love,
# which only test:parity builds.
class BenchGamesTest < Minitest::Test
  SETTINGS = Bench::Settings.new(draws: 20, warmup: 2, frames: 3, calls: 2_000, runs: 1, game_frames: 30)

  def run_scenarios(scenarios)
    love = ENV.fetch("LOTA_REFERENCE_LOVE") do
      raise "LOTA_REFERENCE_LOVE is not set; bundle exec rake test:parity builds the reference love and sets it"
    end
    Dir.mktmpdir("lota-bench") do |directory|
      Bench::Runner.new(settings: SETTINGS, love:, directory:, out: StringIO.new).call(scenarios)
    end
  end

  def test_every_scenario_of_both_games_runs_and_reports_its_frames_or_calls
    scenarios = Bench::Scenario.all.select { |scenario| %w[interpreter luajit].include?(scenario.jit) }
    results = run_scenarios(scenarios)

    results.each do |result|
      if result.scenario.name == "calls"
        assert_operator result.calls.size, :>=, 6, result.scenario.to_s
        assert(result.calls.values.all? { |call| call.fetch("seconds").positive? }, result.scenario.to_s)
      elsif result.scenario.game
        # Every frame's update and draw are timed, and every whole frame
        # but the last, which ends as the game quits.
        assert_equal [30, 30, 29], %w[update draw frame].map { |part| result.data.fetch(part).size },
          result.scenario.to_s
        assert(result.work.all?(&:positive?), result.scenario.to_s)
        if result.scenario.engine == "lota"
          assert_equal 29, result.data.fetch("frame_gc_ns").size, result.scenario.to_s
          assert_operator result.gc.fetch("total_allocated_objects"), :>, 0, result.scenario.to_s
        end
      else
        assert_equal [3, 3], [result.data.fetch("draw").size, result.data.fetch("frame").size], result.scenario.to_s
        assert_operator result.frame, :>=, result.draw, result.scenario.to_s
        assert_kind_of Hash, result.data.fetch("gc_major_by"), result.scenario.to_s if result.scenario.engine == "lota"
      end
    end
    # Lota::Graphics.color returns a new Array each call, so the timed
    # frames allocate at least one per draw, whatever else the loop does.
    # Lota::Graphics.rectangle allocates nothing (Lota::EnumName), so its
    # count is only what the loop itself allocates each frame.
    reader = Bench::Scenario.new(engine: "lota", jit: "interpreter", name: "color_reader")
    color_reader = results.find { |result| result.scenario == reader }

    assert_operator color_reader.gc.fetch("total_allocated_objects"), :>=, 3 * 20, "an Array per call, from Lota::Graphics.color"
    report = Bench::Report.new(results, settings: SETTINGS, machine: []).to_s

    assert_match(/^Lota rectangle +interpreter /, report)
    assert_match(/^LÖVE rectangle +luajit /, report)
    assert_match(%r{^Lota +interpreter +[\d.]+/[\d.]+/[\d.]+ +\d+ +[\d.]+x }, report)
    assert_match(%r{^LÖVE +luajit +[\d.]+/[\d.]+/[\d.]+ +\d+ +1\.00x }, report)
  end

  # Runs +scenario+ once, as a phone runs it: with +environment+ added and
  # its report named by a relative path, under a home of its own. Returns
  # the report, found under that home, its output, and its status.
  def run_in_save_directory(scenario, environment = {})
    love = ENV.fetch("LOTA_REFERENCE_LOVE", "love")
    Dir.mktmpdir("lota-bench-home") do |home|
      env = scenario.environment(SETTINGS, "report.json").merge(environment).merge(
        "HOME" => home, "XDG_DATA_HOME" => File.join(home, "share"), "CFFIXED_USER_HOME" => home,
      )
      output, status = Bench.spawn(env, scenario.command(love:), timeout: 120)
      reports = Dir.glob("**/report.json", base: home)
      [(reports.size == 1) ? JSON.parse(File.read(File.join(home, reports.first))) : reports, output, status]
    end
  end

  def test_each_game_writes_a_relative_report_in_its_save_directory
    %w[lota love].each do |engine|
      jit = (engine == "lota") ? "interpreter" : "luajit"
      report, output, status = run_in_save_directory(Bench::Scenario.new(engine:, jit:, name: "rectangle"))

      assert status&.success?, "#{engine}: #{output}"
      assert_equal [3, 3], [report.fetch("draw").size, report.fetch("frame").size], engine
    end
  end

  def test_lota_runs_without_its_test_extension_as_a_phone_does
    phone = { "LOTA_BENCH_NATIVE_TEST" => "0" }
    calls, = run_in_save_directory(Bench::Scenario.new(engine: "lota", jit: "interpreter", name: "calls"), phone)
    frames, = run_in_save_directory(Bench::Scenario.new(engine: "lota", jit: "interpreter", name: "frame"), phone)
    _, output, status = run_in_save_directory(Bench::Scenario.new(engine: "lota", jit: "interpreter", name: "noop"), phone)

    refute_includes calls.fetch("calls").keys, "LotaNativeTest.noop_rectangle"
    assert_includes calls.fetch("calls").keys, "Lota::Graphics.rectangle"
    assert_equal "GC.total_time", frames.fetch("gc_clock")
    assert_equal 3, frames.fetch("frame_gc_ns").size
    refute status&.success?
    assert_match(/the scenario noop needs lota_native_test/, output)
  end

  def test_lota_runs_under_the_jit_it_was_asked_for
    results = run_scenarios(%w[yjit zjit].map { |jit| Bench::Scenario.new(engine: "lota", jit:, name: "rectangle") })

    assert_equal %w[yjit zjit], results.map { |result| result.data.fetch("jit") }
  end
end
