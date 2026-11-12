# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's glow_benchmark.lua
# (test/fixtures/flash_blip/game/glow_benchmark.lua, lines 1-122), by the
# rules of doc/contributors/design/translation.md: love.timer.getTime
# becomes Lota::Timer.time (rule 3). The module table's fields are the
# module's accessors, and the callback it stores is anything that answers
# call.

require "settings"

module GlowBenchmark
  class << self
    attr_accessor :glow_testing, :glow_start_time, :glow_warmup_end, :glow_test_end, :glow_frame_count,
      :glow_notice_message, :glow_notice_timer, :glow_needs_benchmark, :on_glow_disabled
  end

  @glow_testing = false
  @glow_start_time = 0
  @glow_warmup_end = 0
  @glow_test_end = 0
  @glow_frame_count = 0
  @glow_notice_message = ""
  @glow_notice_timer = 0
  @glow_needs_benchmark = false
  @on_glow_disabled = nil

  def self.init
    GlowBenchmark.glow_needs_benchmark = Settings.is_glow_enabled &&
      (Settings.is_mobile || Settings.is_web) &&
      !Settings.has_passed_glow_test
  end

  def self.set_on_glow_disabled(callback)
    GlowBenchmark.on_glow_disabled = callback
  end

  def self.start
    GlowBenchmark.glow_testing = true
    now = Lota::Timer.time
    GlowBenchmark.glow_start_time = now
    GlowBenchmark.glow_warmup_end = now + 0.5
    GlowBenchmark.glow_test_end = now + 3.0
    GlowBenchmark.glow_frame_count = 0
    GlowBenchmark.glow_notice_message = ""
    GlowBenchmark.glow_notice_timer = 0
    GlowBenchmark.glow_needs_benchmark = false
  end

  def self.stop
    GlowBenchmark.glow_testing = false
    GlowBenchmark.glow_needs_benchmark = false
  end

  def self.is_benchmark_needed
    GlowBenchmark.glow_needs_benchmark
  end

  def self.is_testing
    GlowBenchmark.glow_testing
  end

  def self.get_notice
    GlowBenchmark.glow_notice_message
  end

  def self.get_notice_timer
    GlowBenchmark.glow_notice_timer
  end

  def self._disable
    Settings.is_glow_enabled = false
    Settings.has_passed_glow_test = false
    Settings.save_debounced
    GlowBenchmark.on_glow_disabled&.call
    GlowBenchmark.glow_testing = false
    GlowBenchmark.glow_needs_benchmark = false
    GlowBenchmark.glow_notice_message = "GLOW DISABLED: UNSUPPORTED / LOW FPS"
    GlowBenchmark.glow_notice_timer = 4.0
  end

  def self.update(dt)
    GlowBenchmark.glow_notice_timer -= dt if GlowBenchmark.glow_notice_timer.positive?

    return unless GlowBenchmark.glow_testing

    now = Lota::Timer.time
    total_elapsed = now - GlowBenchmark.glow_start_time

    # Warmup phase (first 0.5 seconds of wall time)
    return if now < GlowBenchmark.glow_warmup_end

    GlowBenchmark.glow_frame_count += 1
    sample_elapsed = now - GlowBenchmark.glow_warmup_end

    # Check FPS continuously after 0.3 seconds of active sampling
    if sample_elapsed >= 0.3
      real_fps = GlowBenchmark.glow_frame_count / sample_elapsed
      if real_fps < 25
        GlowBenchmark._disable
        return
      end
    end

    # maximum 3.0 seconds total wall time for testing
    return unless total_elapsed >= 3.0

    if sample_elapsed.positive?
      final_fps = GlowBenchmark.glow_frame_count / sample_elapsed
      if final_fps < 25
        GlowBenchmark._disable
        return
      end
    end

    GlowBenchmark.glow_notice_message = "GLOW SUPPORTED"
    GlowBenchmark.glow_notice_timer = 2.0
    Settings.has_passed_glow_test = true
    Settings.save_debounced
    GlowBenchmark.glow_testing = false
    GlowBenchmark.glow_needs_benchmark = false
    nil
  end

  def self.draw; end
end
# SPDX-SnippetEnd
