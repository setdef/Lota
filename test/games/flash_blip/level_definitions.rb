# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's level_definitions.lua
# (test/fixtures/flash_blip/game/level_definitions.lua, lines 1-48). The
# Lua file returns its definitions table, keyed by the level's two-digit
# name, which level_data.lua indexes as LevelDefinitions[level_id]; here
# that table is a Hash in the module LevelDefinitions, which
# LevelDefinitions[level_id] reads, and LevelDefinitions.definitions
# returns whole. Each definition, and its win condition, is a record whose
# fields read as Lua's do.
#
# colors.lua has no magenta, so Lua's Colors.magenta is nil, and three of
# the star color sets hold nil as their first color. Each set is the same
# four-element Array here, nil included, as LuaJIT's # counts four for a
# table constructor of four values whose last is not nil.
#
# Lua numbers are all doubles: the difficulty is rounded to hundredths with
# a Float division, and Lua's % on whole numbers is Ruby's.

require "colors"
require "settings"

module LevelDefinitions
  # A level's definition.
  Definition = Struct.new(:background_color, :star_colors, :difficulty, :win_condition, :seed,
    keyword_init: true)

  # A definition's win condition.
  WinCondition = Struct.new(:type, :value, :final_blip_color, keyword_init: true)

  class << self
    attr_reader :definitions
  end

  # The definition of the level named +level_key+, or nil, as Lua indexes
  # the table.
  def self.[](level_key)
    @definitions[level_key]
  end

  @definitions = {}

  # Background colors cycle
  bg_colors = [
    Colors.dark_blue,
    Colors.almost_black,
    Colors.almost_dark_blue,
    Colors.dark_reddish_black,
    Colors.dark_bluish_black,
    Colors.deep_midnight_blue,
    Colors.subtle_violet,
    Colors.faint_crimson,
    Colors.shadow_green,
    Colors.inky_blue,
  ]

  # Colors.magenta, which colors.lua does not define, is nil.
  magenta = nil

  # Star colors cycle
  star_color_sets = [
    [Colors.periwinkle_mist, Colors.skyline_azure, Colors.royal_sapphire, Colors.midnight_harbor],
    [magenta, Colors.cyan, Colors.apricot_glow, Colors.royal_sapphire],
    [Colors.periwinkle_mist, Colors.skyline_azure, Colors.midnight_harbor, Colors.apricot_glow],
    [magenta, Colors.cyan, Colors.royal_sapphire, Colors.midnight_harbor],
    [Colors.periwinkle_mist, Colors.apricot_glow, Colors.skyline_azure, Colors.royal_sapphire],
    [magenta, Colors.cyan, Colors.midnight_harbor, Colors.apricot_glow],
    [Colors.periwinkle_mist, Colors.skyline_azure, Colors.royal_sapphire, Colors.apricot_glow],
  ]

  1.upto(Settings.max_levels) do |level_index|
    level_key = format("%02d", level_index)
    jumps = 4 + level_index # 5 to 104
    difficulty = 1.0 + ((level_index - 1) * (3.5 - 1.0) / (Settings.max_levels - 1))
    bg_color_index = ((level_index - 1) % bg_colors.size) + 1
    star_color_index = ((level_index - 1) % star_color_sets.size) + 1
    seed = level_index * 100

    @definitions[level_key] = Definition.new(
      background_color: bg_colors[bg_color_index - 1],
      star_colors: star_color_sets[star_color_index - 1],
      difficulty: ((difficulty * 100) + 0.5).floor / 100.0,
      win_condition: WinCondition.new(type: "blips", value: jumps, final_blip_color: Colors.antique_gold),
      seed:,
    )
  end
end
# SPDX-SnippetEnd
