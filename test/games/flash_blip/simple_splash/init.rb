# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's simple_splash/init.lua
# (test/fixtures/flash_blip/game/simple_splash/init.lua, lines 1-79), by
# the rules of doc/contributors/design/translation.md: love.data.decode
# becomes Lota::Data.decode, with its container and format symbols (rule 9);
# love.image.newImageData and love.graphics.newImage become the
# constructors Lota::Image::ImageData.new and Lota::Graphics::Image.new
# (rule 2); getWidth and getHeight become width and height (rules 3 and
# 13); setColor becomes the writer Lota::Graphics.color= (rules 5 and 6).
#
# SimpleSplash.new makes a table and copies SimpleSplash's functions into
# it as its draw, update, and set_done, so the splash is an object whose
# methods those are: here the class SimpleSplash, whose instances answer
# draw, update, and set_done, and whose fields read and write as Lua's do.
# The flag, a field of the SimpleSplash table, is the class's reader
# cuban_flag. on_done, a function main.lua stores, is anything that
# answers call. Lua's string.sub and # count bytes, so the loading text is
# cut with byteslice and measured with bytesize. Lua numbers are all
# doubles, so where Lua divides, Ruby divides as Floats.
#
# love.graphics.clear is given the background color as a table, which
# LÖVE's clear takes (wrap_Graphics.cpp, w_clear), and here it is given the
# Array, as the rules translate a table of a color, though
# Lota::Graphics.clear does not take one yet.

require "text"
require "colors"

class SimpleSplash
  class << self
    attr_reader :cuban_flag
  end

  @cuban_flag = "iVBORw0KGgoAAAANSUhEUgAAAKoAAACWBAMAAAC84A5nAAAAAXNSR0IArs4c6QAAAARnQU1BAACx" \
    "jwv8YQUAAAASUExURUdwTAAAAPz8/gAAgIAAAAICgacQmYMAAAABdFJOUwBA5thmAAAAl0lEQVRo" \
    "3u3ayw2EIABAQVuwBVugBVvY/lvZyGGJRIiymPiZd4IQ5kbgwDBIknTzxnWHVqlUahmcf4WltDmO" \
    "wro9NJX6ajWB01Ki4zSuTqXKNJVK3dqX0VQqteeJjX2qtaqhGpX6DHXrpfk/SKVSi2e34Q6kUql1" \
    "uidIpVIzuvX6o1Kpe+lOIJVKzehzfoBQqa9WJUm6QF+hUqlzAImF5QAAAABJRU5ErkJggg=="

  attr_accessor :width, :height, :background, :done, :alpha, :flag_image, :loading_text, :loading_index,
    :loading_timer, :loading_delay, :on_done

  def initialize(width, height)
    self.width = width
    self.height = height
    self.background = Colors.murky_blue
    self.done = false
    self.alpha = 1
    decoded = Lota::Data.decode(:data, :base64, SimpleSplash.cuban_flag)
    image_data = Lota::Image::ImageData.new(decoded)
    self.flag_image = Lota::Graphics::Image.new(image_data)

    self.loading_text = "LOADING..."
    self.loading_index = 1
    self.loading_timer = 0
    self.loading_delay = 0.2
  end

  def draw
    width = self.width
    height = self.height

    Lota::Graphics.clear(background)

    Lota::Graphics.color = [1, 1, 1, alpha]
    image_width = flag_image.width
    image_height = flag_image.height
    scale = [width.fdiv(image_width), height.fdiv(image_height)].min * 0.5
    x = (width - (image_width * scale)) / 2.0
    y = (height - (image_height * scale)) / 2.0
    Lota::Graphics.draw(flag_image, x, y, 0, scale, scale)

    image_bottom = y + (image_height * scale)
    text_y = image_bottom + (height * 0.01)
    Text.draw_centered_text("Made with LOVE2D", text_y, 0.8)
    Text.draw_centered_text("by plinkr", text_y + (height * 0.05), 0.4)

    loading_display = loading_text.byteslice(0, loading_index)
    Text.draw_centered_text(loading_display, text_y + (height * 0.20), 0.4, 2, 2)
  end

  def update(dt)
    self.loading_timer = loading_timer + dt
    return unless loading_timer >= loading_delay

    self.loading_timer = 0
    self.loading_index = loading_index + 1
    self.loading_index = 1 if loading_index > loading_text.bytesize
  end

  def set_done
    return if done

    self.done = true
    on_done&.call
  end
end
# SPDX-SnippetEnd
