# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's highscore_manager.lua
# (test/fixtures/flash_blip/game/highscore_manager.lua, lines 1-215), by the
# rules of doc/contributors/design/translation.md: love.data.compress and
# encode are Lota::Data.compress and encode, their container and format
# symbols (rules 9 and 40), and love.thread.getChannel is Lota::Thread.channel
# (rule 3). The data field
# MIN_RELEVANT_SCORE reads as HighscoreManager.min_relevant_score.
#
# A score from the server, a table of id, player, and score, is a
# ScoreEntry. The messages on the download and relevance channels are
# frozen Hashes, as HttpClient pushes them, read with [:success], [:data],
# [:error], and [:relevant]. Lua's sign_replay returns two values, so it
# returns an Array. A callback is anything that answers call; Lua's test
# that an argument is a function is a test that it is a Proc. string.format's
# %q, which Ruby's format lacks, is lua_quote, which quotes as LuaJIT does.
# Lua's table.sort is not stable, nor is Ruby's sort, so scores that tie
# may come out in another order than LuaJIT's.

require "lib/hmac"
require "settings"
require "http_client"
require "lua"

module HighscoreManager
  ScoreEntry = Struct.new(:id, :player, :score)

  class << self
    attr_accessor :min_relevant_score
  end

  @min_relevant_score = 5000

  # String.format's %q as LuaJIT writes it (strfmt_putquotedlen in
  # lj_strfmt.c): quoted, with a backslash before ", \, and a newline, and
  # a control character as \ and its decimal code, three digits wide when
  # a digit follows it.
  def self.lua_quote(text)
    bytes = text.b
    quoted = +"\""
    bytes.each_byte.with_index do |byte, i|
      following = bytes.getbyte(i + 1)
      digit_follows = following && following >= 48 && following <= 57
      quoted << case byte
                when 34, 92, 10 then "\\#{byte.chr}"
                when 0..31, 127 then digit_follows ? format("\\%03d", byte) : "\\#{byte}"
                else byte.chr
      end
    end
    (quoted << "\"").force_encoding(text.encoding)
  end

  def self.build_score_payload(player_name, score, rng_seed, total_ticks, difficulty, replay_version)
    format(
      '{"p":%s,"s":%d,"rng_seed":%d,"total_ticks":%d,"difficulty":%.2f,"replay_version":%d}',
      lua_quote(player_name),
      score.floor,
      rng_seed.floor,
      total_ticks.floor,
      difficulty,
      replay_version || 1
    )
  end

  def self.sign_replay(replay_binary, nonce)
    compressed = Lota::Data.compress(:data, :lz4, replay_binary, 8)
    encoded = Lota::Data.encode(:string, :base64, compressed)
    signature = Hmac.sha256(encoded, nonce)
    [encoded, signature]
  end

  def self.parse_prepare_response(raw)
    token = raw[/"token"\s*:\s*"([^"]+)"/, 1]
    nonce = raw[/"nonce"\s*:\s*"([^"]+)"/, 1]
    [token, nonce]
  end

  def self.parse_scores(raw_json)
    scores = []
    raw_json.scan(/\{([^}]+)\}/) do |(entry)|
      id = entry[/"id"\s*:\s*(\d+)/, 1]
      player = entry[/"player"\s*:\s*"([^"]+)"/, 1]
      score = entry[/"score"\s*:\s*(\d+)/, 1]
      scores << ScoreEntry.new(Lua.tonumber(id), player, Lua.tonumber(score)) if player && score
    end
    scores.sort! { |a, b| b.score <=> a.score }
    scores
  end

  def self.post(...)
    HttpClient.post(...)
  end

  def self.start_get(...)
    HttpClient.get_via_channel(...)
  end

  @active_download = false
  @checking_relevance = false

  def self.submit(
    player_name,
    score,
    replay_binary,
    rng_seed,
    total_ticks,
    difficulty = nil,
    replay_version = nil,
    callback = nil
  )
    if replay_version.is_a?(Proc)
      callback = replay_version
      replay_version = 1
    end
    if difficulty.is_a?(Proc)
      callback = difficulty
      difficulty = 1.0
    end
    difficulty ||= 1.0

    payload = build_score_payload(player_name, score, rng_seed, total_ticks, difficulty, replay_version)

    post("/scores/prepare", payload, { "Content-Type" => "application/json" }, proc do |ok, status, raw|
      unless ok
        callback&.call(false, "Prepare failed: #{Lua.tostring(status)}")
        next
      end

      token, nonce = parse_prepare_response(raw)
      if !token || !nonce
        callback&.call(false, "Prepare failed: invalid response format")
        next
      end

      encoded, signature = sign_replay(replay_binary, nonce)
      submit_headers = {
        "Content-Type" => "application/octet-stream",
        "X-Submit-Token" => token,
        "X-Signature" => signature,
      }

      post("/scores/submit", encoded, submit_headers, proc do |sub_ok, sub_status|
        next unless callback

        if sub_ok
          callback.call(true, "Score uploaded")
        else
          callback.call(false, "Submit failed: #{Lua.tostring(sub_status)}")
        end
      end)
    end)
  end

  def self.start_download
    return if @active_download

    @active_download = true
    Lota::Thread.channel("highscore_download").clear
    start_get("/scores", "highscore_download")
  end

  def self.poll_download(callback = nil)
    return false unless @active_download

    msg = Lota::Thread.channel("highscore_download").pop
    return false unless msg

    @active_download = false

    if msg[:success]
      callback&.call(true, parse_scores(msg[:data]))
    else
      callback&.call(false, msg[:error])
    end
    true
  end

  def self.is_downloading
    @active_download
  end

  def self.start_relevance_check(score)
    return if @checking_relevance

    @checking_relevance = true

    channel = Lota::Thread.channel("relevance_check")
    channel.clear

    if score < min_relevant_score
      channel.push({ success: true, relevant: false }.freeze)
      return
    end

    start_get("/scores/check?score=#{Lua.tostring(score.floor)}", "relevance_check")
  end

  def self.poll_relevance_check(callback = nil)
    return false unless @checking_relevance

    msg = Lota::Thread.channel("relevance_check").pop
    return false unless msg

    @checking_relevance = false

    relevant = false
    if msg[:success]
      relevant = if msg[:relevant].nil?
        (msg[:data] || "").match?(/"relevant"\s*:\s*true/)
      else
        msg[:relevant]
      end
    end

    callback&.call(relevant)
    true
  end

  def self.is_score_above_min(score)
    score >= min_relevant_score
  end

  def self.is_checking_relevance
    @checking_relevance
  end

  def self.is_score_relevant(score)
    if Settings.is_web
      puts "HighscoreManager: is_score_relevant() is synchronous and does not run on web; use start_relevance_check()."
      return false
    end

    return false if score < min_relevant_score

    ok, body = HttpClient.sync_get("/scores/check?score=#{Lua.tostring(score.floor)}")
    ok && body.match?(/"relevant"\s*:\s*true/)
  end
end
# SPDX-SnippetEnd
