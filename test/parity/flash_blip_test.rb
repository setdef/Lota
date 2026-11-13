# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# FLASH-BLIP (github.com/plinkr/flash-blip, MIT, with the moonshine
# shaders it carries under MIT and 0BSD, and no other assets: it draws its
# text a rectangle a pixel, and makes its sounds and music from formulas),
# unchanged, in the reference love, and its Ruby translation in Lota
# (test/games/flash_blip), frame by frame, the heaviest of the fixture
# games: in its attract mode the game plays itself under a menu, every
# frame through four shaders (glow, a blur, scanlines, and a CRT's
# curve). The game is made for LÖVE 11.5 (its conf.lua sets t.version
# from product.env), so LÖVE 12 warns in a dialog before the window opens,
# which the harness answers, and it uses only names LÖVE 12 keeps, three of
# them deprecated, so it runs without a patch.
#
# The game generates its music in a love.thread thread and waits on the
# splash screen for it (music.lua:281-358, main.lua:563-569), and asks a
# server for a newer version in another (update_checker.lua:113-130),
# which the harness refuses in both engines alike, so no run reaches the
# network (Parity::OFFLINE, test/parity/offline_test.rb). The harness
# runs each thread to its end as it starts (wait_for_threads in
# test/parity/lua/conf.lua), and so does Lota's probe for each of the
# translation's Lota::Thread::Threads (test/parity/probe.rb), so the
# splash ends in frame 1 in both. Its first star color comes from a pairs loop
# (parallax.lua:13-16), whose order LuaJIT changes from run to run, which
# the harness fixes (sorted_pairs).
class FlashBlipTest < Minitest::Test
  GAME = File.join(Parity::ROOT, "test/fixtures/flash_blip/game")
  TRANSLATED = File.join(Parity::ROOT, "test/games/flash_blip")

  # SDL's scancodes for Return and the space bar (SDL_scancode.h).
  RETURN = 40
  SPACE = 44

  # At 60 frames a second, the game plays itself under its menu until
  # Return, in frame 300, starts ENDLESS MODE, the first item, with LÖVE's
  # generator seeded from the clock (input.lua:100-107). The game ignores
  # input for its first second (main.lua:146-150), then the player blips
  # with the space bar every 40 frames from frame 400, until an obstacle
  # ends the game, whose score is a new high score, which the game saves
  # (main.lua:257-264, player_progress.lua). The harness quits after frame
  # 900.
  SCRIPT = Parity::Script.new(frames: 900, fps: 60, holds: [], presses: [
    [RETURN, 300..300],
    *Array.new(10) { |press| [SPACE, (400 + (40 * press))..(400 + (40 * press))] },
  ])

  # LÖVE runs the game once for every test here.
  def self.love
    @love ||= Parity::LoveRun.new(GAME, SCRIPT, Parity.directory)
  end

  def love
    self.class.love
  end

  # Lota runs the translation once for every test here, after LÖVE.
  def self.lota
    @lota ||= Parity::LotaRun.new(TRANSLATED, SCRIPT, love, File.dirname(love.frames_dir))
  end

  def lota
    self.class.lota
  end

  # What +run+ printed, each deprecation notice without the engine's name
  # or where the name was used, and with the settings function's name as
  # Lota's: LÖVE's notices begin "LOVE - Warning:" and Lota's "Lota -
  # Warning:" (Lota::Deprecation), each says where in its own files the
  # name was used, and Lota's error messages name Lota.conf where LÖVE's
  # name love.conf (translation rule 23).
  def self.printed(run)
    run.output.text.gsub(/^(?:LOVE|Lota) - Warning: (?:.*?:\d+: )?/, "Warning: ").gsub("in love.conf", "in Lota.conf")
  end

  # The game's progress file, which LÖVE saved under its identity
  # (product.env's PRODUCT_ID) in LÖVE's folder, or Lota in Lota's.
  def saved(run, folder)
    File.binread(File.join(TestHome.application_data(run.home), folder, "com.plinkr.flash_blip",
      "player_progress_v2.txt"))
  end

  def test_love_warns_of_the_version_and_of_deprecated_names_then_plays_every_frame
    assert_predicate love.output.status, :success?, love.output.text
    assert_equal "Warning: Using deprecated field t.gammacorrect in Lota.conf (replaced by t.graphics.gammacorrect)\n" \
      "This game indicates it was made for version '11.5' of LOVE.\n" \
      "It may not be compatible with the running version (12.0).\n" \
      "Warning: Using deprecated field window.display (replaced by displayindex field)\n" \
      "Warning: Using deprecated field window.highdpi (replaced by t.highdpi in Lota.conf)\n" \
      "Warning: Using deprecated texture2D() or texture3D() or textureCube() function calls in shader code " \
      "(replaced by texture() function calls)\n", self.class.printed(love)
    assert_equal SCRIPT.frames, love.frames.size
  end

  def test_the_translation_matches_love_frame_by_frame
    assert_predicate lota.output.status, :success?, lota.output.text
    assert_nil lota.mismatch, lota.mismatch_message
    assert_equal SCRIPT.frames, lota.compared
    assert_equal self.class.printed(love), self.class.printed(lota)
  end

  # Both runs mix the same music and sounds, sample for sample: the music,
  # from the SoundData its thread generates, from frame 1.
  def test_the_translation_mixes_what_love_mixes
    assert_predicate lota.output.status, :success?, lota.output.text
    expected = File.binread(love.audio).unpack("e*")
    actual = File.binread(lota.audio).unpack("e*")
    differing = expected.each_index.find { |index| expected[index] != actual[index] }
    frame = differing && ((differing / 2 / (Parity::LOOPBACK_RATE / SCRIPT.fps)) + 1)

    assert_nil differing, "first differing sample: #{differing}, in frame #{frame}"
    assert_equal SCRIPT.frames * Parity::LOOPBACK_RATE / SCRIPT.fps * 2, expected.size
    assert_equal expected.size, actual.size
  end

  # Both runs save the same progress, compressed and encoded as the game
  # writes it (player_progress.lua), byte for byte.
  def test_the_translation_saves_what_love_saves
    assert_predicate lota.output.status, :success?, lota.output.text
    assert_equal saved(love, TestHome::LOVE_FOLDER), saved(lota, TestHome::LOTA_FOLDER)
  end

  # Each of the game's threads runs in a Lota::Thread::Thread, as each of
  # LÖVE's runs in a love.thread Thread: the music's and the update
  # check's, which the probe counts.
  def test_the_translation_runs_its_threads_in_lota_threads
    assert_predicate lota.output.status, :success?, lota.output.text
    assert_equal 2, lota.report["threads"]
  end
end
