# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
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
  # <tt>love.restart</tt> (src/love.cpp, main and runlove). Ruby cannot
  # close the world a game defined, so Lota does what a fresh start is: it
  # ends the game as a quit does, with the window closed and the exit
  # procs run, and then replaces the process with <tt>lota run</tt> again
  # (<tt>Process.exec</tt>), with the command and arguments it was started
  # with. The process keeps its id.
  #
  # Windows cannot replace a process, so there Ruby's exec starts the
  # command as a new process, waits for it, and exits with its status
  # (Ruby's win32/win32.c, child_result). Each run has a process id of its
  # own, and the process that restarted stays, waiting, until the run it
  # started ends.
  #
  # On macOS, a restart can wait on a busy machine. Before the new run
  # starts, the system ends every other thread of the process, and each
  # thread runs its own ending at its own priority: exit raises the
  # priority of a dying process's threads, but exec does not (XNU 12377,
  # bsd/kern/mach_loader.c, load_machfile, and osfmk/kern/task.c,
  # task_start_halt_locked and task_complete_halt). A process that opened
  # a window keeps threads of the system's frameworks at background and
  # utility priority, so when other programs keep every core busy, those
  # threads wait for a turn and the restart waits with them: a few
  # milliseconds on an idle machine, seconds or more on a loaded one.
  # macOS has no public way to raise those threads, and starting a new
  # process instead would not keep the process id.
  #
  # <tt>lota run</tt> remembers the program Ruby runs, <tt>$0</tt>, which
  # under <tt>bundle exec lota run</tt> is still Lota's: Bundler loads the
  # program into its own process, so the process began as +bundle+, but
  # it sets <tt>$0</tt> to the program, and puts its own setup in
  # +RUBYOPT+, which the new process inherits (Bundler::CLI::Exec,
  # kernel_load, and Bundler::SharedHelpers.set_rubyopt).
  #
  # A fused game, which Lota::Boot#call starts and remembers as it starts
  # when the game is fused, as the entry script <tt>lota fuse</tt> writes
  # boots it (Lota::Fuse), starts again as LÖVE's fused game does, by running the
  # program the process runs, with the same arguments: the app's own
  # launcher, which Fledge builds and which runs Ruby inside its own
  # process, found as LÖVE's love.filesystem.getExecutablePath finds it
  # (Lota::Filesystem.executable_path). It sets the app up as it did the
  # first time, and on macOS keeps the app's bundle. Only when that
  # program is Ruby's own, as when someone runs the entry script with
  # +ruby+, does the game start again through Ruby and the script.
  #
  # A game started in any other way, such as by Lota::Boot in your own
  # program, or on a phone, which cannot replace its process, ends when it
  # restarts, as a quit ends it. Ruby's own flags are not remembered but
  # +-w+ and +-W0+; the ones that matter to a game belong in +RUBYOPT+,
  # which the new process inherits with the rest of the environment.
  #
  # The restart value crosses in an environment variable, Restart::VARIABLE,
  # which the new process reads once and removes. It holds a type, a colon,
  # and the value (<tt>nil:</tt>, <tt>boolean:true</tt>, <tt>number:</tt>
  # and <tt>string:</tt> followed by hexadecimal digits, or
  # <tt>table:</tt> followed by its keys and values in parentheses), and
  # nothing in it is evaluated: +nil+, +true+, +false+, a number, a String,
  # or a table of them, an Array or a Hash, which are what the event queue
  # carries. A table arrives as the queue gives one back, so a Hash whose
  # keys are 1 to n arrives as an Array (Lota::Event.poll). Anything else
  # in the variable is ignored. Environment variables are limited in size,
  # so a value of more than about 100 kilobytes cannot cross on every
  # system, and none of more than a megabyte, MAXIMUM_LENGTH, crosses on
  # any; tables nest at most MAXIMUM_DEPTH deep.
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
    # The environment variable the restart value crosses in. :nodoc:
    VARIABLE = "LOTA_RESTART_VALUE"

    # The longest text the variable holds, in bytes: macOS limits a
    # process's arguments and environment together to a megabyte
    # (ARG_MAX), Linux each variable to 128 kilobytes (MAX_ARG_STRLEN), and
    # Windows each to 32,767 characters. :nodoc:
    MAXIMUM_LENGTH = 1_048_576

    # How deep tables nest in the variable, a table in a table being two
    # deep, so that reading it cannot exhaust the stack. :nodoc:
    MAXIMUM_DEPTH = 100

    # The feature flag that starts the game again in the same process, as
    # LÖVE does, rather than by exec: unset, never; +always+, on every
    # restart. :nodoc:
    IN_PROCESS = "LOTA_IN_PROCESS_RESTART"

    # Rejects what the event queue cannot carry. :nodoc:
    class Unsupported < TypeError; end

    # Catches the exit procs a game registers while it runs in a process
    # that starts it again, so that they run when that run ends, as they
    # would when its process ended. Only the main Ractor's are caught;
    # a Lota thread's run when the process ends. :nodoc:
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
    @taken = false
    @command = nil
    @directory = nil
    @pending = nil
    @arguments = []
    @fused = false
    @kept = nil
    @exit_procs = nil

    class << self
      # The value the game that restarted chose, or +nil+ when the game
      # was not started by a restart. Lota.restart returns it. :nodoc:
      attr_reader :value
      private :value

      # Writes +value+ for the environment: its type, a colon, and its
      # value, with numbers as the hexadecimal digits of their eight bytes
      # and Strings as those of their bytes, so that every number and every
      # String, valid UTF-8 or not, arrives as it left. Integers become
      # Floats, as the queue makes them, and Symbols Strings. A table, an
      # Array or a Hash, is its pairs of keys and values, each written so,
      # a key and its value parted by a comma and each pair from the next
      # by a semicolon, in parentheses; an Array's keys are 1 to its size.
      # Raises TypeError for anything else, for a table that holds itself
      # (<tt>"Cycle detected in table"</tt>, as luax_checkvariant raises,
      # src/common/runtime.cpp:768-774), for tables nested deeper than
      # MAXIMUM_DEPTH, and for a value whose text is longer than
      # MAXIMUM_LENGTH. :nodoc:
      private def encode(value)
        text = written(value, [])
        if text.bytesize > MAXIMUM_LENGTH
          raise Unsupported, "can't restart with a value too long to cross: #{text.bytesize} bytes, of #{MAXIMUM_LENGTH}"
        end

        text
      end

      # The value +text+ holds, which encode wrote. Raises ArgumentError
      # for anything else, however it is shaped. :nodoc:
      private def decode(text)
        raise ArgumentError, "not a restart value" if text.bytesize > MAXIMUM_LENGTH

        parse(text)
      end

      # The value +text+ holds, of any length. :nodoc:
      private def parse(text)
        scanner = StringScanner.new(text.b)
        tokens = [] #: Array[Variant::token]
        read(scanner, 0, tokens)
        raise ArgumentError, "not a restart value" unless scanner.eos?

        Variant.read(tokens)
      end

      # Reads the restart value the previous run left in +environment+,
      # once: the variable is removed whatever it holds, and a value that
      # is not one encode wrote is dropped. Only the first call in a
      # process reads. :nodoc:
      private def take(environment = ENV)
        return if @taken

        @taken = true
        text = environment.delete(VARIABLE)
        @value = text && decode(text)
      rescue ArgumentError
        @value = nil
      end

      # Remembers how the game was started, to start it again (the
      # interpreter, the program Ruby runs, <tt>$0</tt>, and the working
      # directory), and makes sure a restart is the last thing the process
      # does. +arguments+ are the command line's arguments after the
      # program. With +fused+, the game is a fused one, which starts again
      # by running the program the process runs (fused_command). A program
      # Ruby cannot start again, such as <tt>-e</tt>'s, is not remembered.
      # :nodoc:
      private def remember(arguments, fused: false)
        script = File.expand_path($PROGRAM_NAME)
        return unless File.file?(script)

        flag = { true => "-w", nil => "-W0" }[$VERBOSE]
        @command = [RbConfig.ruby, *flag, script, *arguments].freeze
        @arguments = arguments.dup.freeze
        @fused = fused
        @directory = Dir.pwd
        install
      end

      # Starts the game again with +value+ once it has ended: in this
      # process, when IN_PROCESS says so (keep); otherwise by exec when the
      # command was remembered and the game is not on a phone, which
      # cannot replace its process (request); and otherwise not at all,
      # though +value+ is checked all the same. Raises TypeError, before
      # the game ends, for a value that cannot cross. :nodoc:
      private def ask(value, phone:)
        if in_process?
          keep(value)
        elsif restartable? && !phone
          request(value)
        else
          encode(value)
        end
      end

      # Whether a restart starts the game again in this process. :nodoc:
      private def in_process?(environment = ENV)
        environment[IN_PROCESS] == "always"
      end

      # Keeps +value+ for the run that starts next in this process, as
      # love.cpp keeps its Variant (src/love.cpp, runlove): it crosses as
      # it would cross exec, so a game sees the same value either way.
      # Raises TypeError as encode does, but for its length. :nodoc:
      private def keep(value)
        @kept = [parse(written(value, []))]
      end

      # The exit procs the run in progress has registered, or +nil+ when
      # none is caught. :nodoc:
      attr_reader :exit_procs
      private :exit_procs

      # Runs the block, which runs the game in the folder +directory+ once
      # and returns its exit status, and runs it again each time the game
      # restarts in this process, as love.cpp's main runs runlove again
      # (src/love.cpp, main). Between runs it runs the exit procs the game
      # registered, takes away what the game defined (Snapshot), closes
      # the engine (Lota::Native.close_modules), and hands the next run
      # the value. Returns the last run's status. Unless IN_PROCESS says
      # so, it runs the block once. :nodoc:
      private def in_process(directory)
        return yield unless in_process?

        snapshot = Snapshot.new
        Kernel.prepend(ExitProcs) unless Kernel.ancestors.include?(ExitProcs)
        loop do
          status = catching_exit_procs { yield }
          kept = @kept
          return status unless kept

          @kept = nil
          snapshot.restore(directory)
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

      # Whether the game can restart: whether the command was remembered.
      # :nodoc:
      private def restartable?
        !@command.nil?
      end

      # Asks for the process to start again with +value+ once it has
      # exited, and, for a fused game, chooses its command from the program
      # the process runs. Raises TypeError, before the game ends, for a
      # value encode cannot write. :nodoc:
      private def request(value)
        pending = encode(value)
        @command = fused_command(Lota::Native::Filesystem.executable_path) if @fused && Lota::Native::Filesystem.open?
        @pending = pending
      end

      # The command that starts a fused game again when +program+ is the
      # program its process runs, as love.cpp's main runs the game again
      # in the program it is (src/love.cpp, main): +program+, with the
      # arguments the game was started with. When +program+ is one of
      # Ruby's own, in Ruby's +bin+ folder, or empty because the system did
      # not name it, the game starts again as remember wrote, through Ruby
      # and the entry script; on macOS and Linux Fledge's <tt>bin/ruby</tt>
      # hands that script to the app's launcher too (Fledge's ADR 026,
      # section 3). :nodoc:
      private def fused_command(program)
        command = @command
        return command if program.empty? || File.identical?(File.dirname(program), RbConfig::CONFIG.fetch("bindir"))

        [program, *@arguments].freeze
      end

      # Replaces the process with the command it was started with, when a
      # restart was requested, as the last of the exit procs: Ruby runs
      # them in the opposite order to the one they were registered in, and
      # Lota registers this as it loads, before its own (lib/lota.rb), so
      # the game's, and Lota's own, have run. The window is closed first, so the
      # new process does not open its window beside it. If the system
      # cannot start the command, says so and exits with status 1.
      #
      # The program goes to exec as a pair of itself and its name, so that
      # it is always one path, even with no arguments after it, as a fused
      # game started with none has. Ruby takes a lone String as a command
      # line instead: on macOS and Linux it splits one with no shell
      # characters at its spaces and runs the first word (Ruby's
      # process.c, rb_exec_fillarg), and on Windows it hands the line to
      # w32_spawn, which takes the program to run as the text before the
      # first space unless the line opens with a quote (win32/win32.c), so
      # an app in a folder such as <tt>My Games</tt> could not start
      # again. :nodoc:
      private def exec_pending
        pending = @pending
        command = @command
        directory = @directory
        return unless pending && command && directory

        program = command.fetch(0)
        arguments = command.drop(1)

        Lota::Native::Window.close if defined?(Lota::Native::Window) && Lota::Native::Window.open?
        $stdout.flush
        $stderr.flush
        Kernel.exec({ VARIABLE => pending }, [program, program], *arguments, chdir: directory)
      rescue SystemCallError => e
        warn "Error: Cannot restart: #{e.message}"
        exit(1)
      end

      # The text encode writes for +value+, inside the tables +outer+.
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

      # Registers exec_pending as an exit proc, once in a process. Lota
      # calls it as it loads, before it registers exit procs of its own,
      # so a restart is the last thing the process does. :nodoc:
      private def install
        return if @installed

        @installed = true
        at_exit { exec_pending }
      end
    end
  end
end
