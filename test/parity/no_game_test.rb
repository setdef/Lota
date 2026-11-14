# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# LÖVE's no-game screen, its own nogame.lua (vendor/love/src/scripts),
# unchanged, in the reference love, and Lota's port of it, Lota::NoGame,
# shown as Lota shows it when it starts with no game, frame by frame.
# The screen steps its physics on the frames' dt and seeds LÖVE's
# generator itself (nogame.lua:3153-3154), so both draw the same balloon,
# rope, and clouds. Lota gets LÖVE's pictures from nogame.lua as the test
# runs (test/no_game_artwork.rb), and Escape, pressed on the last frame,
# quits both, as the screen's keypressed does.
class NoGameScreenTest < Minitest::Test
  # SDL's scancode for Escape (SDL_scancode.h).
  ESCAPE = 41

  # Seven seconds at 60 frames a second: the balloon blinks first after
  # five, and is pushed every fifth physics step.
  SCRIPT = Parity::Script.new(frames: 420, fps: 60, holds: [], presses: [[ESCAPE, 420..420]])

  # LÖVE runs the screen once for every test here.
  def self.love
    @love ||= Parity::LoveRun.new(nil, SCRIPT, Parity.directory)
  end

  # Escape goes down at the start of the last frame, and the screen quits
  # as it hears of it, before it draws that frame.
  SHOWN = SCRIPT.frames - 1

  def test_lotas_no_game_screen_matches_loves_frame_by_frame
    expected = self.class.love

    assert_predicate expected.output.status, :success?, expected.output.text
    assert_equal SHOWN, expected.frames.size

    run = Parity::LotaRun.new(nil, SCRIPT, expected, File.dirname(expected.frames_dir))

    assert_predicate run.output.status, :success?, run.output.text
    assert_nil run.mismatch, run.mismatch_message
    assert_equal SHOWN, run.compared
  end
end
