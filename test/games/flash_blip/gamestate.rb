# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's gamestate.lua
# (test/fixtures/flash_blip/game/gamestate.lua, lines 1-68). The GameState
# table becomes the module GameState, each of its fields a reader and
# writer of the same name, and each of its functions a method of the
# module. The state names are the game's own Strings, not names LÖVE
# defines, so they stay Strings. GameState.is and GameState.is_not keep
# their names, without a question mark, as the other files call them.

module GameState
  class << self
    attr_accessor :current, :previous, :is_attract_mode, :is_paused, :ignore_input_timer,
      :game_over_input_delay, :level_completed_input_delay, :restart_delay_counter, :is_new_hi_score,
      :hi_score_flash_timer, :hi_score_flash_visible, :all_levels_completed, :has_played_since_hi_scores,
      :hi_scores_dirty
  end

  @current = "attract"
  @previous = nil
  @is_attract_mode = true
  @is_paused = false
  @ignore_input_timer = 0
  @game_over_input_delay = 0
  @level_completed_input_delay = 0
  @restart_delay_counter = 0
  @is_new_hi_score = false
  @hi_score_flash_timer = 0
  @hi_score_flash_visible = true
  @all_levels_completed = false
  @has_played_since_hi_scores = false
  @hi_scores_dirty = false

  def self.set(state)
    GameState.previous = GameState.current
    GameState.current = state
    GameState.has_played_since_hi_scores = true if state == "playing"
    GameState.hi_scores_dirty = true if state == "hi_scores"
  end

  def self.update(dt)
    if GameState.ignore_input_timer > 0
      GameState.ignore_input_timer = GameState.ignore_input_timer - dt
      GameState.ignore_input_timer = 0 if GameState.ignore_input_timer < 0
    end

    if GameState.current == "gameOver"
      if GameState.game_over_input_delay > 0
        GameState.game_over_input_delay = GameState.game_over_input_delay - dt
      end
    elsif GameState.current == "levelCompleted"
      if GameState.level_completed_input_delay > 0
        GameState.level_completed_input_delay = GameState.level_completed_input_delay - dt
      end
    end

    if GameState.restart_delay_counter > 0
      GameState.restart_delay_counter = GameState.restart_delay_counter - 1
    end

    return unless GameState.is_new_hi_score

    GameState.hi_score_flash_timer = GameState.hi_score_flash_timer + dt
    return unless GameState.hi_score_flash_timer > 0.8

    GameState.hi_score_flash_visible = !GameState.hi_score_flash_visible
    GameState.hi_score_flash_timer = 0
  end

  def self.is(state)
    GameState.current == state
  end

  def self.is_not(state)
    GameState.current != state
  end
end
# SPDX-SnippetEnd
