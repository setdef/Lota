# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

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
  # Only <tt>lota run</tt> remembers the command, so a game started in
  # any other way, such as by Lota::Boot in your own program, ends when it
  # restarts, as a quit ends it. Ruby's own flags are not remembered but
  # +-w+ and +-W0+; the ones that matter to a game belong in +RUBYOPT+,
  # which the new process inherits with the rest of the environment.
  #
  # The restart value crosses in an environment variable, Restart::VARIABLE,
  # which the new process reads once and removes. It holds a type, a colon,
  # and the value (<tt>nil:</tt>, <tt>boolean:true</tt>, or
  # <tt>number:</tt> and <tt>string:</tt> followed by hexadecimal digits),
  # and nothing in it is evaluated: +nil+, +true+, +false+, a number, or a
  # String, which are what the event queue carries. Anything else in the
  # variable is ignored. Environment variables are
  # limited in size, so a String of more than about 100 kilobytes cannot
  # cross on every system.
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

    # Rejects what the event queue cannot carry. :nodoc:
    class Unsupported < TypeError; end

    @value = nil
    @taken = false
    @command = nil
    @directory = nil
    @pending = nil

    class << self
      # The value the game that restarted chose, or +nil+ when the game
      # was not started by a restart. Lota.restart returns it. :nodoc:
      attr_reader :value

      # Writes +value+ for the environment: its type, a colon, and its
      # value, with numbers as the hexadecimal digits of their eight bytes
      # and Strings as those of their bytes, so that every number and every
      # String, valid UTF-8 or not, arrives as it left. Integers become
      # Floats, as the queue makes them, and Symbols Strings. Raises
      # TypeError for anything else. :nodoc:
      def encode(value)
        case value
        when nil then "nil:"
        when true, false then "boolean:#{value}"
        when Integer, Float then "number:#{[value.to_f].pack('G').unpack1('H*')}"
        when String then "string:#{value.b.unpack1('H*')}"
        when Symbol then "string:#{value.name.b.unpack1('H*')}"
        else raise Unsupported, "can't restart with a #{value.class}: only nil, booleans, numbers and strings cross"
        end
      end

      # The value +text+ holds, which encode wrote. Raises ArgumentError
      # for anything else, however it is shaped. :nodoc:
      def decode(text)
        tag, content = text.split(":", 2)
        case [tag, content]
        in ["nil", ""] then nil
        in ["boolean", "true"] then true
        in ["boolean", "false"] then false
        in ["number", /\A\h{16}\z/] then [content].pack("H*").unpack1("G")
        in ["string", /\A(\h\h)*\z/] then [content].pack("H*").force_encoding(Encoding::UTF_8)
        else raise ArgumentError, "not a restart value"
        end
      end

      # Reads the restart value the previous run left in +environment+,
      # once: the variable is removed whatever it holds, and a value that
      # is not one encode wrote is dropped. Only the first call in a
      # process reads. :nodoc:
      def take(environment = ENV)
        return if @taken

        @taken = true
        text = environment.delete(VARIABLE)
        @value = text && decode(text)
      rescue ArgumentError
        @value = nil
      end

      # Remembers how <tt>lota run</tt> was started, to start it again
      # (Process.argv0, the interpreter, and the working directory), and
      # makes sure a restart is the last thing the process does. +arguments+
      # are the command line's arguments after the script. A script Ruby
      # cannot start again, such as <tt>-e</tt>'s, is not remembered. :nodoc:
      def remember(arguments)
        script = File.expand_path(Process.argv0)
        return unless File.file?(script)

        flag = { true => "-w", nil => "-W0" }[$VERBOSE]
        @command = [RbConfig.ruby, *flag, script, *arguments].freeze
        @directory = Dir.pwd
        install
      end

      # Whether the game can restart: whether the command was remembered.
      # :nodoc:
      def restartable?
        !@command.nil?
      end

      # Asks for the process to start again with +value+ once it has
      # exited. Raises TypeError, before the game ends, for a value
      # encode cannot write. :nodoc:
      def request(value)
        @pending = encode(value)
      end

      # Replaces the process with the command it was started with, when a
      # restart was requested, as the last of the exit procs: Ruby runs
      # them in the opposite order to the one they were registered in, and
      # lota run registers this before it loads Lota, so the game's, and
      # Lota's own, have run. The window is closed first, so the
      # new process does not open its window beside it. If the system
      # cannot start the command, says so and exits with status 1. :nodoc:
      def exec_pending
        pending = @pending
        command = @command
        directory = @directory
        return unless pending && command && directory

        interpreter = command.fetch(0)
        arguments = command.drop(1)

        Lota::Native::Window.close if defined?(Lota::Native::Window) && Lota::Native::Window.open?
        $stdout.flush
        $stderr.flush
        Kernel.exec({ VARIABLE => pending }, interpreter, *arguments, chdir: directory)
      rescue SystemCallError => e
        warn "Error: Cannot restart: #{e.message}"
        exit(1)
      end

      private def install
        return if @installed

        @installed = true
        at_exit { exec_pending }
      end
    end
  end
end
