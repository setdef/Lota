# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# Gravity Wars, unchanged, in the reference love, and its Ruby translation
# in Lota, frame by frame (Plan 001, "Shapes and the keyboard"): shapes,
# canvases with antialiasing, two small images, text in the game's
# TrueType font, keys, and random numbers, which both engines draw from
# LÖVE's own generator, seeded from the clock both fix at CLOCK.
class GravityWarsTest < Minitest::Test
  GAME = File.join(Parity::ROOT, "test/fixtures/gravity_wars")
  TRANSLATED = File.join(Parity::ROOT, "test/games/gravity_wars")

  # SDL's scancodes for the space bar, the up arrow, and Escape
  # (SDL_scancode.h), which are the same on every keyboard layout, as the
  # letters the game also reads (x and n) are not.
  SPACE = 44
  UP = 82
  ESCAPE = 41

  # The clock the game seeds its planets and ships from, and which places
  # them so that player 1's first shot, at the force it starts with, and
  # player 2's miss, and player 1's second, at 16 presses of the up arrow
  # more force, hits player 2.
  CLOCK = 1_600_000_030

  # At 60 frames a second: player 1 fires in frame 20, and the shot falls
  # into a planet by frame 409; player 2 fires in frame 440, and the shot
  # leaves the field by frame 901. Player 1 then raises the shot's force
  # 16 times, each press 1% more, which the game shows beside the ship
  # in its TrueType font, and fires in frame 980. The shot hits player 2
  # about 300 frames later, which explodes into ten more shots that fly
  # until frame 2446, and the next frame starts a new game, on a new map
  # drawn from the same generator. Escape goes down at the start of frame
  # 2520, and the game exits before it draws it.
  SCRIPT = Parity::Script.new(frames: 2520, fps: 60, clock: CLOCK, holds: [], presses: [
    [SPACE, 20..20],
    [SPACE, 440..440],
    *Array.new(16) { |press| [UP, (920 + (2 * press))..(920 + (2 * press))] },
    [SPACE, 980..980],
    [ESCAPE, 2520..2520],
  ])

  # The frames the game draws: every one but the last, which Escape ends
  # before it starts.
  FRAMES = SCRIPT.frames - 1

  # LÖVE runs the game once for every test here.
  def self.love
    @love ||= Parity::LoveRun.new(GAME, SCRIPT, Dir.mktmpdir("lota-parity-"))
  end

  def love
    self.class.love
  end

  def test_love_runs_the_game_through_a_hit_and_a_new_game
    assert_predicate love.output.status, :success?, love.output.text
    assert_equal FRAMES, love.frames.size
    assert_equal 2, love.output.text.scan("New Game Started").size, love.output.text
    assert_includes love.output.text, "you hit someone!\n"
    assert love.output.text.end_with?("escape\n"), love.output.text
  end

  def test_the_translation_matches_love_frame_by_frame
    run = Parity::LotaRun.new(TRANSLATED, SCRIPT, love, File.dirname(love.frames_dir))

    assert_predicate run.output.status, :success?, run.output.text
    assert_nil run.mismatch, "first differing frame: #{run.mismatch}"
    assert_equal FRAMES, run.compared
    assert_equal love.output.text, run.output.text
  end
end
