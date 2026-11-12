# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's screen_utils.lua
# (test/fixtures/flash_blip/game/screen_utils.lua, lines 1-95), by the rules
# of doc/contributors/design/translation.md: love.graphics.setColor becomes
# the writer Lota::Graphics.color= (rules 5 and 6), the draw mode "fill" a
# symbol (rule 9), and love.mouse.getPosition Lota::Mouse.position, an
# Array (rules 3 and 4). The screen_utils table becomes the module
# ScreenUtils, and its local functions private methods of it; the functions
# that return two values return an Array. The arrow's direction is the
# game's own String. Lua numbers are all doubles, so where Lua divides,
# Ruby divides by a Float.

require "settings"
require "text"
require "colors"

module ScreenUtils
  ARROW_HITBOX_PADDING_RATIO = 0.75

  def self.get_arrow_points(direction, x, y, size)
    case direction
    when "right"
      [x - (size / 2.0), y - size, x + size, y, x - (size / 2.0), y + size]
    when "left"
      [x + (size / 2.0), y - size, x - size, y, x + (size / 2.0), y + size]
    when "up"
      [x - size, y + (size / 2.0), x, y - size, x + size, y + (size / 2.0)]
    when "down"
      [x - size, y - (size / 2.0), x, y + size, x + size, y - (size / 2.0)]
    end
  end
  private_class_method :get_arrow_points

  def self.is_point_in_arrow_hitbox(x, y, points, size, point_x, point_y)
    min_x = [points[0], points[2], points[4]].min
    max_x = [points[0], points[2], points[4]].max
    min_y = [points[1], points[3], points[5]].min
    max_y = [points[1], points[3], points[5]].max
    padding = size * ARROW_HITBOX_PADDING_RATIO
    side = [max_x - min_x, max_y - min_y].max + (padding * 2)
    half_side = side / 2.0

    point_x >= x - half_side && point_x <= x + half_side && point_y >= y - half_side && point_y <= y + half_side
  end
  private_class_method :is_point_in_arrow_hitbox

  def self.draw_arrow(direction, x, y, size, color)
    points = get_arrow_points(direction, x, y, size)
    return unless points

    Lota::Graphics.color = color
    Lota::Graphics.polygon(:fill, points)
  end

  def self.is_hovering_arrow(direction, x, y, size)
    mx, my = Lota::Mouse.position
    ScreenUtils.is_point_in_arrow(direction, x, y, size, mx, my)
  end

  def self.is_point_in_arrow(direction, x, y, size, point_x, point_y)
    points = get_arrow_points(direction, x, y, size)
    return false unless points

    is_point_in_arrow_hitbox(x, y, points, size, point_x, point_y)
  end

  def self.get_return_arrow_layout(text, y, width_percentage, size)
    scale = Text.calculate_scale_for_width(text, width_percentage)
    text_width = Text.get_text_width(text, scale)
    text_height = Text.get_text_height(scale)
    text_x = (Settings.window_width - text_width) / 2.0

    [text_x - (size * 2.5), y + (text_height / 2.0)]
  end
  private_class_method :get_return_arrow_layout

  def self.is_return_control_clicked(text, y, width_percentage, x, point_y)
    arrow_size = ScreenUtils.get_arrow_size
    arrow_x, arrow_y = get_return_arrow_layout(text, y, width_percentage, arrow_size)
    ScreenUtils.is_point_in_arrow("left", arrow_x, arrow_y, arrow_size, x, point_y)
  end

  def self.draw_return_control(text, y, width_percentage)
    arrow_size = ScreenUtils.get_arrow_size
    arrow_x, arrow_y = get_return_arrow_layout(text, y, width_percentage, arrow_size)
    Lota::Graphics.color = Colors.white
    Text.draw_centered_text(text, y, width_percentage)
    color = if ScreenUtils.is_hovering_arrow("left", arrow_x, arrow_y, arrow_size)
      Colors.neon_lime_splash
    else
      Colors.crimson
    end
    ScreenUtils.draw_arrow("left", arrow_x, arrow_y, arrow_size, color)
  end

  def self.get_return_prompt
    return "PRESS BACK OR TAP RED ARROW TO RETURN" if Settings.is_mobile

    "PRESS ESC OR CLICK RED ARROW TO RETURN"
  end

  def self.get_arrow_size
    12 * (Settings.window_height / 800.0)
  end

  def self.get_return_width_percentage
    Settings.is_mobile ? 0.65 : 0.6
  end
end
# SPDX-SnippetEnd
