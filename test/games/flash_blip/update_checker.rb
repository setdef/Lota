# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's update_checker.lua
# (test/fixtures/flash_blip/game/update_checker.lua, lines 1-144), by the
# rules of doc/contributors/design/translation.md: setColor is the writer
# color= (rules 5 and 6) and love.system.openURL Lota::System.open_url
# (rules 13 and 36). The data field RELEASES_BASE_URL reads as
# UpdateChecker.releases_base_url, and the module's locals are its
# instance variables.
#
# The update notice, its layout, and the bounds a click on it hits, tables
# with fixed fields, are a Notice, a NoticeLayout, and a Bounds. HttpClient
# takes get's options table as the keyword timeout, and its callback as
# anything that answers call. Lua patterns are regular expressions with
# the same meaning; Lua's upper knows only ASCII, as upcase(:ascii) does,
# and its tonumber is Lua.tonumber.

require "colors"
require "gamestate"
require "settings"
require "text"
require "http_client"
require "lua"

module UpdateChecker
  Notice = Struct.new(:tag, :url, :layout, keyword_init: true)
  NoticeLayout = Struct.new(:text, :scale, :draw_x, :draw_y, :bounds, keyword_init: true)
  Bounds = Struct.new(:x, :y, :width, :height, keyword_init: true)

  class << self
    attr_reader :releases_base_url
  end

  @releases_base_url = "https://github.com/plinkr/flash-blip/releases/tag/"

  VERSION_ENDPOINT = "/game_version"
  CHECK_TIMEOUT_SECONDS = 5
  NOTICE_WIDTH_PERCENTAGE = 0.3
  HIT_PADDING_X_PERCENTAGE = 0.02
  HIT_PADDING_Y_PERCENTAGE = 0.015

  @state = nil
  @started = false

  def self.parse_tag(raw)
    return nil unless raw.is_a?(String)

    raw[/"tag_name"\s*:\s*"([^"]+)"/, 1]
  end

  def self.strip_version_prefix(version)
    return "" unless version.is_a?(String)

    version.sub(/\A[vV]+/, "")
  end

  def self.split_numeric_segments(version)
    segments = []
    version.scan(/[^.]+/) do |part|
      num = Lua.tonumber(part)
      return nil unless num

      segments << num
    end
    return nil if segments.empty?

    segments
  end

  def self.is_newer(current, candidate)
    current_segments = split_numeric_segments(strip_version_prefix(current))
    candidate_segments = split_numeric_segments(strip_version_prefix(candidate))
    return false if !current_segments || !candidate_segments

    (1..([current_segments.size, candidate_segments.size].max)).each do |i|
      current_n = current_segments[i - 1] || 0
      candidate_n = candidate_segments[i - 1] || 0
      if candidate_n > current_n
        return true
      elsif candidate_n < current_n
        return false
      end
    end
    false
  end

  def self.layout_notice(tag)
    text = " █ UPDATE: #{tag.upcase(:ascii)} █"
    scale = Text.calculate_scale_for_width(text, NOTICE_WIDTH_PERCENTAGE)
    width = Text.get_text_width(text, scale)
    height = Text.get_text_height(scale)
    padding_x = Settings.window_width * HIT_PADDING_X_PERCENTAGE
    padding_y = Settings.window_height * HIT_PADDING_Y_PERCENTAGE

    draw_x = (Settings.window_width - width) * 0.03
    draw_y = Settings.window_height * 0.97
    bounds = Bounds.new(
      x: draw_x - padding_x,
      y: draw_y - padding_y,
      width: width + (padding_x * 2),
      height: height + (padding_y * 2)
    )

    NoticeLayout.new(
      text:,
      scale:,
      draw_x:,
      draw_y:,
      bounds:
    )
  end

  def self.start
    return if @started

    @started = true

    HttpClient.get(VERSION_ENDPOINT, proc do |ok, _status, data|
      next unless ok

      tag = parse_tag(data)
      if tag && is_newer(GAME_VERSION, tag)
        @state = Notice.new(
          tag:,
          url: releases_base_url + tag,
          layout: layout_notice(tag)
        )
      end
    end, timeout: CHECK_TIMEOUT_SECONDS)
  end

  def self.draw
    return if !@state || !@state.layout

    layout = @state.layout
    Lota::Graphics.color = Colors.neon_lime_splash
    Text.draw_text(layout.text, layout.draw_x, layout.draw_y, layout.scale)
    Lota::Graphics.color = Colors.white
  end

  def self.is_point_in_bounds(x, y, bounds)
    x > bounds.x && x < bounds.x + bounds.width && y > bounds.y && y < bounds.y + bounds.height
  end

  def self.handle_click(x, y)
    return false if !@state || !@state.layout
    return false if GameState.ignore_input_timer.positive? && !GameState.is_paused
    return false unless is_point_in_bounds(x, y, @state.layout.bounds)

    Lota::System.open_url(@state.url)
    true
  end
end
# SPDX-SnippetEnd
