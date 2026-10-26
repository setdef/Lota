# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"
require_relative "../../tasks/bench"
require "stringio"

# rake bench's two games (tasks/bench/lota and tasks/bench/love), each
# scenario run for a few frames of a few draws, so the gate knows they
# still run and report what the benchmark reads, without running the
# benchmark itself. It lives with the parity harness because the LÖVE
# side needs the reference love, which only test:parity builds.
class BenchGamesTest < Minitest::Test
  SETTINGS = Bench::Settings.new(draws: 20, warmup: 2, frames: 3, calls: 2_000, runs: 1)

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
      else
        assert_equal [3, 3], [result.data.fetch("draw").size, result.data.fetch("frame").size], result.scenario.to_s
        assert_operator result.frame, :>=, result.draw, result.scenario.to_s
      end
    end
    rectangle = results.find { |result| result.scenario == scenarios.find { |s| s.name == "rectangle" } }

    assert_operator rectangle.gc.fetch("total_allocated_objects"), :>=, 3 * 20, "a String per call, from :fill.to_s"
    report = Bench::Report.new(results, settings: SETTINGS, machine: []).to_s

    assert_match(/^Lota rectangle +interpreter /, report)
    assert_match(/^LÖVE rectangle +luajit /, report)
  end

  def test_lota_runs_under_the_jit_it_was_asked_for
    results = run_scenarios(%w[yjit zjit].map { |jit| Bench::Scenario.new(engine: "lota", jit:, name: "rectangle") })

    assert_equal %w[yjit zjit], results.map { |result| result.data.fetch("jit") }
  end
end
