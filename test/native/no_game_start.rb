# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Starts the lota program with no game, for
# test/native/no_game_run_test.rb, as LÖVE starts when it is given none:
# it prints its usage and shows its no-game screen (Lota::NoGame).
#
# Once the screen has drawn its first frame, what LOTA_NO_GAME_DROP names
# happens to it: "directory" drops the folder LOTA_NO_GAME_GAME names
# through the event queue LÖVE's own drop reaches the game by, "file"
# drops the file it names as LÖVE's event code drops one, a File opened
# closed with love.filesystem.openNativeFile
# (vendor/love/src/modules/event/sdl/Event.cpp:536-563), and "escape"
# presses Escape. Nothing happens once Lota has restarted. An error shows
# the error screen and quits (quit_on_error.rb).
require "lota"
require_relative "quit_on_error"

# Drops the game on the screen after its first frame.
module DropOnTheScreen
  def draw
    super if defined?(super)
    return if @dropped || !Lota.restart.nil?

    @dropped = true
    game = ENV.fetch("LOTA_NO_GAME_GAME", "")
    case ENV.fetch("LOTA_NO_GAME_DROP")
    when "directory" then Lota::Event.push(:directorydropped, game)
    when "file" then Lota.filedropped(Lota::Filesystem.open_native_file(game, :c).first)
    when "escape" then Lota::Event.push(:keypressed, :escape, :escape, false)
    end
  end
end

Lota.singleton_class.prepend(DropOnTheScreen)
require "lota/cli"
exit Lota::CLI.call(ARGV)
