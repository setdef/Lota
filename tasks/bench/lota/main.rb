# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# rake bench's game for Lota (tasks/bench.rb). It runs one scenario,
# named by LOTA_BENCH_SCENARIO, and writes what it measured to
# LOTA_BENCH_REPORT as JSON, then quits.
#
# Each frame scenario makes LOTA_BENCH_DRAWS calls from the draw callback,
# in the same loop as tasks/bench/love/main.lua, so the two engines draw
# the same rectangles: 4 by 4 pixels, on a grid of 100 columns 8 pixels
# apart and rows 6 pixels apart. Bench::Recorder times them. The scenario
# +calls+ instead times single calls, each over and over, with
# Bench.per_call, and counts what each allocates.
#
# LotaNativeTest.noop_rectangle (ext/lota/native_test) takes the same
# arguments as Lota::Native::Graphics.rectangle, converted by Rice the same
# way, and does nothing, so it times the crossing from Ruby into C++ alone.

require_relative "../recorder"
require "lota_native_test"

# The scenarios, one method each, so that both JITs compile each loop as
# one method once the warm-up frames have called it often enough.
module BenchScenarios
  DRAWS = Integer(ENV.fetch("LOTA_BENCH_DRAWS", "10000"))

  # A Ruby method with rectangle's parameters that does nothing.
  def self.nothing(_mode, _x, _y, _width, _height)
    nil
  end

  # The loop, calling a Ruby method instead of the engine.
  def self.ruby_noop
    i = 0
    while i < DRAWS
      nothing("fill", (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # The loop, crossing into C++ through Rice and doing nothing there.
  def self.noop
    i = 0
    while i < DRAWS
      LotaNativeTest.noop_rectangle("fill", (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # The generated binding, called directly.
  def self.native
    i = 0
    while i < DRAWS
      Lota::Native::Graphics.rectangle("fill", (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # Lota's public method, as a game calls it.
  def self.rectangle
    i = 0
    while i < DRAWS
      Lota::Graphics.rectangle(:fill, (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # A color for each rectangle, set without allocating.
  def self.set_color
    i = 0
    while i < DRAWS
      Lota::Native::Graphics.set_color((i % 8) * 0.125, (i % 4) * 0.25, (i % 2) * 0.5, 1.0)
      Lota::Native::Graphics.rectangle("fill", (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # A color for each rectangle, set through rule 6's writer, which takes
  # an Array.
  def self.color_writer
    i = 0
    while i < DRAWS
      Lota::Graphics.color = (i % 8) * 0.125, (i % 4) * 0.25, (i % 2) * 0.5, 1.0
      Lota::Native::Graphics.rectangle("fill", (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # The color read before each rectangle, through rule 4's getter, which
  # returns an Array.
  def self.color_reader
    i = 0
    while i < DRAWS
      Lota::Graphics.color
      Lota::Native::Graphics.rectangle("fill", (i % 100) * 8, (i / 100) * 6, 4, 4)
      i += 1
    end
  end

  # The single calls the scenario +calls+ times, by name.
  def self.calls
    red = 0.25
    green = 0.5
    blue = 0.75
    alpha = 1.0
    {
      "empty block" => -> {},
      "Lota::Graphics.width" => -> { Lota::Graphics.width },
      "Lota::Graphics.color" => -> { Lota::Graphics.color },
      "Lota::Graphics.dimensions" => -> { Lota::Graphics.dimensions },
      "Lota::Native::Graphics.set_color(r, g, b, a)" => -> { Lota::Native::Graphics.set_color(red, green, blue, alpha) },
      "Lota::Graphics.color = r, g, b, a" => -> { Lota::Graphics.color = red, green, blue, alpha },
      "LotaNativeTest.noop_rectangle" => -> { LotaNativeTest.noop_rectangle("fill", 8, 6, 4, 4) },
      "Lota::Native::Graphics.rectangle" => -> { Lota::Native::Graphics.rectangle("fill", 8, 6, 4, 4) },
      "Lota::Graphics.rectangle" => -> { Lota::Graphics.rectangle(:fill, 8, 6, 4, 4) },
    }
  end
end

SCENARIO = ENV.fetch("LOTA_BENCH_SCENARIO")
REPORT = ENV.fetch("LOTA_BENCH_REPORT")
RECORDER = Bench::Recorder.new(warmup: Integer(ENV.fetch("LOTA_BENCH_WARMUP", "200")),
  frames: Integer(ENV.fetch("LOTA_BENCH_FRAMES", "2000")))
CALL_ITERATIONS = Integer(ENV.fetch("LOTA_BENCH_CALLS", "200000"))
unless SCENARIO == "calls" || BenchScenarios.respond_to?(SCENARIO)
  raise ArgumentError, "unknown scenario #{SCENARIO.inspect}"
end

def Lota.draw
  if SCENARIO == "calls"
    results = BenchScenarios.calls.transform_values do |call|
      seconds, allocations = Bench.per_call(iterations: CALL_ITERATIONS, &call)
      { "seconds" => seconds, "allocations" => allocations }
    end
    BenchReport.write("calls" => results)
  elsif RECORDER.draw { BenchScenarios.public_send(SCENARIO) }
    BenchReport.write(RECORDER.to_h)
  end
end

# Writes what was measured, and what measured it, then quits.
module BenchReport
  def self.write(results)
    jit = if defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled? then "zjit"
    elsif defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? then "yjit"
    else "interpreter"
    end
    report = {
      "engine" => "lota",
      "scenario" => SCENARIO,
      "jit" => jit,
      "ruby" => RUBY_DESCRIPTION,
      "draws" => BenchScenarios::DRAWS,
      **results,
    }
    File.write(REPORT, JSON.generate(report))
    Lota::Event.quit
  end
end
