# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's input_recorder.lua
# (test/fixtures/flash_blip/game/input_recorder.lua, lines 1-104), by the
# rules of doc/contributors/design/translation.md: love.math.random is
# Lota::Math.random and setRandomSeed the writer random_seed= (rule 5).
# The module's locals are its instance variables. Its data fields
# REPLAY_VERSION and INPUT read as InputRecorder.replay_version and
# InputRecorder.input, and INPUT, a record of five input ids, is an Inputs
# whose fields are their names downcased (InputRecorder.input.blip). A
# recorded event, a table of a tick and an id, is an Event. Lua's
# string.char of several bytes is those bytes packed with C*, so a
# serialized replay is binary text, byte for byte the same.

module InputRecorder
  Inputs = Struct.new(:none, :blip, :ping, :multiplier_started, :multiplier_ended)
  Event = Struct.new(:tick, :id)

  class << self
    attr_reader :replay_version, :input
  end

  @events = []
  @is_running = false
  @ticks = 0
  @seed = 0

  @replay_version = 2

  @input = Inputs.new(
    none: 0,
    blip: 1,
    ping: 2,
    multiplier_started: 3,
    multiplier_ended: 4
  ).freeze

  def self.start(initial_seed = nil)
    @events = []
    @is_running = true
    @ticks = 0
    @seed = initial_seed || Lota::Math.random(0, 2_147_483_647)
    Lota::Math.random_seed = @seed
  end

  def self.stop
    @is_running = false
  end

  def self.tick
    @ticks += 1 if @is_running
  end

  def self.add_event(event_tick, input_id)
    event = Event.new(event_tick, input_id)
    insert_at = @events.size + 1
    insert_at -= 1 while insert_at > 1 && @events[insert_at - 2].tick > event_tick
    @events.insert(insert_at - 1, event)
  end

  def self.record(input_id)
    return if !@is_running || input_id == input.none

    add_event(@ticks, input_id)
  end

  def self.record_next_tick(input_id)
    return if !@is_running || input_id == input.none

    add_event(@ticks + 1, input_id)
  end

  def self.serialize_event(event)
    event_tick = event.tick
    tick_byte1 = event_tick % 256
    tick_byte2 = event_tick.fdiv(256).floor % 256
    tick_byte3 = event_tick.fdiv(65_536).floor % 256
    tick_byte4 = event_tick.fdiv(16_777_216).floor % 256
    [tick_byte1, tick_byte2, tick_byte3, tick_byte4, event.id].pack("C*")
  end

  def self.serialize
    parts = []
    @events.each do |event|
      parts << serialize_event(event)
    end
    parts.join.b
  end

  def self.serialize_v2
    parts = ["FBRP".b, [replay_version, 1, 0, 0].pack("C*")]
    @events.each do |event|
      parts << serialize_event(event)
    end
    parts.join.b
  end

  def self.get_seed
    @seed
  end

  def self.get_ticks
    @ticks
  end

  def self.get_count
    @events.size
  end

  def self.is_active
    @is_running
  end
end
# SPDX-SnippetEnd
