# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's text.lua
# (test/fixtures/flash_blip/game/text.lua, lines 1-298), by the rules of
# doc/contributors/design/translation.md: setColor is the writer color=
# (rules 5 and 6) and the draw mode a symbol (rule 9). The module table is
# the module Text; its local functions are private module methods.
#
# Lua walks text with the byte pattern UTF8_PATTERN, a lead byte (ASCII or
# 0xC2-0xF4) and the continuation bytes after it, skipping any other byte,
# and string.upper changes only ASCII letters. Text.each_char does the same
# on the text's bytes, with a binary regexp and ASCII-only upcase, and
# hands each piece on as a UTF-8 String, so "█" and "░" find their glyphs
# as Lua's byte strings do. Numbers Lua turns into text go through
# Lua.tostring, and every division divides Floats, as Lua's do. A menu item
# is Input's record; draw_menu_items assigns its y and height, as Lua does.

require "lua"
require "custom_font"
require "colors"
require "settings"

module Text
  UTF8_PATTERN = /[\x00-\x7F\xC2-\xF4][\x80-\xBF]*/n

  CustomFont.init

  @char_height = CustomFont.char_height

  class << self
    attr_accessor :char_height
  end

  def self.draw_centered_text(text, y_position, width_percentage, min_scale = nil, max_scale = nil)
    scale = calculate_scale_for_width(text, width_percentage)

    if min_scale && max_scale
      height_factor = Settings.window_height.fdiv(800)
      min_scale *= height_factor
      max_scale = [max_scale, max_scale * height_factor].min
      # Not clamp: min_scale passes max_scale on tall windows, where clamp
      # raises and Lua's math.max(min, math.min(max, s)) gives min_scale.
      scale = [max_scale, scale].min
      scale = [min_scale, scale].max
    end

    text_width = get_text_width(text, scale)
    x = (Settings.window_width - text_width) / 2.0
    draw_text(text, x, y_position, scale)
  end

  def self.draw_menu_items(menu_items, selected_item, start_y, width_percentage)
    uniform_scale = calculate_uniform_scale(menu_items, width_percentage)

    y_pos = start_y
    menu_items.each_with_index do |item, index|
      Lota::Graphics.color = if index + 1 == selected_item
        Colors.cyan
      else
        Colors.white
      end
      # Use the uniform scale for all items
      text_width = get_text_width(item.text, uniform_scale)
      x = (Settings.window_width - text_width) / 2.0
      draw_text(item.text, x, y_pos, uniform_scale)
      item.y = y_pos # Store y position for click detection
      item.height = get_text_height(uniform_scale) # Uniform height based on uniform scale
      y_pos += 50
    end
  end
  private_class_method :draw_menu_items

  def self.draw_high_score_flash(hi_score, is_new_hi_score, hi_score_flash_visible)
    return unless is_new_hi_score && hi_score_flash_visible

    Lota::Graphics.color = Colors.neon_lime_splash
    draw_centered_text("NEW HIGH", Settings.window_height * 0.08, 0.8)
    draw_centered_text("SCORE!", Settings.window_height * 0.18, 0.55)
    draw_centered_text(Lua.tostring(hi_score.floor), Settings.window_height * 0.27, 0.5, 12.0, 15.0)
  end
  private_class_method :draw_high_score_flash

  # draw_all_levels_completed calls this with no arguments, as Lua does, and
  # then fails where Lua fails, adding to a nil y.
  def self.draw_continue_prompt(action_text = nil, action_text_size = nil, prompt_y = nil, action_y = nil)
    input_prompt = if Settings.is_mobile
      "TOUCH / TAP ON SCREEN"
    else
      "PRESS SPACE OR CLICK"
    end

    Lota::Graphics.color = Colors.white
    draw_centered_text(input_prompt, prompt_y, 0.9)
    draw_centered_text(action_text, action_y, action_text_size)
  end
  private_class_method :draw_continue_prompt

  def self.draw_attract(menu_items, selected_item)
    Lota::Graphics.color = [0, 0, 0, 0.5]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)
    Lota::Graphics.color = Colors.cyan
    draw_centered_text("FLASH-BLIP", Settings.window_height * 0.15, 0.95)

    draw_menu_items(menu_items, selected_item, Settings.window_height * 0.4, 0.55)

    draw_game_version
    Lota::Graphics.color = [1, 1, 1]
  end

  def self.draw_game_version
    Lota::Graphics.color = Colors.light_blue_glow
    game_version_scale = calculate_scale_for_width(GAME_VERSION, 0.09)
    game_version_width = get_text_width(GAME_VERSION, game_version_scale)
    draw_text(
      GAME_VERSION,
      (Settings.window_width - game_version_width) * 0.97,
      Settings.window_height * 0.97,
      game_version_scale,
    )
  end

  def self.draw_pause_menu(menu_items, selected_item, level_id)
    Lota::Graphics.color = [0, 0, 0, 0.65]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)
    Lota::Graphics.color = Colors.cyan
    draw_centered_text("PAUSED", Settings.window_height * 0.25, 0.6)

    if level_id
      level_text = "LEVEL #{Lua.tostring(level_id)}"
      Lota::Graphics.color = Colors.spring_green
      draw_centered_text(level_text, Settings.window_height * 0.35, 0.3)
    end

    draw_menu_items(menu_items, selected_item, Settings.window_height * 0.5, 0.5)

    Lota::Graphics.color = [1, 1, 1]
  end

  def self.draw_game_over(hi_score, is_new_hi_score, hi_score_flash_visible)
    Lota::Graphics.color = [0, 0, 0, 0.65]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)

    draw_high_score_flash(hi_score, is_new_hi_score, hi_score_flash_visible)

    Lota::Graphics.color = Colors.naranja_rojo
    draw_centered_text("GAME OVER", Settings.window_height * 0.4, 0.9)

    draw_continue_prompt("TO RESTART", 0.45, Settings.window_height * 0.55, Settings.window_height * 0.6)
  end

  def self.draw_completion_background(hi_score, is_new_hi_score, hi_score_flash_visible)
    Lota::Graphics.color = [0, 0, 0, 0.65]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)

    draw_high_score_flash(hi_score, is_new_hi_score, hi_score_flash_visible)
  end
  private_class_method :draw_completion_background

  def self.draw_level_completed(hi_score, is_new_hi_score, hi_score_flash_visible)
    draw_completion_background(hi_score, is_new_hi_score, hi_score_flash_visible)

    Lota::Graphics.color = Colors.neon_lime_splash
    draw_centered_text("LEVEL", Settings.window_height * 0.4, 0.5)
    draw_centered_text("COMPLETED!", Settings.window_height * 0.5, 0.9)

    draw_continue_prompt("TO CONTINUE", 0.5, Settings.window_height * 0.7, Settings.window_height * 0.75)
  end

  def self.draw_all_levels_completed(hi_score, is_new_hi_score, hi_score_flash_visible)
    draw_completion_background(hi_score, is_new_hi_score, hi_score_flash_visible)

    Lota::Graphics.color = Colors.neon_lime_splash
    draw_centered_text("YOU COMPLETED", Settings.window_height * 0.4, 0.95)
    draw_centered_text("ALL LEVELS!", Settings.window_height * 0.48, 0.8)
    draw_centered_text("A GREAT FEAT!", Settings.window_height * 0.56, 0.9)

    draw_continue_prompt
  end

  def self.draw_score(score, hi_score, is_multiplying)
    current_score_text = Lua.tostring(score.floor)
    score_color = Colors.white
    score_scale = calculate_scale_for_width(current_score_text, 0.15)

    if is_multiplying
      current_score_text = "#{current_score_text} X4"
      score_scale = calculate_scale_for_width(current_score_text, 0.4)
      score_color = Colors.yellow
    end

    # Apply min/max scale based on window height
    height_factor = Settings.window_height.fdiv(800)
    min_scale = 3 * height_factor
    max_scale = 5 * height_factor
    score_scale = score_scale.clamp(min_scale, max_scale)

    Lota::Graphics.color = score_color
    current_score_text_height = get_text_height(score_scale)
    # Bottom left Score
    draw_text(current_score_text, 10, Settings.window_height - current_score_text_height - 10, score_scale)

    Lota::Graphics.color = Colors.white
    hi_score_text = "HI: #{Lua.tostring(hi_score.floor)}"
    hi_score_scale = calculate_scale_for_width(hi_score_text, 0.15)
    hi_score_scale = hi_score_scale.clamp(min_scale, max_scale)
    hi_score_text_width = get_text_width(hi_score_text, hi_score_scale)
    hi_score_text_height = get_text_height(hi_score_scale)
    # Bootom right High Score
    draw_text(
      hi_score_text,
      Settings.window_width - hi_score_text_width - 10,
      Settings.window_height - hi_score_text_height - 10,
      hi_score_scale,
    )
  end

  def self.draw_level_progress(current, total, final_color = nil)
    progress = [1.0, current.fdiv(total)].min
    # Bar size to just below the drawing position of the bolt powerup
    bar_height = Settings.window_height * 0.29
    bar_width = 4
    margin = 12
    x = Settings.window_width - margin
    # Starting position it just above the Hi Score area
    hi_score_area_height = Settings.window_height * 0.05
    y = Settings.window_height - hi_score_area_height

    # Background track (dim black bar)
    Lota::Graphics.color = [0, 0, 0, 0.8]
    Lota::Graphics.rectangle(:fill, x, y - bar_height, bar_width, bar_height, 1, 1)

    # Completion Fill (Bottom to Top)
    start_color = Colors.periwinkle_mist
    end_color = final_color || Colors.antique_gold
    fill_color = Colors.lerp(start_color, end_color, progress)

    Lota::Graphics.color = fill_color
    current_height = bar_height * progress
    Lota::Graphics.rectangle(:fill, x, y - current_height, bar_width, current_height, 1, 1)

    # Percentage text
    percent_value = (progress * 100).floor
    percent_text = "#{Lua.tostring(percent_value)}%"
    # Use a fixed reference to calculate scale so it doesn't change as numbers grow
    percent_scale = calculate_scale_for_width("100", 0.05)
    percent_width = get_text_width(percent_text, percent_scale)
    percent_height = get_text_height(percent_scale)

    Lota::Graphics.color = fill_color
    draw_text(percent_text, x - percent_width - 2, y - current_height - (percent_height / 2.0), percent_scale)

    Lota::Graphics.color = [1, 1, 1, 1]
  end

  def self.draw_text_by_percentage(text, x_position, y_position, width_percentage)
    scale = calculate_scale_for_width(text, width_percentage)
    draw_text(text, x_position, y_position, scale)
  end

  # Yields each character Lua's gmatch(UTF8_PATTERN) finds in +text+, as
  # string.upper leaves it: matched on the bytes, upcased in ASCII only,
  # and handed on as UTF-8.
  def self.each_char(text)
    text.b.scan(UTF8_PATTERN) do |raw_char|
      yield raw_char.upcase.force_encoding(Encoding::UTF_8)
    end
  end
  private_class_method :each_char

  def self.draw_text(text, x, y, scale = nil)
    scale ||= 1
    current_x = x || 0

    # Display block characters such as █.
    each_char(text) do |char|
      glyph = CustomFont.glyphs[char]

      if glyph
        glyph.each_with_index do |row_str, row_index|
          row_str.length.times do |col_index|
            if row_str[col_index] != " "
              Lota::Graphics.rectangle(:fill, current_x + (col_index * scale), y + (row_index * scale), scale, scale)
            end
          end
        end

        width = CustomFont.glyph_widths[char] || CustomFont.space_width
        current_x += (width + CustomFont.tracking) * scale
      else
        # Character not found, advance as a space
        current_x += (CustomFont.space_width + CustomFont.tracking) * scale
      end
    end
  end

  def self.get_text_width(text, scale = nil)
    scale ||= 1
    total_width = 0
    each_char(text) do |char|
      width = CustomFont.glyph_widths[char] || CustomFont.space_width
      total_width += (width + CustomFont.tracking) * scale
    end
    total_width
  end

  def self.get_text_height(scale = nil)
    scale ||= 1
    CustomFont.char_height * scale
  end

  def self.calculate_scale_for_width(text, width_percentage)
    target_width = Settings.window_width * width_percentage
    text_width_at_scale1 = get_text_width(text, 1)
    return 1 if text_width_at_scale1.zero?

    target_width.fdiv(text_width_at_scale1)
  end

  def self.calculate_uniform_scale(menu_items, width_percentage)
    # Find the text with the maximum width at scale 1 to determine the uniform scale
    max_width = 0
    max_width_text = ""
    menu_items.each do |item|
      text_width = get_text_width(item.text, 1)
      if text_width > max_width
        max_width = text_width
        max_width_text = item.text
      end
    end
    # Calculate the uniform scale based on the longest text
    calculate_scale_for_width(max_width_text, width_percentage)
  end
end
# SPDX-SnippetEnd
