# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# The arkanoid tutorial's snapshots, unchanged, in the reference love, and
# their Ruby translations in Lota, frame by frame (Plan 001, "Shapes and
# the keyboard").
class ArkanoidTest < Minitest::Test
  # SDL's scancodes for the arrow keys (SDL_scancode.h), which are the
  # same on every keyboard layout.
  RIGHT = 79
  LEFT = 80

  # 1-01 moves the ball 5 pixels a frame at 60 frames a second, off the
  # bottom of the window by frame 62, and the platform 5 pixels a frame
  # while an arrow key is held: right for half a second, left for a whole
  # one, then both at once, which cancel out.
  SCRIPT = Parity::Script.new(frames: 240, fps: 60, holds: [
    [RIGHT, 31..60],
    [LEFT, 91..150],
    [RIGHT, 181..210],
    [LEFT, 181..210],
  ])

  SNAPSHOT = "1-01_TheBallTheBrickThePlatform"

  # LÖVE runs the snapshot once for every test here.
  def self.love
    @love ||= Parity::LoveRun.new(File.join(Parity::ARKANOID, SNAPSHOT), SCRIPT, Dir.mktmpdir("lota-parity-"))
  end

  def love
    self.class.love
  end

  def lota(script = SCRIPT)
    Parity::LotaRun.new(File.join(Parity::ARKANOID_TRANSLATED, SNAPSHOT), script, love,
      File.dirname(love.frames_dir))
  end

  def test_love_runs_the_snapshot_for_every_frame_and_quits_through_its_quit_callback
    assert_predicate love.output.status, :success?, love.output.text
    assert_equal SCRIPT.frames, love.frames.size
    assert_equal "Thanks for playing! Come back soon!\n", love.output.text
  end

  def test_1_01_the_ball_the_brick_the_platform_matches_love_frame_by_frame
    run = lota

    assert_predicate run.output.status, :success?, run.output.text
    assert_nil run.mismatch, "first differing frame: #{run.mismatch}"
    assert_equal SCRIPT.frames, run.compared
    assert_equal love.output.text, run.output.text
  end

  # The harness itself: with the keys left alone in Lota, the first frame
  # that differs from LÖVE's is the first one LÖVE drew with the right
  # arrow held, and comparing stops there.
  def test_a_frame_that_differs_is_reported_with_its_first_differing_pixel
    run = lota(Parity::Script.new(frames: SCRIPT.frames, fps: SCRIPT.fps, holds: []))

    assert_predicate run.output.status, :success?, run.output.text
    assert_equal 31, run.mismatch&.fetch("frame"), run.mismatch.inspect
    assert_match(/\Acompare image pixel \(.+\) at \d+,\d+, matching = .*, not matching = .+ \(frame 31\)\z/,
      run.mismatch.fetch("message"))
    assert_equal 31, run.compared
  end
end
