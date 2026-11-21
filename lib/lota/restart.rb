# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "strscan"
require_relative "variant"
require_relative "restart/snapshot"

module Lota
  # Starts the game again after it asks to restart, as LÖVE's main loop
  # starts its Lua state again.
  #
  # LÖVE can close the Lua state a game ran in and open a fresh one,
  # passing the new one a value the old one chose: <tt>love.event.restart</tt>
  # queues a quit message that says +restart+, love.run returns it, and
  # love.cpp's loop runs the game again with that value as
  # <tt>love.restart</tt> (src/love.cpp, main and runlove).
  #
  # Lota does the same: Lota::Boot#call runs the game again in the same
  # process, on every system, once the game has ended as a quit ends it.
  # Ruby cannot close the world a game defined, as <tt>lua_close</tt>
  # closes a Lua state, so between two runs Lota runs the exit procs the
  # game registered, takes away what the game's own files defined
  # (Snapshot), and closes the engine (Lota::Native.close_modules). What
  # the game changed outside its own files stays: a change to a built-in
  # class, or to a class it did not define, and a gem it loaded, which
  # +require+ does not load again (doc/contributors/design/game.md,
  # "Restarting").
  #
  # The value crosses as the event queue carries it, as LÖVE carries it in
  # a Variant (src/love.cpp, runlove): +nil+, +true+, +false+, a number, a
  # String, or a table of them, an Array or a Hash. Integers become Floats
  # and Symbols Strings, and a table arrives as the queue gives one back,
  # so a Hash whose keys are 1 to n arrives as an Array
  # (Lota::Event.poll). Tables nest at most MAXIMUM_DEPTH deep.
  #
  # LÖVE has no guard against a game that restarts every time it starts,
  # and Lota adds none: such a game restarts until the player stops it.
  #
  # === Example
  #
  #   # main.rb
  #   def Lota.keypressed(key)
  #     Lota::Event.restart("from the menu") if key == :r
  #   end
  #
  #   def Lota.load
  #     puts Lota.restart.inspect # => nil, then "from the menu"
  #   end
  module Restart
    # How deep tables nest in the value, a table in a table being two deep,
    # so that reading it cannot exhaust the stack. :nodoc:
    MAXIMUM_DEPTH = 100

    # Rejects what the event queue cannot carry. :nodoc:
    class Unsupported < TypeError; end

    # Catches the exit procs a game registers while it runs, so that they
    # run when that run ends, as they would when its process ended. Only
    # the main Ractor's are caught; a Lota thread's run when the process
    # ends. :nodoc:
    module ExitProcs
      private def at_exit(&block)
        return super unless Ractor.current.equal?(Ractor.main)

        procs = Restart.__send__(:exit_procs) #: Array[Proc]?
        if procs && block
          procs << block
          return block
        end
        super
      end
    end

    @value = nil
    @kept = nil
    @exit_procs = nil

    class << self
      # The value the game that restarted chose, or +nil+ when the game
      # was not started by a restart. Lota.restart returns it. :nodoc:
      attr_reader :value
      private :value

      # The value +text+ holds, which written wrote. :nodoc:
      private def parse(text)
        scanner = StringScanner.new(text.b)
        tokens = [] #: Array[Variant::token]
        read(scanner, 0, tokens)
        raise ArgumentError, "not a restart value" unless scanner.eos?

        Variant.read(tokens)
      end

      # Keeps +value+ for the run that starts next, as love.cpp keeps its
      # Variant (src/love.cpp, runlove), copied as the event queue carries
      # it. Raises TypeError, before the game ends, for a value that cannot
      # cross: anything but nil, booleans, numbers, Strings, Symbols, and
      # tables of them, a table that holds itself (<tt>"Cycle detected in
      # table"</tt>, as luax_checkvariant raises, src/common/runtime.cpp:768-774),
      # and tables nested deeper than MAXIMUM_DEPTH. :nodoc:
      private def keep(value)
        @kept = [parse(written(value, []))]
      end

      # The exit procs the run in progress has registered, or +nil+ when
      # none is caught. :nodoc:
      attr_reader :exit_procs
      private :exit_procs

      # Runs the block, which runs a game once and returns its exit status,
      # and runs it again each time the game restarts, as love.cpp's main
      # runs runlove again (src/love.cpp, main). Between runs it runs the
      # exit procs the game registered, takes away what the game in the
      # folder +directory+ returns defined (Snapshot), closes the engine
      # (Lota::Native.close_modules), and hands the next run the value.
      # +directory+ is asked after each run, since a run that started with
      # no game has no folder, and the next can start the game a player
      # dropped on it (Lota::NoGame). Returns the last run's status. :nodoc:
      private def in_process(directory)
        snapshot = Snapshot.new
        Kernel.prepend(ExitProcs) unless Kernel.ancestors.include?(ExitProcs)
        loop do
          status = catching_exit_procs { yield }
          kept = @kept
          return status unless kept

          @kept = nil
          snapshot.restore(directory.call)
          GC.start(full_mark: true, immediate_sweep: true)
          Lota::Native.close_modules
          @value = kept.first
        end
      end

      # Runs the block, catching the exit procs it registers, and runs
      # them once it ends, the last registered first, as Ruby runs them,
      # printing what one raises. Returns the block's value.
      private def catching_exit_procs
        @exit_procs = []
        yield
      ensure
        procs = @exit_procs || []
        @exit_procs = nil
        procs.reverse_each do |block|
          block.call
        rescue StandardError, ScriptError => e
          warn e.full_message
        end
      end

      # The text keep writes for +value+, inside the tables +outer+.
      private def written(value, outer)
        case value
        when nil then "nil:"
        when true, false then "boolean:#{value}"
        when Integer, Float then "number:#{[value.to_f].pack('G').unpack1('H*')}"
        when String then "string:#{value.b.unpack1('H*')}"
        when Symbol then "string:#{value.name.b.unpack1('H*')}"
        when Array then table(value.each.with_index(1).map { |element, key| [key, element] }, value, outer)
        when Hash then table(value.to_a, value, outer)
        else raise Unsupported, "can't restart with a #{value.class}: only nil, booleans, numbers, strings and tables cross"
        end
      end

      # The text of the table +value+, whose +pairs+ are its keys and
      # values, inside the tables +outer+.
      private def table(pairs, value, outer)
        raise Unsupported, "Cycle detected in table" if outer.any? { |table| table.equal?(value) }
        raise Unsupported, "can't restart with tables nested more than #{MAXIMUM_DEPTH} deep" if outer.size >= MAXIMUM_DEPTH

        inside = [*outer, value]
        "table:(#{pairs.map { |key, element| "#{written(key, inside)},#{written(element, inside)}" }.join(';')})"
      end

      # Appends to +tokens+ those of the value at +scanner+'s position,
      # +depth+ tables deep, as Lota::Variant reads them, with a String's
      # bytes as they are.
      private def read(scanner, depth, tokens)
        if scanner.skip(/nil:/) then tokens << nil
        elsif scanner.skip(/boolean:true/) then tokens << true
        elsif scanner.skip(/boolean:false/) then tokens << false
        elsif scanner.scan(/number:(\h{16})/) then tokens << [scanner[1].to_s].pack("H*").unpack1("G")
        elsif scanner.scan(/string:((?:\h\h)*)/) then tokens << [scanner[1].to_s].pack("H*")
        elsif depth < MAXIMUM_DEPTH && scanner.skip(/table:\(/) then pairs(scanner, depth + 1, tokens)
        else raise ArgumentError, "not a restart value"
        end
      end

      # Appends to +tokens+ those of the table whose opening parenthesis
      # +scanner+ has read, +depth+ tables deep, up to and with its closing
      # one: Variant::TABLE, the number of its pairs, and each key and
      # value.
      private def pairs(scanner, depth, tokens)
        tokens.push(Variant::TABLE, 0)
        count_at = tokens.size - 1
        return if scanner.skip(/\)/)

        count = 0
        loop do
          read(scanner, depth, tokens)
          expect(scanner, /,/)
          read(scanner, depth, tokens)
          tokens[count_at] = (count += 1)
          return if scanner.skip(/\)/)

          expect(scanner, /;/)
        end
      end

      # Reads +delimiter+, or raises ArgumentError.
      private def expect(scanner, delimiter)
        raise ArgumentError, "not a restart value" unless scanner.skip(delimiter)
      end
    end
  end
end
