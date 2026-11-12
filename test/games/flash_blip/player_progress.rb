# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's player_progress.lua
# (test/fixtures/flash_blip/game/player_progress.lua, lines 1-177), by the
# rules of doc/contributors/design/translation.md: love.filesystem.read and
# write return Arrays (rule 4), love.data's compress, decompress, encode,
# and decode are Lota::Data's (rule 40), and their container and format
# names symbols (rule 9). The module table is the module PlayerProgress
# and its locals the module's instance variables. The progress table, of
# four fixed fields, is a Progress; its unlocked levels and high scores,
# keyed by level id at run time, are Hashes. A high score entry, a table
# of score and source, is a HighScoreEntry; hi_scores.rb reads both.
#
# Lua's read returns the contents and size, or nil and a message, so the
# third value the Lua reads as its error is always nil, and so it is here.
# The file is parsed as bytes, as Lua's patterns read it, and Lua's %s
# trim strips space, tab, newline, vertical tab, form feed, and carriage
# return (Ruby's strip also strips NUL, which Lua's %s does not). The
# saved text writes numbers with Lua.tostring, as tostring does. In the
# fallback branch the progress shares the default table of high scores,
# as Lua's does.

require "lua"

module PlayerProgress
  Progress = Struct.new(:current_level, :unlocked_levels, :level_high_scores, :endless_high_score, keyword_init: true)
  HighScoreEntry = Struct.new(:score, :source, keyword_init: true)

  TRIM = /\A[ \t\n\v\f\r]*(.*?)[ \t\n\v\f\r]*\z/m

  @default_progress = Progress.new(
    current_level: "01",
    unlocked_levels: { "01" => true },
    level_high_scores: {},
    endless_high_score: 0,
  )

  @progress = Progress.new
  @player_progress_file = "player_progress_v2.txt"

  # Lua's s:match("^%s*(.-)%s*$").
  def self.trim(text)
    text[TRIM, 1]
  end
  private_class_method :trim

  def self.load
    encoded_content, _, error = Lota::Filesystem.read(@player_progress_file)
    if encoded_content&.bytesize&.positive?
      compressed_data = Lota::Data.decode(:data, :base64, encoded_content)
      content = Lota::Data.decompress(:string, :lz4, compressed_data)
      @progress = Progress.new(
        current_level: nil,
        unlocked_levels: nil,
        level_high_scores: nil,
        endless_high_score: nil,
      )
      content.b.scan(/[^\n]+/) do |line|
        match = line.match(/([^=]+)=(.*)/)
        next unless match

        key = trim(match[1])
        value = trim(match[2])
        case key
        when "current_level"
          @progress.current_level = value
        when "unlocked_levels"
          @progress.unlocked_levels = {}
          value.scan(/[^,]+/) do |lvl|
            lvl = trim(lvl)
            @progress.unlocked_levels[lvl] = true
          end
        when "level_high_scores"
          @progress.level_high_scores = {}
          value.scan(/[^,]+/) do |pair_str|
            pair = pair_str.match(/([^:]+):([^:]+)/)
            next unless pair

            lvl = trim(pair[1])
            score_str = trim(pair[2])
            @progress.level_high_scores[lvl] = Lua.tonumber(score_str) || 0
          end
        when "endless_high_score"
          @progress.endless_high_score = Lua.tonumber(value) || 0
        end
      end
      @progress.current_level = @default_progress.current_level unless @progress.current_level
      @progress.unlocked_levels = { "01" => true } unless @progress.unlocked_levels
      @progress.level_high_scores = {} unless @progress.level_high_scores
      @progress.endless_high_score = 0 unless @progress.endless_high_score
    else
      @progress = Progress.new(
        current_level: @default_progress.current_level,
        unlocked_levels: { "01" => true },
        level_high_scores: @default_progress.level_high_scores,
        endless_high_score: 0,
      )
      if error && !(error.match?(/No such file/) || error.match?(/does not exist/))
        puts "Failed to load progress: #{error}"
      end
    end
  end

  def self.save
    data = "current_level=#{Lua.tostring(@progress.current_level)}\n"
    ul_levels = @progress.unlocked_levels.keys
    ul_levels.sort! { |a, b| Lua.tonumber(a) <=> Lua.tonumber(b) }
    ul_str = ul_levels.join(",")
    data = "#{data}unlocked_levels=#{ul_str}\n"
    hs_str = +""
    # Lua writes the level high scores in pairs' order, which LuaJIT changes
    # from run to run and the parity harness makes sorted
    # (test/parity/lua/conf.lua, sorted_pairs), so they are in the order of
    # the levels' names.
    @progress.level_high_scores.sort.each do |lvl, score|
      hs_str << "," if hs_str.bytesize.positive?
      truncated_score = score.floor
      hs_str << "#{lvl}:#{Lua.tostring(truncated_score)}"
    end
    data = "#{data}level_high_scores=#{hs_str}\n"
    data = "#{data}endless_high_score=#{Lua.tostring((@progress.endless_high_score || 0).floor)}\n"

    compressed_data = Lota::Data.compress(:data, :lz4, data, 9)
    encoded_data = Lota::Data.encode(:string, :base64, compressed_data)
    success, message = Lota::Filesystem.write(@player_progress_file, encoded_data)
    puts "Failed to save progress: #{message || 'Unknown error'}" unless success
  end

  def self.get_current_level
    @progress.current_level
  end

  def self.set_current_level(level)
    @progress.current_level = level
    save
  end

  def self.is_level_unlocked(level)
    !@progress.unlocked_levels[level].nil?
  end

  def self.unlock_level(level)
    return if is_level_unlocked(level)

    @progress.unlocked_levels[level] = true
    save
  end

  def self.get_level_high_score(level_id)
    @progress.level_high_scores[level_id] || 0
  end

  def self.set_level_high_score(level_id, score)
    return unless score > (@progress.level_high_scores[level_id] || 0)

    @progress.level_high_scores[level_id] = score
    save
  end

  def self.get_endless_high_score
    @progress.endless_high_score || 0
  end

  def self.set_endless_high_score(score)
    return unless score > (@progress.endless_high_score || 0)

    @progress.endless_high_score = score
    save
  end

  def self.get_all_high_scores
    list = []
    if @progress.endless_high_score&.positive?
      list << HighScoreEntry.new(score: @progress.endless_high_score, source: "Endless")
    end
    # Lua lists the level high scores in pairs' order, sorted under the
    # parity harness (save, above), which decides the order of equal scores
    # after the sort below.
    @progress.level_high_scores&.sort&.each do |lvl, score|
      next unless score&.positive?

      source_display = if lvl.byteslice(0, 5) == "level"
        lvl
      elsif lvl.byteslice(0, 3) == "lvl"
        "level#{lvl.byteslice(3..)}"
      else
        "level#{lvl}"
      end
      list << HighScoreEntry.new(score:, source: source_display)
    end
    # Lua's table.sort is not stable, and neither is Ruby's sort, so equal
    # scores may come out in another order.
    list.sort! { |a, b| b.score <=> a.score }
    list
  end

  load
end
# SPDX-SnippetEnd
