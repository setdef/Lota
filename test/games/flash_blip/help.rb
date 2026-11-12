# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's help.lua
# (test/fixtures/flash_blip/game/help.lua, lines 1-211), by the rules of
# doc/contributors/design/translation.md: setColor and setScissor are the
# writers color= and scissor= (rules 5 and 6), setScissor() clears it with
# nil, love.mouse.isDown is Lota::Mouse.down? (rule 8), and the draw mode
# a symbol (rule 9). The module table is the module Help, its locals the
# module's instance variables, and its local functions private module
# methods. The functions nested in draw_help_screen_scrollable, which
# share its y_pos, are lambdas, and the icon functions it passes them are
# Powerups' and Debuffs' methods, called with call. Input's connected
# joysticks, a table keyed by joystick id, are a Hash, so Lua's next(t)
# ~= nil is its not being empty. Every division divides Floats, as Lua's
# do.

require "colors"
require "settings"
require "powerups"
require "debuffs"
require "text"
require "input"
require "gamestate"
require "screen_utils"

module Help
  @is_dragging = false
  @last_drag_y = nil

  def self.load
    @is_dragging = false
    @last_drag_y = nil
  end

  def self.draw_help_screen_static
    Lota::Graphics.color = [0, 0, 0, 0.9]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)
    Lota::Graphics.color = Colors.cyan
    Text.draw_centered_text("HOW TO PLAY", Settings.window_height * 0.03, 0.80)

    Lota::Graphics.color = Colors.spiced_amber
    Text.draw_centered_text("UP/DOWN TO SCROLL", Settings.window_height * 0.12, 0.3)

    return_text = ScreenUtils.get_return_prompt
    return_text_size = ScreenUtils.get_return_width_percentage
    return_y = Settings.window_height * 0.97
    ScreenUtils.draw_return_control(return_text, return_y, return_text_size)
    Text.draw_game_version
  end
  private_class_method :draw_help_screen_static

  def self.draw_help_screen_scrollable(scroll_y = nil)
    scroll_y ||= 0
    left_margin = Settings.window_width * 0.03
    start_y = Settings.window_height * 0.18
    y_pos = start_y - scroll_y

    connected_joysticks = Input.get_connected_joysticks
    has_controller = !connected_joysticks.empty?

    if Settings.is_mobile
      move_text = "TOUCH ON SCREEN:"
      move_scale = 0.55
      ping_text = "HOLD SCREEN OR DOUBLE TOUCH:"
      ping_scale = 0.85
    elsif has_controller
      move_text = "BUTTON 1:"
      move_scale = 0.3
      ping_text = "BUTTON 2:"
      ping_scale = 0.3
    else
      move_text = "LEFT CLICK OR SPACE:"
      move_scale = 0.6
      ping_text = "RIGHT CLICK OR C:"
      ping_scale = 0.5
    end

    draw_text = lambda do |text, x, width_pct, color = nil|
      Lota::Graphics.color = color || Colors.white
      scale = Text.calculate_scale_for_width(text, width_pct)
      Text.draw_text(text, x, y_pos, scale)
      height = Text.get_text_height(scale)
      y_pos = y_pos + height + (Settings.window_height * 0.015)
    end

    draw_section_header = lambda do |text, width_pct, color = nil|
      draw_text.call(text, left_margin, width_pct, color)
    end

    draw_section_detail = lambda do |text, width_pct, color = nil|
      draw_text.call(text, left_margin + (Settings.window_width * 0.02), width_pct, color)
    end

    draw_section_header.call(move_text, move_scale)
    draw_section_detail.call("MOVES PLAYER TO THE NEXT POINT", 0.8)
    y_pos += (Settings.window_height * 0.02)

    draw_section_header.call(ping_text, ping_scale)
    draw_section_detail.call("PINGS TO COLLECT POWERUPS NEARBY", 0.85)
    y_pos += (Settings.window_height * 0.02)

    text_icon_offset = Settings.window_width * 0.08

    draw_powerup_header = lambda do |draw_icon_func, r_factor, y_offset_factor, text, width_pct, color, has_line_width = nil, lw_multiplier = nil|
      scale = Text.calculate_scale_for_width(text, width_pct)
      text_height = Text.get_text_height(scale)
      base_radius = (text_height / 2.0) * 1.4
      radius = base_radius * (r_factor || 1)
      icon_x = left_margin + (Settings.window_width * 0.02)
      icon_y = y_pos + (text_height / 2.0) + (radius * (y_offset_factor || 0))

      Lota::Graphics.color = color
      if has_line_width
        line_width = [1, radius * 0.2].max * (lw_multiplier || 1)
        draw_icon_func.call(icon_x, icon_y, radius, 0, line_width)
      else
        draw_icon_func.call(icon_x, icon_y, radius, 0)
      end
      draw_text.call(text, left_margin + text_icon_offset, width_pct, color)
    end

    draw_powerup_header.call(Powerups.method(:draw_star), 1.0, 0, "STAR POWERUP:", 0.4, Colors.yellow)
    draw_section_detail.call("10 SECONDS OF INVULNERABILITY", 0.85, Colors.yellow)
    y_pos += (Settings.window_height * 0.02)

    draw_powerup_header.call(Powerups.method(:draw_clock), 1.0, 0, "HOURGLASS POWERUP:", 0.55,
      Colors.light_blue_glow)
    draw_section_detail.call("SHRINKS AND SLOWS OBSTACLES", 0.8, Colors.light_blue_glow)
    draw_section_detail.call("PREVENTS PLAYER FROM FALLING", 0.8, Colors.light_blue_glow)
    y_pos += (Settings.window_height * 0.02)

    draw_powerup_header.call(Powerups.method(:draw_phase_shift), 1.6, 0, "PHASE SHIFT POWERUP:", 0.6,
      Colors.emerald_shade, true, 1.2)
    draw_section_detail.call("RIGHT CLICK PING TELEPORTS", 0.8, Colors.emerald_shade)
    draw_section_detail.call("TO NEXT POINT. LASTS 10 SECONDS.", 0.8, Colors.emerald_shade)
    y_pos += (Settings.window_height * 0.02)

    draw_powerup_header.call(Powerups.method(:draw_bolt), 1.2, 0, "BOLT POWERUP:", 0.4, Colors.tangerine_blaze,
      true, 1.2)
    draw_section_detail.call("A SAFETY NET THAT TELEPORTS YOU", 0.8, Colors.tangerine_blaze)
    draw_section_detail.call("TO THE NEXT POINT. LASTS 30 SECS.", 0.8, Colors.tangerine_blaze)
    y_pos += (Settings.window_height * 0.02)

    draw_powerup_header.call(Powerups.method(:draw_score_multiplier), 1.0, 0, "SCORE MULTIPLIER:", 0.55,
      Colors.yellow)
    draw_section_detail.call("MULTIPLY YOUR SCORE BY 4X.", 0.8, Colors.yellow)
    draw_section_detail.call("LASTS 30 SECONDS.", 0.5, Colors.yellow)
    y_pos += (Settings.window_height * 0.02)

    draw_powerup_header.call(Powerups.method(:draw_spawn_rate_boost), 1.1, 0.4, "SPAWN RATE BOOST:", 0.55,
      Colors.neon_lime_splash)
    draw_section_detail.call("INCREASES POWERUP SPAWN RATE.", 0.8, Colors.neon_lime_splash)
    draw_section_detail.call("LASTS 30 SECONDS.", 0.5, Colors.neon_lime_splash)
    y_pos += (Settings.window_height * 0.02)

    draw_powerup_header.call(Debuffs.method(:draw_emp_fuse), 1.1, 0.20, "PING GLITCH DEBUFF:", 0.55, Colors.crimson,
      true, 1.2)
    draw_section_detail.call("REMOVES ACTIVE POWERUPS ON CONTACT.", 0.85, Colors.crimson)
    draw_section_detail.call("BLOCKS ALL PING ACTIONS FOR 10 SECS.", 0.85, Colors.crimson)
    y_pos += (Settings.window_height * 0.01)
    draw_section_detail.call("HINT: THE DEBUFF AND POWERUPS CANCEL EACH OTHER", 0.85, Colors.periwinkle_mist)
    draw_section_detail.call("PLAY CAREFULLY AND BLIP OVER POWERUPS TO CANCEL IT", 0.90, Colors.periwinkle_mist)

    y_pos + scroll_y - start_y
  end
  private_class_method :draw_help_screen_scrollable

  def self.draw
    draw_help_screen_static
    top_boundary = Settings.window_height * 0.15
    bottom_boundary = Settings.window_height * 0.95
    Lota::Graphics.scissor = [0, top_boundary, Settings.window_width, bottom_boundary - top_boundary]

    content_height = draw_help_screen_scrollable(Input.help_scroll_y)
    Lota::Graphics.scissor = nil

    view_height = bottom_boundary - top_boundary
    Input.max_help_scroll = [0, content_height - view_height + (Settings.window_height * 0.05)].max
  end

  def self.mousepressed(x, y, button)
    return true if button != 1

    return_text = ScreenUtils.get_return_prompt
    return_text_size = ScreenUtils.get_return_width_percentage
    return_y = Settings.window_height * 0.97
    if ScreenUtils.is_return_control_clicked(return_text, return_y, return_text_size, x, y)
      GameState.set(GameState.previous || "attract")
      return true
    end

    if !Settings.is_mobile && y >= Settings.window_height * 0.15 && y < Settings.window_height * 0.88
      @is_dragging = true
      @last_drag_y = y
    end

    true
  end

  def self.mousemoved(_x, y)
    unless Lota::Mouse.down?(1)
      @is_dragging = false
      @last_drag_y = nil
      return
    end

    return if !@is_dragging || !@last_drag_y

    Input.help_scroll_y = Input.help_scroll_y + @last_drag_y - y
    Input.help_scroll_y = Input.help_scroll_y.clamp(0, Input.max_help_scroll)
    @last_drag_y = y
  end

  def self.mousereleased(_x, _y, button)
    return unless button == 1

    @is_dragging = false
    @last_drag_y = nil
  end
end
# SPDX-SnippetEnd
