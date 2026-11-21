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

namespace :bench do
  # The same measurements on an iPhone or iPad connected to this Mac, in
  # apps built, signed, and installed beforehand, as
  # doc/guide/performance.md says: BENCH_IOS_DEVICE names the device, as
  # devicectl knows it, BENCH_IOS_APP the bundle identifier of Lota's
  # bench game, and BENCH_IOS_LOVE_APP that of LÖVE's own iOS app with
  # LÖVE's bench game fused in, if it is installed. BENCH_IOS_SAVE and
  # BENCH_IOS_LOVE_SAVE name each game's save directory in its app's
  # container, when it is not the default. The other BENCH_ variables
  # shape it as they shape rake bench.
  desc "Benchmark draw calls in Lota and LÖVE on a connected iPhone or iPad (writes tmp/bench/ios)"
  task :ios do
    device = ENV.fetch("BENCH_IOS_DEVICE") { abort "❌ Set BENCH_IOS_DEVICE to the device's name or identifier" }
    lota = ENV.fetch("BENCH_IOS_APP") { abort "❌ Set BENCH_IOS_APP to the bench game's bundle identifier" }
    apps = {}
    apps["lota"] = Bench::Device::App.new(identifier: lota,
      save: ENV.fetch("BENCH_IOS_SAVE", "Library/Application Support/lota"))
    if ENV["BENCH_IOS_LOVE_APP"]
      apps["love"] = Bench::Device::App.new(identifier: ENV.fetch("BENCH_IOS_LOVE_APP"),
        save: ENV.fetch("BENCH_IOS_LOVE_SAVE", "Library/Application Support/bench"))
    end
    settings = Bench::Settings.from(ENV)
    directory = File.expand_path("tmp/bench/ios")
    runner = Bench::Device.new(device:, apps:, settings:, directory: File.join(directory, "runs"))
    results = runner.call(Bench::Device.select(Bench::Scenario.from(ENV), apps.keys))
    machine = runner.lines(Bench::Machine.new.lines.last)
    report = Bench::Report.new(results, settings:, machine:).to_s
    File.write(File.join(directory, "report.txt"), report)
    puts report
  rescue Bench::Failure => e
    abort "❌ #{e.message}"
  end
end
