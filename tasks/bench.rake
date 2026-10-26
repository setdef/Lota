# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bench"

# Not part of the default task: it opens a window for each of dozens of
# runs and takes minutes. BENCH_RUNS, BENCH_FRAMES, BENCH_WARMUP,
# BENCH_DRAWS, and BENCH_CALLS change how much it measures
# (Bench::Settings).
desc "Benchmark 10,000 draw calls a frame and rules 4 and 6's Arrays, in Lota and LÖVE (writes tmp/bench)"
task bench: %w[compile reference:love] do
  settings = Bench::Settings.from(ENV)
  directory = File.expand_path("tmp/bench")
  results = Bench::Runner.new(settings:, love: REFERENCE_LOVE.executable, directory: File.join(directory, "runs")).call
  report = Bench::Report.new(results, settings:, machine: Bench::Machine.new.lines).to_s
  File.write(File.join(directory, "report.txt"), report)
  puts report
rescue Bench::Failure => e
  abort "❌ #{e.message}"
end
