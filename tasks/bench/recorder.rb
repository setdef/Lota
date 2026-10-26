# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

module Bench
  # Times the frames of a benchmark game from inside it (tasks/bench/lota),
  # with nothing but Ruby, so what it measures is the game and the engine.
  #
  # The game calls #draw from its draw callback with the frame's work as a
  # block. The first +warmup+ frames run untimed, so both JITs have
  # compiled the draw loop before timing starts (each compiles a method
  # once it has been called 30 times). Then each of +frames+ frames is
  # timed twice: how long the block took, and how long the whole frame
  # took, from the start of its draw to the start of the next, which takes
  # in events, update, clearing, presenting, and the loop's 1 ms sleep.
  # The collector's work in each timed frame is counted from GC.stat and
  # GC.total_time over the same span.
  class Recorder
    # Monotonic seconds, as a Float.
    CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    attr_reader :draw_times, :frame_times, :gc_times, :gc_counts

    # [warmup] Frames run before timing starts.
    # [frames] Frames timed.
    # [clock] What tells the time, in seconds.
    def initialize(warmup:, frames:, clock: CLOCK)
      @warmup = warmup
      @frames = frames
      @clock = clock
      @drawn = 0
      @open = nil
      @draw_times = []
      @frame_times = []
      @gc_times = []
      @gc_counts = []
      @gc_start = nil
    end

    # Runs the frame's work, the block, and times it. Returns +true+ once
    # every timed frame is over, without running the block, so the game
    # can quit; +false+ before.
    def draw
      start = @clock.call
      close_frame(start) if @open
      return true if done?

      warming_up = @drawn < @warmup
      @drawn += 1
      if warming_up
        yield
        return false
      end

      @gc_start ||= gc_snapshot
      @open = [start, GC.total_time, GC.count]
      yield
      @draw_times << (@clock.call - start)
      false
    end

    # Whether every timed frame is over.
    def done?
      @frame_times.size >= @frames
    end

    # What the collector did over the timed frames: collections, minor and
    # major, objects allocated, and nanoseconds spent.
    def gc
      return {} unless @gc_start

      GC_KEYS.to_h { |key| [key.to_s, gc_snapshot.fetch(key) - @gc_start.fetch(key)] }
    end

    # Everything recorded, as the Hash the game writes to its report.
    def to_h
      {
        "draw" => @draw_times,
        "frame" => @frame_times,
        "frame_gc_ns" => @gc_times,
        "frame_gc_count" => @gc_counts,
        "gc" => gc,
      }
    end

    GC_KEYS = %i[count minor_gc_count major_gc_count total_allocated_objects time_ns].freeze
    private_constant :GC_KEYS

    private def gc_snapshot
      GC.stat.slice(:count, :minor_gc_count, :major_gc_count, :total_allocated_objects)
        .merge(time_ns: GC.total_time)
    end

    private def close_frame(now)
      start, gc_time, gc_count = @open
      @frame_times << (now - start)
      @gc_times << (GC.total_time - gc_time)
      @gc_counts << (GC.count - gc_count)
      @open = nil
    end
  end

  # Times one call, the block, as the best of +repetitions+ runs of
  # +iterations+ calls, and counts the objects each allocates. Returns
  # seconds and allocations per call, as Floats.
  #
  # Each run calls the block from a short method, Bench.calls, many
  # times over, rather than from one long loop, because neither JIT
  # compiles a method until it has been called often enough, and a loop
  # in a method called once would stay interpreted however long it ran.
  def self.per_call(iterations:, repetitions: 5, chunk: 1_000, clock: Recorder::CLOCK, &)
    chunks = [iterations / chunk, 1].max
    runs = Array.new(repetitions) do
      allocated = GC.stat(:total_allocated_objects)
      start = clock.call
      chunks.times { calls(chunk, &) }
      elapsed = clock.call - start
      [elapsed, GC.stat(:total_allocated_objects) - allocated]
    end
    elapsed, allocated = runs.min_by(&:first)
    calls = chunks * chunk
    [elapsed / calls, allocated.fdiv(calls)]
  end

  # Calls the block +count+ times.
  def self.calls(count)
    i = 0
    while i < count
      yield
      i += 1
    end
  end
end
