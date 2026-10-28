# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"
require_relative "frame_comparison"

# The arkanoid tutorial's snapshots, unchanged, in the reference love, and
# their Ruby translations in Lota, frame by frame (Plan 001, "Shapes and
# the keyboard").
class ArkanoidTest < Minitest::Test
  # SDL's scancodes for the arrow keys and Escape (SDL_scancode.h), which
  # are the same on every keyboard layout.
  RIGHT = 79
  LEFT = 80
  ESCAPE = 41

  # What every snapshot's love.quit prints.
  GOODBYE = "Thanks for playing! Come back soon!\n"

  # The script for the snapshots with levels, which ends in the game's
  # last screen.
  LEVELS = Parity::Script.new(frames: 1640, fps: 60, holds: [], presses: [
    [LEFT, 85..166],
    [LEFT, 176..253],
    [RIGHT, 380..392],
    [ESCAPE, 1640..1640],
  ])

  # Each snapshot, and the script both engines run it under. At 60 frames
  # a second, the ball moves 5 pixels a frame until 1-05 speeds it up to
  # about 11.7, and the platform 5 pixels a frame, then about 8.3, while an
  # arrow key is down.
  SCRIPTS = {
    # The ball leaves the window by frame 62; the platform moves right for
    # half a second, left for a whole one, then is held both ways at once,
    # which cancel out.
    "1-01_TheBallTheBrickThePlatform" => Parity::Script.new(frames: 240, fps: 60, holds: [
      [RIGHT, 31..60],
      [LEFT, 91..150],
      [RIGHT, 181..210],
      [LEFT, 181..210],
    ]),
    # The ball crosses the five bricks' row and leaves the window; the
    # platform moves both ways.
    "1-02_GameObjectsAsLuaTables" => Parity::Script.new(frames: 120, fps: 60, holds: [
      [RIGHT, 11..40],
      [LEFT, 61..110],
    ]),
    # The ball crosses the wall of bricks and the bottom wall; the platform
    # passes through the right wall, which nothing stops yet, and back.
    "1-03_BricksAndWalls" => Parity::Script.new(frames: 150, fps: 60, holds: [
      [RIGHT, 2..70],
      [LEFT, 91..140],
    ]),
    # The ball crosses bricks and walls, and the platform runs into the
    # right wall, each collision printing a line; the arrow keys are
    # pressed, so the game hears them come up and carries on, until Escape
    # comes up after the last frame and the game quits.
    "1-04_DetectingCollisions" => Parity::Script.new(frames: 180, fps: 60, holds: [], presses: [
      [RIGHT, 2..60],
      [LEFT, 101..130],
      [ESCAPE, 180..180],
    ]),
    # The ball rebounds from walls, bricks, and the platform, and knocks
    # out about 30 bricks; the platform runs into the right wall and is
    # pushed back, then moves left.
    "1-05_ResolvingCollisions" => Parity::Script.new(frames: 600, fps: 60, holds: [], presses: [
      [RIGHT, 2..50],
      [LEFT, 151..260],
      [ESCAPE, 600..600],
    ]),
    # The platform steers the ball until it clears the first level, about
    # frame 936, and the second, about frame 1577; the last second shows
    # the congratulations, drawn with LÖVE's default font.
    "1-06_Levels" => LEVELS,
    # The same game, with its levels drawn as strings.
    "1-A_LevelsAsStrings" => LEVELS,
  }.freeze

  # The script of the first snapshot, whose test checks the harness too.
  SCRIPT = SCRIPTS.fetch("1-01_TheBallTheBrickThePlatform")

  # LÖVE runs each snapshot once for every test here.
  def self.love(snapshot)
    @love ||= {}
    @love[snapshot] ||= Parity::LoveRun.new(File.join(Parity::ARKANOID, snapshot), SCRIPTS.fetch(snapshot),
      Dir.mktmpdir("lota-parity-"))
  end

  def love(snapshot = SCRIPTS.keys.first)
    self.class.love(snapshot)
  end

  def lota(snapshot = SCRIPTS.keys.first, script = SCRIPTS.fetch(snapshot))
    Parity::LotaRun.new(File.join(Parity::ARKANOID_TRANSLATED, snapshot), script, love(snapshot),
      File.dirname(love(snapshot).frames_dir))
  end

  # LÖVE runs +snapshot+ for every frame of its script, and the snapshot
  # quits through its love.quit; then Lota runs its translation, which
  # matches LÖVE's on every frame and prints what LÖVE's printed.
  def assert_matches_love(snapshot)
    script = SCRIPTS.fetch(snapshot)
    expected = love(snapshot)

    assert_predicate expected.output.status, :success?, expected.output.text
    assert_equal script.frames, expected.frames.size
    assert expected.output.text.end_with?(GOODBYE), expected.output.text

    run = lota(snapshot)

    assert_predicate run.output.status, :success?, run.output.text
    assert_nil run.mismatch, "first differing frame: #{run.mismatch}"
    assert_equal script.frames, run.compared
    assert_equal expected.output.text, run.output.text
  end

  def test_love_runs_the_snapshot_for_every_frame_and_quits_through_its_quit_callback
    assert_predicate love.output.status, :success?, love.output.text
    assert_equal SCRIPT.frames, love.frames.size
    assert_equal GOODBYE, love.output.text
  end

  SCRIPTS.each_key do |snapshot|
    define_method("test_#{snapshot.downcase.tr('-', '_')}_matches_love_frame_by_frame") do
      assert_matches_love(snapshot)
    end
  end

  # The harness itself: a script that ends by pressing a key leaves
  # quitting to the game, and stops a game that did not quit with status
  # 1, once its frames all matched. 1-01 has no keyreleased.
  def test_a_game_that_does_not_quit_on_the_last_key_fails
    script = Parity::Script.new(frames: SCRIPT.frames, fps: SCRIPT.fps, holds: SCRIPT.holds,
      presses: [[ESCAPE, (SCRIPT.frames)..(SCRIPT.frames)]])
    run = lota(SCRIPTS.keys.first, script)

    assert_equal 1, run.output.status.exitstatus, run.output.text
    assert_equal "The game did not quit after frame #{SCRIPT.frames}.\n#{GOODBYE}", run.output.text
    assert_nil run.mismatch
    assert_equal SCRIPT.frames, run.compared
  end

  # The harness itself: with the keys left alone in Lota, the first frame
  # that differs from LÖVE's is the first one LÖVE drew with the right
  # arrow held, and comparing stops there. That frame is kept as both
  # engines showed it, and the two differ as the report says.
  def test_a_frame_that_differs_is_reported_with_its_first_differing_pixel
    run = lota(SCRIPTS.keys.first, Parity::Script.new(frames: SCRIPT.frames, fps: SCRIPT.fps, holds: []))

    assert_predicate run.output.status, :success?, run.output.text
    assert_equal 31, run.mismatch&.fetch("frame"), run.mismatch.inspect
    assert_match(/\Acompare image pixel \(.+\) at \d+,\d+, matching = .*, not matching = .+ \(frame 31\)\z/,
      run.mismatch.fetch("message"))
    assert_equal 31, run.compared

    assert_equal %w[lota-0031.png love-0031.png], Dir.children(run.mismatch_dir).sort
    kept = File.binread(File.join(run.mismatch_dir, "love-0031.png"))
    assert_equal File.binread(File.join(love.frames_dir, "0031.png")), kept
    expected, actual = %w[love lota].map { |engine| frame(File.join(run.mismatch_dir, "#{engine}-0031.png")) }
    assert_equal run.mismatch.fetch("message"), Parity::FrameComparison.new(expected, actual, "frame 31").message
    # Only a test that failed leaves its frames for CI to upload.
    FileUtils.rm_rf(run.mismatch_dir)
  end

  # The PNG file at +path+, decoded by LÖVE's image module.
  def frame(path)
    Lota::Native::Image.open
    Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(File.binread(path), File.basename(path)))
  end
end
