# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's hi_scores.lua
# (test/fixtures/flash_blip/game/hi_scores.lua, lines 1-412), by the rules
# of doc/contributors/design/translation.md: setColor is the writer color=
# (rules 5 and 6), setScissor the writer scissor=, given nil where Lua
# passes nothing, love.mouse.getPosition Lota::Mouse.position, an Array
# (rules 3 and 4), love.timer.getTime Lota::Timer.time, and the draw mode a
# symbol (rule 9). The module, a local table named hi_scores, is HiScores,
# as main.lua names it, and its locals are its instance variables.
#
# A row of the table, with its text and score, is a DisplayItem, and the
# widths a table is laid out by are a Layout. A local high score from
# PlayerProgress answers score and source, and a global one from
# HighscoreManager is a HighscoreManager::ScoreEntry. loading_index stays
# 1-based, as the arithmetic that cycles it is, so it indexes loading_dots
# less one. The arrow directions are the game's own strings.

require "colors"
require "settings"
require "text"
require "player_progress"
require "gamestate"
require "highscore_manager"
require "sound"
require "screen_utils"
require "lua"

module HiScores
  DisplayItem = Struct.new(:rank_str, :name_str, :score_str, :score, keyword_init: true)
  Layout = Struct.new(:max_rank_w1, :max_row_w1, :gap1, keyword_init: true)

  @max_display_count = 10
  @cache = nil
  @uniform_scale = nil
  @count = 0

  @view_mode = "local"
  @global_page = 1
  @global_cache = nil
  @last_global_fetch_time = 0
  @global_fetch_error = nil
  @global_loading = false
  @global_display_cache = nil
  @uniform_scale_global = nil
  @local_layout = nil
  @global_layout = nil

  @loading_base = "LOADING GLOBAL SCORES"
  @loading_dots = ["", ".", "..", "..."]
  @loading_index = 1
  @loading_timer = 0
  @loading_delay = 0.25

  def self.rebuild_global_display
    if !@global_cache || @global_cache.empty?
      @global_display_cache = nil
      @uniform_scale_global = nil
      @global_layout = nil
      return
    end

    @global_display_cache = []
    start_idx = ((@global_page - 1) * 10) + 1
    end_idx = [@global_page * 10, @global_cache.size].min
    (start_idx..end_idx).each do |idx|
      entry = @global_cache[idx - 1]
      rank_str = format("%d.", idx)
      name_str = entry.player || "UNKNOWN"
      score_str = Lua.tostring(entry.score.floor)
      @global_display_cache << DisplayItem.new(
        rank_str:,
        name_str:,
        score_str:,
        score: entry.score
      )
    end

    gap1 = Text.get_text_width("  ", 1)
    gap2 = Text.get_text_width("   ", 1)
    max_rank_w1 = 0
    max_row_w1 = 0

    @global_display_cache.each do |item|
      r_w1 = Text.get_text_width(item.rank_str, 1)
      n_w1 = Text.get_text_width(item.name_str, 1)
      s_w1 = Text.get_text_width(item.score_str, 1)
      max_rank_w1 = r_w1 if r_w1 > max_rank_w1
      row_w1 = r_w1 + gap1 + n_w1 + gap2 + s_w1
      max_row_w1 = row_w1 if row_w1 > max_row_w1
    end

    target_pct = 0.75
    target_width = Settings.window_width * target_pct
    scale = target_width.fdiv(max_row_w1.positive? ? max_row_w1 : 1)
    height_factor = Settings.window_height.fdiv(800)
    min_scale = 1.2 * height_factor
    max_scale = 4.5 * height_factor
    @uniform_scale_global = scale.clamp(min_scale, max_scale)

    @global_layout = Layout.new(
      max_rank_w1:,
      max_row_w1:,
      gap1:
    )
  end

  def self.rebuild_cache
    list = PlayerProgress.get_all_high_scores
    @count = [list.size, @max_display_count].min
    if @count.zero?
      @cache = nil
      @uniform_scale = nil
      @local_layout = nil
    else
      @cache = []
      (1..@count).each do |i|
        entry = list[i - 1]
        rank_str = format("%d.", i)
        name_str = entry.source || ""
        score_str = Lua.tostring(entry.score.floor)
        @cache << DisplayItem.new(
          rank_str:,
          name_str:,
          score_str:,
          score: entry.score
        )
      end

      gap1 = Text.get_text_width("  ", 1)
      gap2 = Text.get_text_width("   ", 1)
      max_rank_w1 = 0
      max_row_w1 = 0

      @cache.each do |item|
        r_w1 = Text.get_text_width(item.rank_str, 1)
        n_w1 = Text.get_text_width(item.name_str, 1)
        s_w1 = Text.get_text_width(item.score_str, 1)
        max_rank_w1 = r_w1 if r_w1 > max_rank_w1
        row_w1 = r_w1 + gap1 + n_w1 + gap2 + s_w1
        max_row_w1 = row_w1 if row_w1 > max_row_w1
      end

      target_pct = 0.75
      target_width = Settings.window_width * target_pct
      scale = target_width.fdiv(max_row_w1.positive? ? max_row_w1 : 1)
      height_factor = Settings.window_height.fdiv(800)
      min_scale = 1.2 * height_factor
      max_scale = 4.5 * height_factor
      @uniform_scale = scale.clamp(min_scale, max_scale)

      @local_layout = Layout.new(
        max_rank_w1:,
        max_row_w1:,
        gap1:
      )
    end

    now = Lota::Timer.time
    needs_fetch = (!@global_cache && !@global_loading && !@global_fetch_error) ||
      (now - @last_global_fetch_time > 60 && !@global_loading) ||
      (GameState.has_played_since_hi_scores && !@global_loading)

    return unless needs_fetch

    GameState.has_played_since_hi_scores = false
    @global_loading = true
    @loading_index = 1
    @loading_timer = 0
    @global_fetch_error = nil

    HighscoreManager.start_download
    @last_global_fetch_time = now
  end

  def self.is_hovering(ax, ay, rx, ry)
    mx, my = Lota::Mouse.position
    (mx - ax).abs <= rx && (my - ay).abs <= ry
  end

  def self.update(dt)
    if HighscoreManager.is_downloading
      HighscoreManager.poll_download(proc do |success, data|
        @global_loading = false
        if success
          @global_cache = data
          @global_fetch_error = nil
          rebuild_global_display
        else
          @global_cache = nil
          @global_fetch_error = data
        end
      end)
    end

    @loading_timer += dt
    return unless @loading_timer >= @loading_delay

    @loading_timer = 0
    @loading_index = (@loading_index % @loading_dots.size) + 1
  end

  def self.draw
    if GameState.hi_scores_dirty
      GameState.hi_scores_dirty = false
      @view_mode = "local"
      @global_page = 1
      @loading_index = 1
      @loading_timer = 0
      rebuild_cache
    end

    Lota::Graphics.color = 0, 0, 0, 0.8
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)

    Lota::Graphics.color = Colors.cyan
    if @view_mode == "local"
      Text.draw_centered_text("LOCAL HI SCORES", Settings.window_height * 0.1, 0.75)
    else
      Text.draw_centered_text("GLOBAL HI SCORES", Settings.window_height * 0.1, 0.75)
    end

    top_boundary = Settings.window_height * 0.18
    bottom_boundary = Settings.window_height * 0.80
    start_y = Settings.window_height * 0.22
    spacing = Settings.window_height * 0.055

    Lota::Graphics.scissor = 0, top_boundary, Settings.window_width, bottom_boundary - top_boundary

    if @view_mode == "local"
      if @count.zero?
        Lota::Graphics.color = Colors.white
        Text.draw_centered_text("NO HIGH SCORES", Settings.window_height * 0.45, 0.6)
      elsif @cache && @local_layout && @uniform_scale
        total_width = @local_layout.max_row_w1 * @uniform_scale
        start_x = (Settings.window_width - total_width) / 2.0
        name_x = start_x + ((@local_layout.max_rank_w1 + @local_layout.gap1) * @uniform_scale)
        end_x = start_x + total_width

        (1..@count).each do |i|
          item = @cache[i - 1]
          next unless item

          y_pos = start_y + ((i - 1) * spacing)
          Lota::Graphics.color = if item.score >= 100_000
            Colors.tangerine_blaze
          else
            Colors.neon_lime_splash
          end

          Text.draw_text(item.rank_str, start_x, y_pos, @uniform_scale)
          Text.draw_text(item.name_str, name_x, y_pos, @uniform_scale)

          score_w = Text.get_text_width(item.score_str, @uniform_scale)
          Text.draw_text(item.score_str, end_x - score_w, y_pos, @uniform_scale)
        end
      end
    elsif @global_loading
      Lota::Graphics.color = Colors.white
      full_text = "#{@loading_base}..."
      scale = Text.calculate_scale_for_width(full_text, 0.5)
      height_factor = Settings.window_height.fdiv(800)
      scale = [0.5 * height_factor, scale].max
      full_width = Text.get_text_width(full_text, scale)
      x_start = (Settings.window_width - full_width) / 2.0
      display_text = @loading_base + @loading_dots[@loading_index - 1]
      Text.draw_text(display_text, x_start, Settings.window_height * 0.45, scale)
    elsif @global_fetch_error
      Lota::Graphics.color = Colors.crimson
      Text.draw_centered_text("CONNECTION ERROR", Settings.window_height * 0.42, 0.55)
      Lota::Graphics.color = Colors.white
      Text.draw_centered_text("NO GLOBAL HIGH SCORES", Settings.window_height * 0.52, 0.45)
    elsif !@global_cache || @global_cache.empty?
      Lota::Graphics.color = Colors.white
      Text.draw_centered_text("NO GLOBAL HIGH SCORES", Settings.window_height * 0.45, 0.6)
    elsif @global_display_cache && @global_layout && @uniform_scale_global
      total_width = @global_layout.max_row_w1 * @uniform_scale_global
      start_x = (Settings.window_width - total_width) / 2.0
      name_x = start_x + ((@global_layout.max_rank_w1 + @global_layout.gap1) * @uniform_scale_global)
      end_x = start_x + total_width

      (1..(@global_display_cache.size)).each do |i|
        item = @global_display_cache[i - 1]
        next unless item

        y_pos = start_y + ((i - 1) * spacing)
        Lota::Graphics.color = if item.score >= 100_000
          Colors.tangerine_blaze
        else
          Colors.neon_lime_splash
        end

        Text.draw_text(item.rank_str, start_x, y_pos, @uniform_scale_global)
        Text.draw_text(item.name_str, name_x, y_pos, @uniform_scale_global)

        score_w = Text.get_text_width(item.score_str, @uniform_scale_global)
        Text.draw_text(item.score_str, end_x - score_w, y_pos, @uniform_scale_global)
      end
    end

    Lota::Graphics.scissor = nil

    arrow_size = ScreenUtils.get_arrow_size

    if @view_mode == "local"
      rx = Settings.window_width - 35
      ry = Settings.window_height * 0.5
      r_hovered = ScreenUtils.is_hovering_arrow("right", rx, ry, arrow_size)
      r_color = r_hovered ? Colors.neon_lime_splash : Colors.cyan
      ScreenUtils.draw_arrow("right", rx, ry, arrow_size, r_color)
    else
      lx = 35
      ly = Settings.window_height * 0.5
      l_hovered = ScreenUtils.is_hovering_arrow("left", lx, ly, arrow_size)
      l_color = l_hovered ? Colors.neon_lime_splash : Colors.cyan
      ScreenUtils.draw_arrow("left", lx, ly, arrow_size, l_color)

      if @global_cache && !@global_cache.empty?
        if @global_page > 1
          ux = (Settings.window_width / 2.0) - 40
          uy = Settings.window_height * 0.83
          u_hovered = is_hovering(ux, uy, 25, 25)
          u_color = u_hovered ? Colors.neon_lime_splash : Colors.cyan
          ScreenUtils.draw_arrow("up", ux, uy, arrow_size, u_color)
        end

        if @global_cache.size > @global_page * 10 && @global_page < 10
          dx = (Settings.window_width / 2.0) + 40
          dy = Settings.window_height * 0.83
          d_hovered = is_hovering(dx, dy, 25, 25)
          d_color = d_hovered ? Colors.neon_lime_splash : Colors.cyan
          ScreenUtils.draw_arrow("down", dx, dy, arrow_size, d_color)
        end
      end
    end

    Text.draw_game_version

    return_text = ScreenUtils.get_return_prompt

    return_y = Settings.window_height * 0.92
    ScreenUtils.draw_return_control(return_text, return_y, 0.7)
  end

  def self.keypressed(_key); end

  def self.mousepressed(x, y, button)
    return true if button != 1

    is_in_bounds = lambda do |bx, by, rx, ry|
      (x - bx).abs <= rx && (y - by).abs <= ry
    end

    is_in_rect = lambda do |x1, y1, x2, y2|
      x >= x1 && x <= x2 && y >= y1 && y <= y2
    end

    return_text = ScreenUtils.get_return_prompt
    return_y = Settings.window_height * 0.92
    return_width_percentage = 0.7
    if ScreenUtils.is_return_control_clicked(return_text, return_y, return_width_percentage, x, y)
      GameState.set(GameState.previous || "attract")
      Sound.play("blip")
      return true
    end

    if @view_mode == "local"
      if is_in_rect.call(
        Settings.window_width - 70,
        Settings.window_height * 0.18,
        Settings.window_width,
        Settings.window_height * 0.88
      )

        @view_mode = "global"
        @global_page = 1
        rebuild_global_display
        Sound.play("blip")
        return true
      end
    else
      if is_in_rect.call(0, Settings.window_height * 0.18, 70, Settings.window_height * 0.88)
        @view_mode = "local"
        Sound.play("blip")
        return true
      end

      if @global_cache && !@global_cache.empty?
        if @global_page > 1
          ux = (Settings.window_width / 2.0) - 40
          uy = Settings.window_height * 0.83
          if is_in_bounds.call(ux, uy, 25, 25)
            @global_page -= 1
            rebuild_global_display
            Sound.play("blip")
            return true
          end
        end

        if @global_cache.size > @global_page * 10 && @global_page < 10
          dx = (Settings.window_width / 2.0) + 40
          dy = Settings.window_height * 0.83
          if is_in_bounds.call(dx, dy, 25, 25)
            @global_page += 1
            rebuild_global_display
            Sound.play("blip")
            return true
          end
        end
      end
    end

    true
  end
end
# SPDX-SnippetEnd
