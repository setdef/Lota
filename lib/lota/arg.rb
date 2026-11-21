# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Reads the arguments the +lota+ program is given, as arg.lua's
  # love.arg reads the +love+ program's
  # (vendor/love/src/modules/love/arg.lua, lines 98-170).
  #
  # The arguments name the game and hold the game's own arguments, with
  # LÖVE's options anywhere among them: <tt>--fused</tt>,
  # <tt>--console</tt>, <tt>--game PATH</tt>, <tt>--renderers LIST</tt>,
  # and <tt>--excluderenderers LIST</tt>. Lota::Boot reads them with
  # parse, as love.boot does (boot.lua:74-87).
  module Arg # :nodoc:
    # The options, each with how many arguments after it are its value
    # (arg.lua:98-104).
    OPTIONS = { "console" => 0, "fused" => 0, "game" => 1, "renderers" => 1, "excluderenderers" => 1 }.freeze

    # What parse read: the value of each option that was given, as an
    # Array of the arguments after it, and the arguments that are the
    # game's.
    class Line < ::Data.define(:options, :game_arguments)
      # The path of the game, or +nil+ for none.
      #
      # === Example
      #
      #   Lota::Arg.parse(["--fused", "games/pong"]).game # => "games/pong"
      def game
        value("game")
      end

      # The first argument after the option +name+, or +nil+ when it was
      # not given or nothing came after it.
      def value(name)
        options[name]&.first
      end

      # Whether the option +name+ was given.
      def set?(name)
        options.key?(name)
      end
    end

    # Reads +arguments+, an Array of Strings, as parseOptions and then
    # parseGameArguments read LÖVE's (arg.lua:121-170).
    #
    # Each argument that names an option, with two dashes, is that option,
    # unless it was given already, and takes the arguments after it that
    # are its value. The first other argument is the game's path, and
    # <tt>--</tt> ends the options, with the argument after it the game's
    # path when none came before. With +game_set+, as for a fused game,
    # whose program carries it (boot.lua:74-81), no argument is the game,
    # and <tt>--game</tt> is an argument like any other. What is left is
    # the game's arguments, in order.
    #
    # An option whose value is missing, at the end, is set with none,
    # where LÖVE's code that reads it would raise.
    #
    # === Example
    #
    #   line = Lota::Arg.parse(["games/pong", "--fused", "level2"])
    #   line.game           # => "games/pong"
    #   line.set?("fused")  # => true
    #   line.game_arguments # => ["level2"]
    def self.parse(arguments, game_set: false)
      options = game_set ? { "game" => [] } : {} #: Hash[String, Array[String]]
      indices = {} #: Hash[Integer, true]
      game = nil #: Integer?
      i = 0
      while i < arguments.size
        # Look for options.
        m = arguments.fetch(i)[/\A--(.*)/m, 1]
        if m && !m.empty? && OPTIONS.key?(m) && !options.key?(m)
          indices[i] = true
          count = OPTIONS.fetch(m)
          options[m] = take(arguments, i + 1, count, indices)
          i += count
        elsif m == "" # handle '--' as an option
          indices[i] = true
          game ||= i + 1 # handle '--' followed by game name
          break
        elsif game.nil?
          game = i
        end
        i += 1
      end

      options["game"] = take(arguments, game, 1, indices) if game && !options.key?("game")

      Line.new(options.freeze, arguments.reject.with_index { |_, index| indices[index] }.freeze)
    end

    # The +count+ arguments from +first+ on, each marked as an option's in
    # +indices+, as parseOption takes them (arg.lua:110-119).
    private_class_method def self.take(arguments, first, count, indices)
      (first...(first + count)).filter_map do |index|
        indices[index] = true
        arguments[index]
      end
    end
  end
  # SPDX-SnippetEnd
end
