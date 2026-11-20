# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Starts Lota with no game, for test/native/no_game_run_test.rb, as LÖVE
# starts when it is given none: Lota shows its no-game screen
# (Lota::NoGame), and remembers how it started, as lota run does, so
# that it can restart.
#
# Once the screen has drawn its first frame, what LOTA_NO_GAME_DROP names
# happens to it: "directory" drops the folder LOTA_NO_GAME_GAME names
# through the event queue LÖVE's own drop reaches the game by, "file"
# drops the file it names as LÖVE's event code drops one, a File opened
# closed with love.filesystem.openNativeFile
# (vendor/love/src/modules/event/sdl/Event.cpp:536-563), and "escape"
# presses Escape. Nothing happens once Lota has restarted. Each process
# that runs this file logs a line that says it started, to the file
# LOTA_RESTART_LOG names, so the test tells a restart by exec from one in
# the same process. An error shows the error screen and quits
# (quit_on_error.rb), which this file loads itself, since a restart by
# exec keeps none of Ruby's -r flags (Lota::Restart).
require "lota"
require_relative "quit_on_error"

File.open(ENV.fetch("LOTA_RESTART_LOG"), "a") { |log| log.puts("start pid=#{Process.pid}") }

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
Lota::Restart.__send__(:remember, ARGV)
exit Lota::Boot.no_game(ARGV).call
