# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's highscore_flow.lua
# (test/fixtures/flash_blip/game/highscore_flow.lua, lines 1-101), by the
# rules of doc/contributors/design/translation.md, which this file needs
# none of, since it calls no LÖVE function. The module's fields
# pending_data, waiting_action, and on_finish_callback read and write as
# methods of the same names, and the data it keeps of a finished game, a
# table with fixed fields, is a PendingData.
#
# A callback is anything that answers call. request_proceed also takes its
# callback as a block, which, like a Lua function, ignores the action it is
# called with when it names none. Lua's print writes its arguments
# separated by tabs, through tostring.

require "highscore_manager"
require "virtual_keyboard"
require "input_recorder"
require "gamestate"
require "settings"
require "lua"

module HighscoreFlow
  PendingData = Struct.new(:score, :seed, :ticks_count, :replay_binary, :replay_version, :level_data,
    keyword_init: true)

  class << self
    attr_accessor :pending_data, :waiting_action, :on_finish_callback
  end

  @pending_data = nil
  @waiting_action = nil
  @on_finish_callback = nil

  def self.reset
    self.pending_data = nil
    self.waiting_action = nil
    self.on_finish_callback = nil
  end

  def self.prepare(score_val, current_level_data)
    reset
    return unless HighscoreManager.is_score_above_min(score_val)

    self.pending_data = PendingData.new(
      score: score_val,
      seed: InputRecorder.get_seed,
      ticks_count: InputRecorder.get_ticks,
      replay_binary: InputRecorder.serialize_v2,
      replay_version: InputRecorder.replay_version,
      level_data: current_level_data
    )
    HighscoreManager.start_relevance_check(score_val)
  end

  def self.update(_dt)
    return unless HighscoreManager.is_checking_relevance

    HighscoreManager.poll_relevance_check(proc do |is_relevant|
      self.pending_data = nil unless is_relevant
      if waiting_action && on_finish_callback
        action = waiting_action
        callback = on_finish_callback
        self.waiting_action = nil
        self.on_finish_callback = nil
        _execute_flow(action, callback)
      end
    end)
  end

  def self.request_proceed(action, on_finish_callback = nil, &block)
    on_finish_callback ||= block
    if HighscoreManager.is_checking_relevance
      self.waiting_action = action
      self.on_finish_callback = on_finish_callback
    else
      _execute_flow(action, on_finish_callback)
    end
  end

  def self.is_waiting
    !waiting_action.nil?
  end

  def self._execute_flow(action, on_finish_callback)
    data = pending_data
    self.pending_data = nil

    unless data
      on_finish_callback.call(action)
      return
    end

    source_name = data.level_data ? "Level #{Lua.tostring(data.level_data.id)}" : "Endless"
    GameState.set("virtual_keyboard")

    VirtualKeyboard.show(data.score, source_name, proc do |player_name|
      difficulty = data.level_data&.difficulty || 1.0
      HighscoreManager.submit(
        player_name,
        data.score,
        data.replay_binary,
        data.seed,
        data.ticks_count,
        difficulty,
        data.replay_version,
        proc do |success, message|
          puts "Submit score result:\t#{Lua.tostring(success)}\t#{Lua.tostring(message)}" if Settings.is_debug_enabled
          GameState.has_played_since_hi_scores = true if success
          on_finish_callback.call(action)
        end
      )
    end, proc do
      on_finish_callback.call(action)
    end)
  end
end
# SPDX-SnippetEnd
