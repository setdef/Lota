# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# KleleAtoms, unchanged, in the reference love (Plan 001, "Images, text,
# and SpriteBatch"). The game is made for LÖVE 11.3 (its conf.lua sets
# t.version), so LÖVE 12 warns in a dialog before the window opens
# (boot.lua:378-393), which the harness dismisses by pressing Return
# (test/parity/lua/conf.lua). The game reads its settings when it loads
# and saves them when it quits (main.lua:87-133, state.lua:34-39), under
# LÖVE's save directory, which the harness keeps in a home of its own.
#
# Its Ruby translation does not run in Lota yet: where a Lota game saves
# is not decided, and its sounds need love.audio, which Plan 001 leaves to
# story 4. Until both are, only LÖVE's side runs.
class KleleAtomsTest < Minitest::Test
  GAME = File.join(Parity::ROOT, "test/fixtures/klele_atoms")

  # SDL's scancode for Escape (SDL_scancode.h).
  ESCAPE = 41

  # The menu quits on Escape once it has been up for 0.3 seconds
  # (states/menu/menustate.lua:363-366); Escape goes down at the start of
  # frame 60, and the game quits before it draws it.
  SCRIPT = Parity::Script.new(frames: 60, fps: 60, holds: [], presses: [[ESCAPE, 60..60]])

  # The frames the game draws: every one but the last.
  FRAMES = SCRIPT.frames - 1

  def test_love_warns_of_the_version_in_a_dialog_then_runs_the_menu_until_escape
    Dir.mktmpdir("lota-parity-") do |directory|
      love = Parity::LoveRun.new(GAME, SCRIPT, directory)

      assert_predicate love.output.status, :success?, love.output.text
      assert_equal "This game indicates it was made for version '11.3' of LOVE.\n" \
        "It may not be compatible with the running version (12.0).\n", love.output.text
      assert_equal FRAMES, love.frames.size
      assert_path_exists File.join(directory, "home/Library/Application Support/LOVE/kleleatoms/settings2.txt")
    end
  end
end
