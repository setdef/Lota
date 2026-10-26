# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module CLI
    # The commands the +lota+ executable runs.
    module Commands
      # Runs the game in a folder, as <tt>love path/to/game</tt> runs a
      # LÖVE game.
      #
      # A Lota game is a folder holding main.rb, and conf.rb if it changes
      # its settings (ADR 003). Typing the Ruby that loads Lota and starts
      # the game's loop, every time you try a change, gets in the way.
      #
      # This command starts the game in the folder you name, or in the
      # current directory, with Lota::Boot, and exits with the status the
      # game quits with. Arguments after the folder reach the game's load
      # callback. The folder goes on <tt>$LOAD_PATH</tt>, so main.rb can
      # <tt>require "player"</tt> for the player.rb beside it, as LÖVE's
      # require searches the game's folder; the working directory stays
      # where you ran the command, as it does for LÖVE.
      #
      # Use it from your game's folder while you work on it.
      #
      # === Example
      #
      #   lota run
      #   lota run path/to/game
      #   lota run path/to/game --level 2
      module Run
        # Runs the run command.
        #
        # [argv] Command-line arguments: the game's folder, then the
        #   game's own arguments.
        def self.call(argv)
          if ["--help", "-h"].include?(argv.first)
            puts usage
            exit(0)
          end

          path, *arguments = argv
          run_game(path, arguments)
        end

        # Returns command-specific usage.
        def self.usage # :nodoc:
          <<~USAGE
            Usage: lota run [path] [arguments]

            Runs the game in path, or in the current directory. The game's
            load callback receives the arguments.

            Options:
              --help, -h  Show this help
          USAGE
        end
        private_class_method :usage

        # SPDX-SnippetBegin
        # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
        # SPDX-License-Identifier: Zlib
        #
        # The message boot.lua raises when the game's path is not a folder
        # (vendor/love/src/modules/love/boot.lua:453-455). LÖVE reports it
        # after opening its window, on its error screen; Lota reports it
        # before opening anything, as a usage error.
        def self.run_game(path, arguments) # :nodoc:
          directory = File.expand_path(path || ".")
          unless File.directory?(directory)
            warn "Error: Cannot load game at path '#{directory}'."
            warn "Make sure a folder exists at the specified path."
            exit(1)
          end

          require "lota"
          exit(Lota::Boot.new(path, arguments).call)
        end
        private_class_method :run_game
        # SPDX-SnippetEnd
      end
    end
  end
end
