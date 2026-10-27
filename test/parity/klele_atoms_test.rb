# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# KleleAtoms, unchanged, in the reference love (Plan 001, "Images, text,
# and SpriteBatch"), played with the mouse. The game is made for LÖVE 11.3
# (its conf.lua sets t.version), so LÖVE 12 warns in a dialog before the
# window opens (boot.lua:378-393), which the harness dismisses by pressing
# Return (test/parity/lua/conf.lua). The game reads its settings when it
# loads and saves them when it starts a game and when it quits
# (main.lua:87-133, state.lua:34-39), and its pause menu saves the game
# (states/game/gamepause.lua:63-77), under LÖVE's save directory, which
# the harness keeps in a home of its own. Its sounds play into OpenAL
# Soft's wave file writer there (test/alsoft.conf).
#
# Its Ruby translation does not run in Lota yet: it reads its saves with
# love.filesystem.getInfo and read and writes them with write, and no rule
# of ADR 001 yet says what getInfo's table, read's two results, or the nil
# and message that read and write return when they fail become in Ruby.
# Until the maintainer settles them, only LÖVE's side runs.
class KleleAtomsTest < Minitest::Test
  GAME = File.join(Parity::ROOT, "test/fixtures/klele_atoms")

  # SDL's scancode for Escape (SDL_scancode.h).
  ESCAPE = 41

  # The middle of the tile at column +x+ and row +y+, counting from 1: the
  # grid starts 10 pixels in and 90 down, in tiles of 44
  # (states/game/gamestate.lua:197-201, gamelogic.lua:3).
  def self.tile(x, y)
    [10 + ((x - 1) * 44) + 22, 90 + ((y - 1) * 44) + 22]
  end

  # At 60 frames a second, the pointer starts off the menu's buttons, moves
  # onto the play button in frame 20, and clicks it in frame 30, once the
  # menu has been up for the 0.3 seconds it waits for
  # (states/menu/menustate.lua:370), which starts a game of two on the
  # 10 by 6 grid its settings start with: red, the player, and blue, the
  # computer. Red places atoms on (1, 1) in frame 70, on (2, 1) in frames
  # 110 and 150, and on (1, 1) again in frame 190, between blue's moves,
  # which the computer makes 0.3 seconds into its turn (gameai.lua:1 and
  # 184-189). Two atoms in a corner explode (gamelogic.lua:64-67 and
  # 193-196), and
  # put a third on (2, 1), at the edge, which explodes too: a chain
  # reaction. In frame 310 the pointer clicks the pause button
  # (gamestate.lua:188-219), and in frame 350 the pause menu's "Save &
  # Quit" (gamepause.lua:79-128 and 232-252), which saves the game and
  # goes back to the menu. Escape goes down at the start of frame 400, and
  # the menu quits before the game draws it, saving its settings.
  SCRIPT = Parity::Script.new(frames: 400, fps: 60, holds: [], presses: [[ESCAPE, 400..400]],
    moves: [
      [1, 620, 300],
      [20, 320, 242],
      [60, *tile(1, 1)],
      [100, *tile(2, 1)],
      [180, *tile(1, 1)],
      [300, 22, 22],
      [340, 325, 170],
    ],
    clicks: [30, 70, 110, 150, 190, 310, 350].map { |frame| [1, frame..frame] })

  # The frames the game draws: every one but the last.
  FRAMES = SCRIPT.frames - 1

  # LÖVE runs the game once for every test here.
  def self.love
    @love ||= Parity::LoveRun.new(GAME, SCRIPT, Dir.mktmpdir("lota-parity-"))
  end

  def love
    self.class.love
  end

  # The file +name+ LÖVE saved for the game, which is not fused, under its
  # identity (conf.lua: t.identity), in LÖVE's folder (Filesystem.cpp:
  # 608-612).
  def saved(name)
    File.binread(File.join(love.home, "Library/Application Support/LOVE/kleleatoms", name))
  end

  def test_love_warns_of_the_version_in_a_dialog_then_plays_until_escape
    assert_predicate love.output.status, :success?, love.output.text
    assert_equal "This game indicates it was made for version '11.3' of LOVE.\n" \
      "It may not be compatible with the running version (12.0).\n", love.output.text
    assert_equal FRAMES, love.frames.size
  end

  # state.saveSettings (state.lua:34-39): the grid's size, the player's
  # experience, 2 once a game has started (gamestate.lua:61), and the four
  # players' types, then fullscreen and window resizing, off.
  def test_love_saves_the_settings
    assert_equal "10\n6\n2\n1\n3\n0\n0\n0\n0", saved("settings2.txt")
  end

  # saveGame (gamepause.lua:63-77): "KSF", the grid's size, the players,
  # the experience, whose turn it is, each player's state and AI, the
  # time, then each tile's owner and atoms, column by column. Red's chain
  # reaction left (2, 1) empty and one red atom on each tile around it.
  def test_love_saves_the_game_after_a_chain_reaction
    game = saved("savegame.ksf").bytes

    assert_equal "KSF".bytes, game.first(3)
    assert_equal [10, 6, 2, 2, 2], game[3, 5]
    assert_equal [2, 2, 255, 255, 0, 3, 0, 0], game[9, 8]
    assert_equal (2 * 10 * 6) + 20, game.size
    tiles = -> (x, y) { game[20 + ((((x - 1) * 6) + (y - 1)) * 2), 2] }
    assert_equal [0, 0], tiles.call(2, 1)
    [[1, 1], [1, 2], [2, 2], [3, 1]].each { |x, y| assert_equal [1, 1], tiles.call(x, y), "tile #{x}, #{y}" }
  end
end
