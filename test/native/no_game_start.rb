# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Starts Lota with no game, for test/native/no_game_run_test.rb, as LÖVE
# starts when it is given none: Lota shows its no-game screen
# (Lota::NoGame), with LÖVE's own pictures (test/no_game_artwork.rb), and
# remembers how it started, as lota run does, so that it can restart.
#
# Once the screen has drawn its first frame, the game LOTA_NO_GAME_GAME
# names is dropped on it, as a folder when LOTA_NO_GAME_DROP is
# "directory", through the event queue LÖVE's own drop reaches the game
# by, or as a file when it is "file", whose name is all the screen reads
# of it (nogame.lua:3293-3295). Nothing is dropped once Lota has
# restarted, nor when LOTA_NO_GAME_DROP is not set.
require "lota"
require_relative "../no_game_artwork"

# Drops the game on the screen after its first frame.
module DropOnTheScreen
  def draw
    super
    return if @dropped || !Lota.restart.nil?

    @dropped = true
    game = ENV.fetch("LOTA_NO_GAME_GAME")
    case ENV.fetch("LOTA_NO_GAME_DROP", nil)
    when "directory" then Lota::Event.push(:directorydropped, game)
    when "file" then Lota.filedropped(Lota::Filesystem.new_file(game).first)
    end
  end
end

Lota.singleton_class.prepend(DropOnTheScreen)
Lota::NoGame.artwork = NoGameArtwork.read
Lota::Restart.__send__(:remember, ARGV)
exit Lota::Boot.__send__(:no_game, ARGV).call
