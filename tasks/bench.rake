# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bench"

# Not part of the default task: it opens a window for each of dozens of
# runs and takes minutes. BENCH_RUNS, BENCH_FRAMES, BENCH_WARMUP,
# BENCH_DRAWS, BENCH_CALLS, and BENCH_GAME_FRAMES change how much it measures,
# and BENCH_SCENARIOS which scenarios it runs
# (Bench::Settings, Bench::Scenario.from). The reference love is the one
# reference:love builds and names in LOTA_REFERENCE_LOVE.
desc "Benchmark 10,000 draw calls a frame, rules 4 and 6's Arrays, a game's frame, and a published game, in Lota and LÖVE " \
  "(writes tmp/bench)"
task bench: %w[compile reference:love] do
  settings = Bench::Settings.from(ENV)
  directory = File.expand_path("tmp/bench")
  results = Bench::Runner.new(settings:, love: ENV.fetch("LOTA_REFERENCE_LOVE"), directory: File.join(directory, "runs"))
    .call(Bench::Scenario.from(ENV))
  report = Bench::Report.new(results, settings:, machine: Bench::Machine.new.lines).to_s
  File.write(File.join(directory, "report.txt"), report)
  puts report
rescue Bench::Failure => e
  abort "❌ #{e.message}"
end
