# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's levels_selector.lua
# (test/fixtures/flash_blip/game/levels_selector.lua, lines 1-282), by the
# rules of doc/contributors/design/translation.md: setColor and
# setLineStyle are the writers color= and line_style= (rules 5 and 6),
# love.timer.getTime is Lota::Timer.time (rule 3), love.keyboard.isDown is
# Lota::Keyboard.down? (rule 8), math.random is Lota::Math.random, and the
# draw mode, line styles, and keys symbols (rule 9). The module table is
# the module LevelsSelector and its locals the module's instance
# variables. The colors module Lua names AllColors here is Colors, whose
# colors are Arrays indexed from 0. A level point, a table of x, y, and
# label, is a LevelPoint; game.rb reads its label. The loops keep Lua's
# 1-based level indices, and read the Array at index - 1. Every division
# divides Floats, as Lua's do.

require "colors"
require "settings"
require "text"
require "player_progress"
require "level_data"
require "parallax"
require "gamestate"
require "screen_utils"

module LevelsSelector
  LevelPoint = Struct.new(:x, :y, :label, keyword_init: true)

  @level_points = []
  @selected_index = 1
  @hovered_index = nil
  @current_y_offset = 0
  @target_y_offset = 0

  @last_move_time = 0
  @move_delay = 0.15

  def self.initialize_level_points
    @level_points = []
    (1..(Settings.max_levels)).each do |level_index|
      level_key = format("%02d", level_index)
      y_pct = 0.95 - ((level_index - 1) * 0.1)
      x_pct = 0.1 + (Lota::Math.random * 0.8)

      @level_points << LevelPoint.new(
        x: x_pct * Settings.window_width,
        y: y_pct * Settings.window_height,
        label: level_key,
      )
    end
  end
  private_class_method :initialize_level_points

  def self.load
    initialize_level_points
    # Initialize selected_index to the highest unlocked level
    highest_unlocked_level = 1
    @level_points.size.downto(1) do |i|
      point = @level_points[i - 1]
      if PlayerProgress.is_level_unlocked(point.label)
        highest_unlocked_level = i
        break
      end
    end
    @selected_index = highest_unlocked_level
    @target_y_offset = (@selected_index - 5) * 0.1
    @current_y_offset = @target_y_offset
  end

  def self.update(dt)
    Parallax.update(dt)
    # Smooth transition while moving between levels
    lerp_speed = 5
    @current_y_offset += (@target_y_offset - @current_y_offset) * lerp_speed * dt

    current_time = Lota::Timer.time
    if Lota::Keyboard.down?(:up) && current_time - @last_move_time > @move_delay
      move_up
      @last_move_time = current_time
    end
    if Lota::Keyboard.down?(:down) && current_time - @last_move_time > @move_delay
      move_down
      @last_move_time = current_time
    end
  end

  def self.draw
    current_level = PlayerProgress.get_current_level

    y_offset = @current_y_offset
    visible_start = [1, @selected_index - 4].max
    visible_end = [Settings.max_levels, @selected_index + 5].min

    Lota::Graphics.line_style = :rough
    (visible_start..(visible_end - 1)).each do |i|
      p1 = @level_points[i - 1]
      p2 = @level_points[i]
      Lota::Graphics.color = if PlayerProgress.is_level_unlocked(p1.label) && PlayerProgress.is_level_unlocked(p2.label)
        Colors.light_blue_glow
      else
        Colors.gunmetal_gray
      end
      draw_y1 = p1.y + (y_offset * Settings.window_height)
      draw_y2 = p2.y + (y_offset * Settings.window_height)
      Lota::Graphics.line(p1.x, draw_y1, p2.x, draw_y2)
    end
    Lota::Graphics.line_style = :smooth

    (visible_start..visible_end).each do |i|
      point = @level_points[i - 1]
      draw_y = point.y + (y_offset * Settings.window_height)

      if PlayerProgress.is_level_unlocked(point.label)
        if i == @hovered_index
          # Visual feedback for hovered level
          (1..5).each do |j|
            alpha = 1 - j.fdiv(5)
            Lota::Graphics.color = [
              Colors.tangerine_blaze[0],
              Colors.tangerine_blaze[1],
              Colors.tangerine_blaze[2],
              alpha * 0.4,
            ]
            Lota::Graphics.polygon(
              :fill,
              point.x,
              draw_y - (30 + j),
              point.x - (30 + j),
              draw_y + (30 + j),
              point.x + (30 + j),
              draw_y + (30 + j),
            )
          end
        end
        if i == @selected_index
          # Visual feedback for selected level
          (1..5).each do |j|
            alpha = 1 - j.fdiv(5)
            Lota::Graphics.color = [
              Colors.tangerine_blaze[0],
              Colors.tangerine_blaze[1],
              Colors.tangerine_blaze[2],
              alpha * 0.8,
            ]
            Lota::Graphics.polygon(
              :fill,
              point.x,
              draw_y - (30 + j),
              point.x - (30 + j),
              draw_y + (30 + j),
              point.x + (30 + j),
              draw_y + (30 + j),
            )
          end
        end
        if point.label == current_level
          (1..5).each do |j|
            alpha = 1 - j.fdiv(5)
            Lota::Graphics.color = [Colors.cyan[0], Colors.cyan[1], Colors.cyan[2], alpha * 0.2]
            Lota::Graphics.polygon(
              :fill,
              point.x,
              draw_y - (20 + j),
              point.x - (20 + j),
              draw_y + (20 + j),
              point.x + (20 + j),
              draw_y + (20 + j),
            )
          end
        end
        Lota::Graphics.color = Colors.cyan
      else
        Lota::Graphics.color = Colors.gunmetal_gray
      end

      Lota::Graphics.polygon(:fill, point.x, draw_y - 20, point.x - 20, draw_y + 20, point.x + 20, draw_y + 20)
      Lota::Graphics.color = Colors.white
      label_scale = Text.calculate_scale_for_width(point.label, 0.10)
      label_width = Text.get_text_width(point.label, label_scale)
      Text.draw_text(point.label, point.x - (label_width / 2.0), draw_y - 45, label_scale)
    end

    arrow_size = ScreenUtils.get_arrow_size
    arrow_x = 35
    arrow_y = Settings.window_height * 0.92
    arrow_hovered = ScreenUtils.is_hovering_arrow("left", arrow_x, arrow_y, arrow_size)
    arrow_color = arrow_hovered ? Colors.neon_lime_splash : Colors.crimson
    ScreenUtils.draw_arrow("left", arrow_x, arrow_y, arrow_size, arrow_color)
  end

  def self.move_up
    ((@selected_index + 1)..(@level_points.size)).each do |i|
      next unless PlayerProgress.is_level_unlocked(@level_points[i - 1].label)

      @selected_index = i
      @target_y_offset = (@selected_index - 5) * 0.1
      break
    end
  end

  def self.move_down
    (@selected_index - 1).downto(1) do |i|
      next unless PlayerProgress.is_level_unlocked(@level_points[i - 1].label)

      @selected_index = i
      @target_y_offset = (@selected_index - 5) * 0.1
      break
    end
  end

  def self.start_level(level_data)
    Main.current_level_data = level_data
    Parallax.load(level_data.background_color, level_data.star_colors)
    level_data.load
    GameState.is_attract_mode = false
    Main.init_game
    Parallax.resume
  end

  def self.keypressed(key)
    if key == :escape
      return_to_menu
    elsif key == :return
      selected_point = @level_points[@selected_index - 1]
      if selected_point && PlayerProgress.is_level_unlocked(selected_point.label)
        PlayerProgress.set_current_level(selected_point.label)
        level_data = LevelData.new(selected_point.label)
        start_level(level_data)
      end
    end
  end

  def self.return_to_menu
    GameState.is_attract_mode = true
    Main.current_level_data = nil
    Main.init_game
    GameState.set("attract")
    Parallax.resume
  end

  def self.is_return_arrow(x, y)
    arrow_size = ScreenUtils.get_arrow_size
    ScreenUtils.is_point_in_arrow("left", 35, Settings.window_height * 0.92, arrow_size, x, y)
  end

  def self.mousemove(x, y)
    # Update hovered_index based on mouse hover over unlocked levels
    y_offset = @current_y_offset
    visible_start = [1, @selected_index - 4].max
    visible_end = [Settings.max_levels, @selected_index + 5].min

    @hovered_index = nil
    (visible_start..visible_end).each do |i|
      point = @level_points[i - 1]
      draw_y = point.y + (y_offset * Settings.window_height)
      next unless x > point.x - 20 && x < point.x + 20 && y > draw_y - 20 && y < draw_y + 20
      next unless PlayerProgress.is_level_unlocked(point.label)

      @hovered_index = i
      break
    end
  end

  def self.mousepressed(x, y, button)
    if button == 1
      if is_return_arrow(x, y)
        return_to_menu
        return true
      end

      y_offset = @current_y_offset
      visible_start = [1, @selected_index - 4].max
      visible_end = [Settings.max_levels, @selected_index + 5].min

      (visible_start..visible_end).each do |i|
        point = @level_points[i - 1]
        draw_y = point.y + (y_offset * Settings.window_height)
        next unless x > point.x - 20 && x < point.x + 20 && y > draw_y - 20 && y < draw_y + 20

        if PlayerProgress.is_level_unlocked(point.label)
          @selected_index = i
          @target_y_offset = (@selected_index - 5) * 0.1
          PlayerProgress.set_current_level(point.label)
          level_data = LevelData.new(point.label)
          start_level(level_data)
        end
        break
      end
    end
    true
  end

  def self.get_level_points
    @level_points
  end
end
# SPDX-SnippetEnd
