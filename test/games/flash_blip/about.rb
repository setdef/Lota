# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's about.lua
# (test/fixtures/flash_blip/game/about.lua, lines 1-101), by the rules of
# doc/contributors/design/translation.md: setColor is the writer color=
# (rules 5 and 6), love.system.openURL is Lota::System.open_url (rules 13
# and 36), and the draw mode a symbol (rule 9). The module table is the
# module About, and its local functions private module methods. A link, a
# table of text, url, y_percentage, width_percentage, and the bounds
# update_link_bounds gives it, is a LinkItem, and its bounds a Bounds.
# Every division divides Floats, as Lua's do.

require "colors"
require "settings"
require "text"
require "gamestate"
require "screen_utils"

module About
  LinkItem = Struct.new(:text, :url, :y_percentage, :width_percentage, :bounds, keyword_init: true)
  Bounds = Struct.new(:x, :y, :width, :height, keyword_init: true)

  RETURN_Y_PERCENTAGE = 0.9
  RETURN_WIDTH_PERCENTAGE = 0.6

  @link_items = [
    LinkItem.new(
      text: "LICENSED UNDER MIT",
      url: "https://github.com/plinkr/flash-blip?tab=MIT-1-ov-file",
      y_percentage: 0.5,
      width_percentage: 0.8,
    ),
    LinkItem.new(
      text: "https://github.com/plinkr/flash-blip",
      url: "https://github.com/plinkr/flash-blip",
      y_percentage: 0.75,
      width_percentage: 0.95,
    ),
  ]

  def self.update_link_bounds
    @link_items.each do |item|
      scale = Text.calculate_scale_for_width(item.text, item.width_percentage)
      width = Text.get_text_width(item.text, scale)
      item.bounds = Bounds.new(
        x: (Settings.window_width - width) / 2.0,
        y: Settings.window_height * item.y_percentage,
        width:,
        height: Text.get_text_height(scale),
      )
    end
  end
  private_class_method :update_link_bounds

  def self.is_point_in_bounds(x, y, bounds)
    x > bounds.x && x < bounds.x + bounds.width && y > bounds.y && y < bounds.y + bounds.height
  end
  private_class_method :is_point_in_bounds

  def self.load; end

  def self.update(_dt); end

  def self.draw
    update_link_bounds

    Lota::Graphics.color = [0, 0, 0, 0.8]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)

    Lota::Graphics.color = Colors.cyan
    Text.draw_centered_text("ABOUT", Settings.window_height * 0.1, 0.45)

    Lota::Graphics.color = Colors.neon_lime_splash
    description1 = "A FAST-PACED, RETRO-STYLE ARCADE"
    description2 = "VERTICAL SCROLLER IN LOVE2D"
    description3 = "SURVIVE AND AIM FOR THE HIGH SCORE!"
    Text.draw_centered_text(description1, Settings.window_height * 0.24, 0.95)
    Text.draw_centered_text(description2, Settings.window_height * 0.27, 0.80)
    Text.draw_centered_text(description3, Settings.window_height * 0.30, 0.96)

    @link_items.each do |item|
      Text.draw_centered_text(item.text, item.bounds.y, item.width_percentage)
    end

    line_kenta_cho = "INSPIRED BY THE WORK OF KENTA CHO"
    Text.draw_centered_text(line_kenta_cho, Settings.window_height * 0.70, 0.9)

    Text.draw_game_version

    return_text = ScreenUtils.get_return_prompt
    return_y = Settings.window_height * RETURN_Y_PERCENTAGE
    ScreenUtils.draw_return_control(return_text, return_y, RETURN_WIDTH_PERCENTAGE)
  end

  def self.keypressed(_key); end

  def self.mousepressed(x, y, button)
    if button == 1
      update_link_bounds

      return_text = ScreenUtils.get_return_prompt
      return_y = Settings.window_height * RETURN_Y_PERCENTAGE
      if ScreenUtils.is_return_control_clicked(return_text, return_y, RETURN_WIDTH_PERCENTAGE, x, y)
        GameState.set(GameState.previous || "attract")
        return true
      end

      @link_items.each do |item|
        if is_point_in_bounds(x, y, item.bounds)
          Lota::System.open_url(item.url)
          return true
        end
      end
    end
    true
  end
end
# SPDX-SnippetEnd
