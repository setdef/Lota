# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "version"
require_relative "cli/commands/fuse"

module Lota
  # The +lota+ program, which runs a game as the +love+ program runs one
  # (doc/contributors/design/packaging.md, "The command line, and
  # fusing").
  #
  # <tt>lota path/to/game</tt> runs the game in a folder,
  # <tt>lota game.lota</tt> a game in one file, and <tt>lota file.rb</tt>
  # a game in one Ruby file, each with Lota::Boot, which reads LÖVE's
  # options among the arguments, such as <tt>--fused</tt> and
  # <tt>--renderers opengl</tt>, and gives the rest to the game. Given no
  # game, it prints how to give one and shows the no-game screen, which
  # starts a game dropped on it. <tt>lota --version</tt> and
  # <tt>lota --help</tt> print and quit.
  #
  # Use it via the +lota+ executable.
  #
  # === Example
  #
  #   # From a terminal:
  #   lota path/to/game
  #   lota path/to/game --level 2
  #   lota "Sample Game.lota"
  #
  #   # Programmatic access, which returns the exit status:
  #   Lota::CLI.call(["path/to/game"])
  module CLI
    # Runs the program with the arguments +argv+, and returns its exit
    # status. As love.cpp's runlove (src/love.cpp, lines 168-187), it
    # prints the version for <tt>--version</tt> and the usage for
    # <tt>--help</tt>, each only as the first argument, and otherwise runs
    # the game the arguments name, until it quits.
    #
    # <tt>lota fuse</tt> still builds a game into an app, until a game is
    # made into one only from an app Lota publishes (Commands::Fuse).
    def self.call(argv)
      case argv.first
      when "--version"
        puts "Lota #{Lota::VERSION}"
        0
      when "--help"
        print usage
        0
      when "fuse"
        Commands::Fuse.call(argv.drop(1))
        0
      else
        require "lota"
        Lota::Boot.new(nil, argv).call
      end
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # The usage LÖVE prints for --help and with no game (src/love.cpp,
    # lines 153-166; boot.lua, lines 157-166), with Lota's names.
    def self.usage
      <<~USAGE
        Lota is an *awesome* framework you can use to make 2D games in Ruby
        https://github.com/setdef/lota

        usage:
            lota --version                  prints Lota version and quits
            lota --help                     prints this message and quits
            lota path/to/gamedir            runs the game from the given directory which contains a main.rb file
            lota path/to/packagedgame.lota  runs the packaged game from the provided .lota file
            lota path/to/file.rb            runs the game from the given .rb file
      USAGE
    end
    # SPDX-SnippetEnd
  end
end
