# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's level_data.lua
# (test/fixtures/flash_blip/game/level_data.lua, lines 1-38), by the rules
# of doc/contributors/design/translation.md: love.math.setRandomSeed
# becomes the writer Lota::Math.random_seed= (rule 5). The LevelData table,
# which its levels take as their metatable, becomes the class LevelData, so
# LevelData.new(level_id) makes one, and LevelData:load is the method load.
# A level's fields read and write as Lua's do; its win condition is a
# LevelDefinitions::WinCondition, whose type, value, and final_blip_color
# read as Lua's fields do. Lua raises with error, Ruby with raise, and
# Lua's tostring is Lua.tostring.

require "level_definitions"
require "lua"

class LevelData
  attr_accessor :id, :background_color, :star_colors, :difficulty, :win_condition, :seed

  def initialize(level_id)
    data = LevelDefinitions[level_id]
    raise "Level data not found for level_id: #{Lua.tostring(level_id)}" unless data

    self.id = level_id
    self.background_color = data.background_color
    self.star_colors = data.star_colors
    self.difficulty = data.difficulty

    win_value = data.win_condition.value
    win_value = (win_value * data.difficulty).ceil if data.win_condition.type == "blips"

    self.win_condition = LevelDefinitions::WinCondition.new(
      type: data.win_condition.type,
      value: win_value,
      final_blip_color: data.win_condition.final_blip_color,
    )
    self.seed = data.seed
  end

  def load
    Lota::Math.random_seed = seed
  end
end
# SPDX-SnippetEnd
