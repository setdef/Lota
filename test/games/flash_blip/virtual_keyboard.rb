# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's virtual_keyboard.lua
# (test/fixtures/flash_blip/game/virtual_keyboard.lua, lines 1-299), by the
# rules of doc/contributors/design/translation.md: setColor is the writer
# color= (rules 5 and 6), love.mouse.getPosition is Lota::Mouse.position,
# an Array (rules 3 and 4), and the draw modes and the keys are symbols
# (rule 9). The module's locals are its instance variables, and a key on
# the screen, a table with fixed fields, is a Key.
#
# A key arrives as a Symbol, so where Lua measures and upper-cases the
# key's name the code does so to key.to_s. Lua counts and cuts a string by
# bytes, and its upper, %a, and %w know only ASCII, as String#bytesize,
# byteslice, upcase(:ascii), and the ASCII classes here do. A callback is
# anything that answers call; a proc, like a Lua function, ignores the
# arguments it does not name.

require "colors"
require "settings"
require "text"
require "sound"
require "lua"

module VirtualKeyboard
  Key = Struct.new(:char, :x, :y, :w, :h, :action, :color, keyword_init: true)

  @name = ""
  @max_name_length = 15
  @score = 0
  @source = ""
  @on_accept_callback = nil
  @on_cancel_callback = nil

  @keys = []
  @cursor_timer = 0
  @cursor_visible = true

  def self.layout
    @keys = []
    col_width = Settings.window_width / 10.6
    padding = col_width * 0.12
    key_w = col_width - padding
    key_h = col_width * 1.25

    start_y = Settings.window_height * 0.42
    row_spacing = col_width * 1.40

    row0 = %w[1 2 3 4 5 6 7 8 9 0]
    r0_offset = (Settings.window_width - ((10 * col_width) - padding)) / 2.0
    row0.each_with_index do |char, index|
      i = index + 1
      x = r0_offset + ((i - 1) * col_width)
      y = start_y
      @keys << Key.new(char:, x:, y:, w: key_w, h: key_h, action: char)
    end

    row1 = %w[Q W E R T Y U I O P]
    r1_offset = (Settings.window_width - ((10 * col_width) - padding)) / 2.0
    row1.each_with_index do |char, index|
      i = index + 1
      x = r1_offset + ((i - 1) * col_width)
      y = start_y + row_spacing
      @keys << Key.new(char:, x:, y:, w: key_w, h: key_h, action: char)
    end

    row2 = %w[A S D F G H J K L]
    r2_offset = (Settings.window_width - ((9 * col_width) - padding)) / 2.0
    row2.each_with_index do |char, index|
      i = index + 1
      x = r2_offset + ((i - 1) * col_width)
      y = start_y + (2 * row_spacing)
      @keys << Key.new(char:, x:, y:, w: key_w, h: key_h, action: char)
    end

    row3 = %w[Z X C V B N M]
    r3_offset = (Settings.window_width - ((7 * col_width) - padding)) / 2.0
    row3.each_with_index do |char, index|
      i = index + 1
      x = r3_offset + ((i - 1) * col_width)
      y = start_y + (3 * row_spacing)
      @keys << Key.new(char:, x:, y:, w: key_w, h: key_h, action: char)
    end

    # Row 4: CANCEL (ESC), DEL, SPACE, OK
    r4_offset = r1_offset
    y = start_y + (4 * row_spacing)

    @keys << Key.new(
      char: "ESC",
      x: r4_offset,
      y:,
      w: (2 * col_width) - padding,
      h: key_h,
      action: "cancel",
      color: Colors.crimson
    )

    @keys << Key.new(
      char: "DEL",
      x: r4_offset + (2 * col_width),
      y:,
      w: (2 * col_width) - padding,
      h: key_h,
      action: "backspace",
      color: Colors.safety_orange
    )

    @keys << Key.new(
      char: "SPACE",
      x: r4_offset + (4 * col_width),
      y:,
      w: (3.5 * col_width) - padding,
      h: key_h,
      action: "space",
      color: Colors.periwinkle_mist
    )

    @keys << Key.new(
      char: "OK",
      x: r4_offset + (7.5 * col_width),
      y:,
      w: (2.5 * col_width) - padding,
      h: key_h,
      action: "accept",
      color: Colors.neon_lime_splash
    )
  end

  def self.show(score_val, source_val, on_accept, on_cancel)
    @name = ""
    @score = score_val || 0
    @source = source_val || ""
    @on_accept_callback = on_accept
    @on_cancel_callback = on_cancel
    @cursor_timer = 0
    @cursor_visible = true
    layout
  end

  def self.update(dt)
    @cursor_timer += dt
    return unless @cursor_timer > 0.4

    @cursor_visible = !@cursor_visible
    @cursor_timer = 0
  end

  def self.draw
    Lota::Graphics.color = 0, 0, 0, 0.85
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.window_width, Settings.window_height)

    # Draw Titles
    Lota::Graphics.color = Colors.yellow
    Text.draw_centered_text("GOBAL HI SCORE!", Settings.window_height * 0.08, 0.9)

    # Draw score details
    Lota::Graphics.color = Colors.neon_lime_splash
    score_str = "#{Lua.tostring(@score.floor)} PTS (#{Lua.tostring(@source)})"
    Text.draw_centered_text(score_str, Settings.window_height * 0.16, 0.85)

    # Prompt
    Lota::Graphics.color = Colors.white
    Text.draw_centered_text("ENTER YOUR NAME:", Settings.window_height * 0.24, 0.8)

    # Draw name input box
    box_w = Settings.window_width * 0.85
    box_h = Settings.window_height * 0.08
    box_x = (Settings.window_width - box_w) / 2.0
    box_y = Settings.window_height * 0.32

    Lota::Graphics.color = Colors.cyan_glow
    Lota::Graphics.rectangle(:line, box_x, box_y, box_w, box_h, 6, 6)

    # Draw text with a cursor
    stable_text = @name
    stable_text = "#{@name}█" if @name.bytesize < @max_name_length

    Lota::Graphics.color = Colors.white
    text_scale = Text.calculate_scale_for_width(stable_text, 0.75)
    max_scale = Settings.window_height * 0.004
    text_scale = [text_scale, max_scale].min

    text_w = Text.get_text_width(stable_text, text_scale)
    text_h = Text.get_text_height(text_scale)
    text_x = box_x + ((box_w - text_w) / 2.0)
    text_y = box_y + ((box_h - text_h) / 2.0)

    # Draw the actual typed name
    Text.draw_text(@name, text_x, text_y, text_scale)

    # Draw the blinking block cursor immediately following the typed name
    if @cursor_visible && @name.bytesize < @max_name_length
      name_w = Text.get_text_width(@name, text_scale)
      Text.draw_text("█", text_x + name_w, text_y, text_scale)
    end

    # Draw keyboard keys
    mouse_x, mouse_y = Lota::Mouse.position
    @keys.each do |key|
      is_hovered = mouse_x >= key.x && mouse_x <= key.x + key.w && mouse_y >= key.y && mouse_y <= key.y + key.h

      # Draw key background
      Lota::Graphics.color = if is_hovered
        [0.2, 0.2, 0.3, 0.9]
      else
        [0.08, 0.08, 0.12, 0.85]
      end
      Lota::Graphics.rectangle(:fill, key.x, key.y, key.w, key.h, 4, 4)

      # Draw key border
      border_color = key.color || Colors.cyan
      Lota::Graphics.color = if is_hovered
        [1, 1, 1, 1]
      else
        [border_color[0], border_color[1], border_color[2], 0.6]
      end
      Lota::Graphics.rectangle(:line, key.x, key.y, key.w, key.h, 4, 4)

      # Draw key label
      Lota::Graphics.color = if is_hovered
        [1, 1, 1, 1]
      else
        [border_color[0], border_color[1], border_color[2], 1]
      end

      scale_pct = 0.075
      max_scale_mult = 0.65
      if key.char.match?(/\A[A-Za-z]\z/)
        scale_pct = 0.09
        max_scale_mult = 0.75
      elsif key.char == "SPACE"
        scale_pct = 0.12
      end

      label_scale = Text.calculate_scale_for_width(key.char, scale_pct)
      max_label_scale = key.w.fdiv(Text.get_text_width(key.char, 1)) * max_scale_mult
      label_scale = [label_scale, max_label_scale].min

      label_width = Text.get_text_width(key.char, label_scale)
      label_height = Text.get_text_height(label_scale)
      label_x = key.x + ((key.w - label_width) / 2.0)
      label_y = key.y + ((key.h - label_height) / 2.0)

      Text.draw_text(key.char, label_x, label_y, label_scale)
    end
  end

  def self.handle_action(action)
    case action
    when "cancel"
      if @on_cancel_callback
        Sound.play("explosion")
        # Avoid duplicate submission triggers while asynchronous requests are in flight
        callback = @on_cancel_callback
        @on_cancel_callback = nil
        @on_accept_callback = nil
        callback.call
      end
    when "backspace"
      if @name.bytesize.positive?
        Sound.play("blip")
        @name = @name.byteslice(0, @name.bytesize - 1)
      end
    when "space"
      if @name.bytesize < @max_name_length
        Sound.play("blip")
        @name = "#{@name} "
      end
    when "accept"
      # validation is strictly ASCII alphanumeric (%w) and spaces (%s)
      clean_name = @name.gsub(/\s+/, "")
      if clean_name.bytesize.zero? || !@name.match?(/\A[A-Za-z0-9\s]+\z/)
        @name = ""
        Sound.play("explosion")
      else
        Sound.play("teleport")
        if @on_accept_callback
          callback = @on_accept_callback
          @on_accept_callback = nil
          @on_cancel_callback = nil
          callback.call(@name)
        end
      end
    else
      if @name.bytesize < @max_name_length
        Sound.play("blip")
        @name += action
      end
    end
  end

  def self.keypressed(key)
    case key
    when :escape
      handle_action("cancel")
    when :backspace
      handle_action("backspace")
    when :return
      handle_action("accept")
    when :space
      handle_action("space")
    else
      if key.to_s.bytesize == 1
        char = key.to_s.upcase(:ascii)
        handle_action(char) if char.match?(/[A-Za-z0-9]/)
      end
    end
  end

  def self.mousepressed(x, y, button)
    return if button != 1

    @keys.each do |key|
      if x >= key.x && x <= key.x + key.w && y >= key.y && y <= key.y + key.h
        handle_action(key.action)
        break
      end
    end
  end
end
# SPDX-SnippetEnd
