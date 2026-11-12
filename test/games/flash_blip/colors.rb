# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's colors.lua
# (test/fixtures/flash_blip/game/colors.lua, lines 1-59). The Colors table
# becomes the module Colors, and each color, a field of it, a reader of the
# same name returning an Array, which Lota::Graphics.color= takes as
# setColor takes a table (rules 5 and 6), so Colors.yellow[1] in Lua is
# Colors.yellow[0] here. Lua numbers are all doubles, so the whole numbers
# among the components are written as Floats. Colors.lerp reads a missing
# fourth component as 1, as Lua's "or 1" reads a missing field.

# Color palette (values from 0 to 1).
module Colors
  class << self
    attr_reader :cyan, :safety_orange, :sea_of_tears, :periwinkle_mist, :green_blob,
      :green_blob_transparent, :naranja_rojo, :naranja_rojo_transparent, :white, :black, :red,
      :crimson, :green, :yellow, :neon_lime_splash, :skyline_azure, :royal_sapphire,
      :midnight_harbor, :light_blue, :apricot_glow, :tangerine_blaze, :spiced_amber, :rusty_cedar,
      :rusty_cedar_transparent, :cyan_glow, :light_blue_glow, :emerald_shade, :gunmetal_gray,
      :spring_green, :charcoal_black, :antique_gold, :dark_blue, :almost_black, :almost_dark_blue,
      :dark_reddish_black, :dark_bluish_black, :deep_midnight_blue, :subtle_violet, :faint_crimson,
      :shadow_green, :inky_blue, :charcoal_blue, :deep_plum, :murky_teal, :murky_blue
  end

  @cyan = [0.0, 1.0, 1.0]
  @safety_orange = [1.0, 0.392, 0.0]
  @sea_of_tears = [0.059, 0.302, 0.659]
  @periwinkle_mist = [0.333, 0.498, 0.745]
  @green_blob = [0.204, 0.847, 0.0]
  @green_blob_transparent = [0.204, 0.847, 0.0, 0.4]
  @naranja_rojo = [1.0, 0.25, 0.0]
  @naranja_rojo_transparent = [1.0, 0.25, 0.0, 0.8]
  @white = [1.0, 1.0, 1.0]
  @black = [0.0, 0.0, 0.0]
  @red = [1.0, 0.0, 0.0]
  @crimson = [0.8, 0.1, 0.1]
  @green = [0.0, 1.0, 0.0]
  @yellow = [1.0, 1.0, 0.0]
  @neon_lime_splash = [0.478, 0.886, 0.345]
  @skyline_azure = [0.2, 0.396, 0.682]
  @royal_sapphire = [0.043, 0.231, 0.51]
  @midnight_harbor = [0.027, 0.176, 0.4]
  @light_blue = [0.678, 0.847, 0.901]
  @apricot_glow = [1.0, 0.631, 0.392]
  @tangerine_blaze = [1.0, 0.529, 0.224]
  @spiced_amber = [0.776, 0.306, 0.0]
  @rusty_cedar = [0.608, 0.239, 0.0]
  @rusty_cedar_transparent = [0.608, 0.239, 0.0, 0.6]
  @cyan_glow = [0.2, 0.8, 0.8, 1.0]
  @light_blue_glow = [0.5, 0.8, 1.0, 1.0]
  @emerald_shade = [0.125, 0.518, 0.0]
  @gunmetal_gray = [0.349, 0.369, 0.4]
  @spring_green = [0.498, 0.696, 0.427]
  @charcoal_black = [0.145, 0.133, 0.18]
  @antique_gold = [0.608, 0.408, 0.0]
  # background colors
  @dark_blue = [0.035, 0.047, 0.106]
  @almost_black = [0.02, 0.024, 0.102]
  @almost_dark_blue = [0.04, 0.06, 0.12]
  @dark_reddish_black = [0.05, 0.03, 0.02]
  @dark_bluish_black = [0.02, 0.03, 0.05]
  @deep_midnight_blue = [0.03, 0.04, 0.08]
  @subtle_violet = [0.04, 0.03, 0.06]
  @faint_crimson = [0.06, 0.02, 0.03]
  @shadow_green = [0.03, 0.05, 0.03]
  @inky_blue = [0.01, 0.02, 0.04]
  @charcoal_blue = [0.05, 0.07, 0.11]
  @deep_plum = [0.04, 0.02, 0.05]
  @murky_teal = [0.02, 0.04, 0.04]
  @murky_blue = [0.063, 0.09, 0.176]

  def self.lerp(color1, color2, t)
    r = color1[0] + ((color2[0] - color1[0]) * t)
    g = color1[1] + ((color2[1] - color1[1]) * t)
    b = color1[2] + ((color2[2] - color1[2]) * t)
    a = (color1[3] || 1) + (((color2[3] || 1) - (color1[3] || 1)) * t)
    [r, g, b, a]
  end
end
# SPDX-SnippetEnd
