# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's options.lua
# (test/fixtures/flash_blip/game/options.lua, lines 1-275), by the rules of
# doc/contributors/design/translation.md: setColor is the writer color=
# (rules 5 and 6), and the draw mode and keys symbols (rule 9). The module
# table is the module Options, its locals the module's instance variables,
# and its local functions private module methods. A menu item, a table of
# text and setting, is a MenuItem; the tables built only for scaling, read
# with .text, are ScalingItems; and an item's click bounds a Bounds, with
# every field Lua gives one. Lua reads a setting by its name upper-cased,
# Settings[item.setting:upper()], and Settings' fields are its methods
# named in lower case, so that is Settings.public_send(item.setting).
# math.max(0, math.min(1, v)) clamps with Float bounds, as Lua's doubles
# do, and every division divides Floats.

require "lua"
require "colors"
require "settings"
require "text"
require "sound"
require "music"
require "gamestate"
require "glow_benchmark"
require "screen_utils"

module Options
  MenuItem = Struct.new(:text, :setting, keyword_init: true)
  ScalingItem = Struct.new(:text, keyword_init: true)
  Bounds = Struct.new(:x, :y, :width, :height, :line1_height, :x2, :w2, :is_double, keyword_init: true)

  @menu_items = [
    MenuItem.new(text: "MUSIC", setting: "is_music_volume"),
    MenuItem.new(text: "SFX", setting: "is_sfx_volume"),
    MenuItem.new(text: "GLOW", setting: "is_glow_enabled"),
    MenuItem.new(text: "BLUR", setting: "is_blur_enabled"),
  ]

  @selected_item = 1
  @bounds = []
  Settings.is_music_volume ||= 1.0
  Settings.is_sfx_volume ||= 1.0

  def self.toggle_setting(setting)
    case setting
    when "is_music_volume"
      Settings.is_music_enabled = !Settings.is_music_enabled
      Music.toggle_mute(!Settings.is_music_enabled)
      Settings.save_debounced
    when "is_sfx_volume"
      Settings.is_sfx_enabled = !Settings.is_sfx_enabled
      Sound.toggle_mute(!Settings.is_sfx_enabled)
      Settings.save_debounced
    when "is_glow_enabled"
      Settings.is_glow_enabled = !Settings.is_glow_enabled
      Main.apply_glow_setting
      if Settings.is_glow_enabled && (Settings.is_mobile || Settings.is_web)
        if Settings.has_passed_glow_test
          GlowBenchmark.stop
          Settings.save_debounced
        else
          GlowBenchmark.start
        end
      else
        GlowBenchmark.stop
        Settings.save_debounced
      end
    when "is_blur_enabled"
      Settings.is_blur_enabled = !Settings.is_blur_enabled
      Main.apply_blur_setting
      Settings.save_debounced
    end
  end
  private_class_method :toggle_setting

  # Change volume BGM and SE separately
  def self.change_volume(setting, delta)
    case setting
    when "is_music_volume"
      Settings.is_music_volume = (Settings.is_music_volume + delta).clamp(0.0, 1.0)
      Music.set_volume(Settings.is_music_volume)
      Settings.save_debounced
    when "is_sfx_volume"
      Settings.is_sfx_volume = (Settings.is_sfx_volume + delta).clamp(0.0, 1.0)
      Sound.set_volume(Settings.is_sfx_volume)
      Settings.save_debounced
    end
  end
  private_class_method :change_volume

  def self.volume_bar(percent)
    total_slots = 5
    percent = Lua.tonumber(percent) || 0
    percent = percent.clamp(0, 100)

    filled = percent.fdiv(20).floor
    filled = filled.clamp(0, total_slots)

    empty = total_slots - filled

    "- #{'█' * filled}#{'░' * empty} +"
  end
  private_class_method :volume_bar

  def self.load
    @selected_item = 1
  end

  def self.update(_dt); end

  def self.draw
    Lota::Graphics.color = [0, 0, 0, 0.85]
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)

    Lota::Graphics.color = Colors.cyan
    Text.draw_centered_text("OPTIONS", Settings.window_height * 0.1, 0.7)

    y_start = Settings.window_height * 0.35
    width_percentage = 0.65

    # Create a list of potential menu item texts to calculate a uniform scale
    items_for_scaling = []
    @menu_items.each do |item|
      # Use the longest possible text for stable scaling
      if item.setting == "is_music_volume" || item.setting == "is_sfx_volume"
        volume = Settings.public_send(item.setting) || 0
        percent = (volume * 100).floor
        items_for_scaling << ScalingItem.new(text: "[✓] #{item.text}")
        items_for_scaling << ScalingItem.new(text: "      #{volume_bar(percent)}")
      else
        items_for_scaling << ScalingItem.new(text: "[✓] #{item.text}")
      end
    end

    uniform_scale = Text.calculate_uniform_scale(items_for_scaling, width_percentage)

    # Calculate common X to align all checkboxes to the left within a centered block
    max_w = 0
    items_for_scaling.each do |item|
      max_w = [max_w, Text.get_text_width(item.text, uniform_scale)].max
    end
    common_x = (Settings.window_width - max_w) / 2.0

    text_height = Text.get_text_height(uniform_scale)
    current_y = y_start

    @menu_items.each_with_index do |item, index|
      i = index + 1
      is_selected = (i == @selected_item)

      is_on = case item.setting
      when "is_music_volume"
        Settings.is_music_enabled
      when "is_sfx_volume"
        Settings.is_sfx_enabled
      else
        Settings.public_send(item.setting)
      end

      color = if !Settings.is_mobile && is_selected
        Colors.cyan
      else
        is_on ? Colors.neon_lime_splash : Colors.naranja_rojo
      end
      Lota::Graphics.color = color

      if item.setting == "is_music_volume" || item.setting == "is_sfx_volume"
        volume = Settings.public_send(item.setting) || 0
        percent = (volume * 100).floor
        checkbox = is_on ? "[✓]" : "[✗]"

        line1 = "#{checkbox} #{item.text}"
        line2 = "      #{volume_bar(percent)}"

        Text.draw_text(line1, common_x, current_y, uniform_scale)

        y2 = current_y + text_height + 15
        Text.draw_text(line2, common_x, y2, uniform_scale)

        w2 = Text.get_text_width(line2, uniform_scale)
        @bounds[index] = Bounds.new(
          x: common_x,
          y: current_y,
          width: max_w + 50,
          height: (y2 + text_height) - current_y,
          line1_height: text_height + 10,
          x2: common_x,
          w2:,
          is_double: true,
        )
        current_y += (y2 + text_height - current_y) + 30
      else
        checkbox = is_on ? "[✓]" : "[✗]"
        text = "#{checkbox} #{item.text}"
        Text.draw_text(text, common_x, current_y, uniform_scale)

        @bounds[index] = Bounds.new(x: common_x, y: current_y, width: max_w, height: text_height)
        current_y = current_y + text_height + 40
      end
    end

    status_y = current_y + 10
    if GlowBenchmark.is_testing
      test_msg = "TESTING GLOW PERFORMANCE..."
      Lota::Graphics.color = Colors.cyan
      Text.draw_centered_text(test_msg, status_y, 0.6)
    elsif GlowBenchmark.get_notice_timer.positive?
      notice_msg = GlowBenchmark.get_notice
      notice_color = notice_msg.include?("DISABLED") ? Colors.crimson : Colors.neon_lime_splash
      Lota::Graphics.color = notice_color
      Text.draw_centered_text(notice_msg, status_y, 0.6)
    end

    return_text = ScreenUtils.get_return_prompt

    return_y = Settings.window_height * 0.92
    ScreenUtils.draw_return_control(return_text, return_y, 0.7)
  end

  def self.keypressed(key)
    setting = @menu_items[@selected_item - 1].setting

    case key
    when :up
      @selected_item = [1, @selected_item - 1].max
      Sound.play("blip")
    when :down
      @selected_item = [@menu_items.size, @selected_item + 1].min
      Sound.play("blip")
    when :"kp-", :-, :left
      if @menu_items[@selected_item - 1].setting == "is_music_volume" ||
          @menu_items[@selected_item - 1].setting == "is_sfx_volume"

        change_volume(setting, -0.2)
      else
        toggle_setting(setting)
      end
      Sound.play("blip")
    when :"kp+", :+, :right
      if @menu_items[@selected_item - 1].setting == "is_music_volume" ||
          @menu_items[@selected_item - 1].setting == "is_sfx_volume"

        change_volume(setting, 0.2)
      else
        toggle_setting(setting)
      end
      Sound.play("blip")
    when :return, :space
      toggle_setting(setting)
      Sound.play("blip")
    end
  end

  def self.mousepressed(x, y, button)
    return true if button != 1

    return_text = ScreenUtils.get_return_prompt
    return_y = Settings.window_height * 0.92
    return_width_percentage = 0.7
    if ScreenUtils.is_return_control_clicked(return_text, return_y, return_width_percentage, x, y)
      GameState.set(GameState.previous || "attract")
      Sound.play("blip")
      return true
    end

    @bounds.each_with_index do |item_bounds, index|
      next unless x > item_bounds.x &&
        x < item_bounds.x + item_bounds.width &&
        y > item_bounds.y &&
        y < item_bounds.y + item_bounds.height

      @selected_item = index + 1
      setting = @menu_items[index].setting

      if item_bounds.is_double
        if y < item_bounds.y + item_bounds.line1_height
          toggle_setting(setting)
        else
          # Split the volume bar area in two for decrease/increase
          bar_center_x = item_bounds.x2 + (item_bounds.w2 / 2.0)
          if x < bar_center_x
            change_volume(setting, -0.2)
          else
            change_volume(setting, 0.2)
          end
        end
      else
        toggle_setting(setting)
      end
      Sound.play("blip")
      return true
    end

    true
  end
end
# SPDX-SnippetEnd
