# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "version"
require_relative "restart"
require_relative "cli/commands/run"
require_relative "cli/commands/fuse"

module Lota
  # Entry point for the Lota command-line interface.
  #
  # A LÖVE game runs with one command, <tt>love path/to/game</tt>.
  # Without one, you would write a script for every game to load Lota,
  # find the game's files, and start its loop.
  #
  # This module dispatches to subcommands. It routes <tt>run</tt> to
  # Commands::Run, which starts a game from its folder
  # (doc/contributors/design/packaging.md; doc/contributors/design/game.md), and
  # <tt>fuse</tt> to Commands::Fuse, which builds a game into an app that runs
  # without Ruby (doc/contributors/design/packaging.md).
  #
  # Use it via the +lota+ executable.
  #
  # === Example
  #
  #   # From a terminal:
  #   lota run path/to/game
  #   cd path/to/game
  #   lota run
  #   lota fuse path/to/game
  #
  #   # Programmatic access:
  #   Lota::CLI.call(["run", "path/to/game"])
  module CLI
    # Maps command names to handler modules.
    COMMANDS = { # :nodoc:
      "run" => Commands::Run,
      "fuse" => Commands::Fuse,
    }.freeze

    # Entry point for the CLI.
    #
    # [argv] Command-line arguments array.
    def self.call(argv)
      command_name = argv.shift

      case command_name
      when "--version", "-v"
        puts "Lota #{Lota::VERSION}"
      when "--help", "-h", nil
        puts usage
      else
        command = COMMANDS[command_name]
        if command
          Restart.__send__(:remember, [command_name, *argv])
          command.call(argv)
        else
          warn "Unknown command: #{command_name}"
          warn usage
          exit(1)
        end
      end
    end

    # Returns the main usage message.
    def self.usage
      <<~USAGE
        Usage: lota <command> [options]

        Commands:
          run [path] [arguments]  Run the game in path, or in the current directory
          fuse [path] [options]   Build the game into an app that runs without Ruby

        Options:
          --version, -v  Show version
          --help, -h     Show this help
      USAGE
    end
  end
end
