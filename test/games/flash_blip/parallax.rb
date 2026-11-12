# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's parallax.lua
# (test/fixtures/flash_blip/game/parallax.lua, lines 1-111), by the rules of
# doc/contributors/design/translation.md: getWidth and getHeight become
# width and height (rule 3), setColor and setBackgroundColor writers (rules
# 5 and 6), and "fill" a symbol (rule 9). The module's Lua locals are its
# instance variables, its layers objects of a class, and its stars Structs. Lua defines
# get_random_color twice: the first, which draws a name from the colors
# map, colors the first star_colors when the module loads, so it stays a
# draw at load time here, as first_random_color; the second, which the
# rest of the module calls, is random_color. That second one calls itself
# with the colors map when the star colors are empty, and Lua's # of a map
# with no array part is 0, so it recurses until the stack overflows, as it
# does here. The draw passes each star's color three times to setColor,
# which reads only the first table, so it sets the color from the one
# Array. Settings.IS_MOBILE and DPI_SCALE are Settings.is_mobile and
# dpi_scale.

require "colors"
require "settings"

module Parallax
  # One layer of stars, all moving at its speed and drawn at its size: a
  # class, not a Struct, as a Struct's size is its member count.
  class Layer
    attr_accessor :stars, :speed, :size

    def initialize(stars:, speed:, size:)
      @stars = stars
      @speed = speed
      @size = size
    end
  end

  # One star of a layer.
  Star = Struct.new(:x, :y, :color, keyword_init: true)

  COLORS = {
    periwinkle_mist: Colors.periwinkle_mist,
    skyline_azure: Colors.skyline_azure,
    royal_sapphire: Colors.royal_sapphire,
    midnight_harbor: Colors.midnight_harbor,
  }.freeze

  # Lua collects these names with pairs, whose order picks the color of the
  # first star_colors at load. LuaJIT's order changes from run to run, and
  # the parity harness makes pairs visit keys in sorted order
  # (test/parity/lua/conf.lua, sorted_pairs), so the names are sorted.
  COLOR_NAMES = COLORS.keys.sort.freeze

  def self.first_random_color
    random_index = Lota::Math.random(COLOR_NAMES.size)
    random_name = COLOR_NAMES[random_index - 1]
    COLORS[random_name]
  end
  private_class_method :first_random_color

  @layers = []
  @num_layers = 4
  @paused = false
  @background_color = Colors.dark_blue
  @star_colors = [first_random_color]

  def self.set_colors(bg, stars)
    @background_color = bg
    @star_colors = stars
  end

  def self.random_color(colors_table = nil)
    colors_to_use = colors_table || @star_colors
    # Lua's # of the colors map is 0, as it has no array part.
    return random_color(COLORS) if colors_to_use.is_a?(Hash) || colors_to_use.empty?

    colors_to_use[Lota::Math.random(colors_to_use.size) - 1]
  end
  private_class_method :random_color

  def self.pause
    @paused = true
  end

  def self.resume
    @paused = false
  end

  def self.load(bg_color = nil, stars = nil)
    Parallax.set_colors(bg_color, stars) if bg_color && stars
    @layers = []
    (1..@num_layers).each do |i|
      stars_in_layer = Lota::Math.random(50, 100)
      # Calculate base size and apply DPI scaling compensation for mobile
      base_size = 1 + (i.fdiv(@num_layers) * 3)
      mobile_scale_compensation = Settings.is_mobile ? (1.0 / [1, Settings.dpi_scale * 3].max) : 1
      final_size = base_size * mobile_scale_compensation

      layer = Layer.new(
        stars: [],
        # Deeper layers move slower, closer layers are faster
        speed: (i * 15) + 5,
        # Closer layers have bigger stars, scaled appropriately for mobile
        size: final_size,
      )
      @layers[i - 1] = layer
      stars_in_layer.times do
        layer.stars << Star.new(
          x: Lota::Math.random(Lota::Graphics.width),
          y: Lota::Math.random(Lota::Graphics.height),
          # Use different colors for different layers to enhance depth
          color: random_color,
        )
      end
    end
  end

  def self.update(dt, game_state = nil)
    return if @paused || game_state == "gameOver" || game_state == "levelCompleted" || game_state == "help"

    @layers.each do |layer|
      layer.stars.each do |star|
        star.y += layer.speed * dt
        if star.y > Lota::Graphics.height
          star.y = 0
          star.x = Lota::Math.random(Lota::Graphics.width)
        end
      end
    end
  end

  def self.draw
    Lota::Graphics.background_color = @background_color
    @layers.each do |layer|
      layer.stars.each do |star|
        next unless star.color

        # Lua passes star.color three times; setColor reads only the first table.
        Lota::Graphics.color = star.color
        # Using rectangles for square pixels, with variable size
        Lota::Graphics.rectangle(:fill, star.x, star.y, layer.size, layer.size)
      end
    end
    # Reset color to white after drawing the parallax background
    Lota::Graphics.color = 1, 1, 1
  end
end
# SPDX-SnippetEnd
