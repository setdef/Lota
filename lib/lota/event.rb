# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The queue of things that happened to the game, translated from
  # love.event.
  #
  # Keys go down, the window gains focus, the player clicks the close
  # button. The operating system reports each of these whenever it likes,
  # while a game wants to hear about them at one point in each frame.
  #
  # Lota::Event keeps them in a queue. Lota's game loop pumps the queue
  # once a frame and calls your callbacks for what it finds, such as
  # +keypressed+ or +quit+.
  #
  # Use it to end the game, or to pump and poll the queue yourself.
  #
  # === Examples
  #
  #   def Lota.keypressed(key)
  #     Lota::Event.quit if key == :escape
  #   end
  #
  #   # Quit with a status for the shell.
  #   Lota::Event.quit(2)
  module Event
    # Gathers what the operating system has reported into the queue,
    # matching love.event.pump (src/modules/event/wrap_Event.cpp, w_pump).
    #
    # [wait_timeout] Float or Integer, the seconds to wait for the first
    #   event when none has arrived; 0, the default, does not wait, and a
    #   negative or infinite timeout waits for good.
    #
    # Lota's loop pumps once a frame. Pumping while a canvas is the target
    # raises RuntimeError, because some systems draw the window during the
    # pump. Raises RuntimeError when the event module is not open.
    #
    # === Example
    #
    #   Lota::Event.pump
    def self.pump(wait_timeout = 0)
      Native::Event.pump(wait_timeout)
    end

    # The messages waiting in the queue, each as its name and its
    # arguments, matching love.event.poll (src/modules/event/wrap_Event.lua
    # and wrap_Event.cpp, w_poll_i).
    #
    # In LÖVE, poll returns an iterator for Lua's +for+; in Lota it returns
    # an Enumerator, or with a block calls the block for each message
    # (ADR 001, rule 15). Each step takes the next message out of the
    # queue, as LÖVE's iterator does, until the queue is empty, so a
    # message is seen once, by whichever loop takes it first; pump the
    # queue first to gather what the system has reported. A message's name
    # is a Symbol, as are its arguments that are names in LÖVE, such as a
    # key (rule 9), and numbers LÖVE's C++ holds as integers are Integers
    # (rule 14). With a block, it returns +nil+.
    #
    # Lota's loop polls the queue once a frame and calls your callbacks
    # for what it finds, so a game that polls it itself takes those
    # messages from the loop.
    #
    # === Examples
    #
    #   Lota::Event.pump
    #   Lota::Event.poll do |name, *arguments|
    #     puts "#{name} #{arguments.inspect}"
    #   end
    #
    #   name, key = Lota::Event.poll.next
    def self.poll
      return enum_for(:poll) unless block_given?

      while (message = Callbacks.poll)
        name, arguments = message
        yield name, *arguments
      end
      nil
    end

    # Adds a message to the queue, matching love.event.push
    # (src/modules/event/wrap_Event.cpp, w_push, which reads each argument
    # with luax_checkvariant).
    #
    # [name] Symbol or String name of the message. Lota's loop calls the
    #   callback of that name; a name LÖVE has no callback for raises
    #   RuntimeError there (<tt>"Unknown event: name"</tt>), as in LÖVE.
    # [arguments] The message's arguments: +true+, +false+, numbers, and
    #   Strings, or Symbols, which become their names. They end at the
    #   first +nil+, as LÖVE stops reading there.
    #
    # A number comes back from the queue as a Float, as LÖVE keeps every
    # number in a message as a double. Returns +true+. Raises
    # ArgumentError, with LÖVE's message, for any other argument; LÖVE also
    # passes its own objects, which Lota does not pass through the queue
    # yet. Raises RuntimeError when the event module is not open.
    #
    # === Example
    #
    #   Lota::Event.push(:keypressed, :space, :space, false)
    def self.push(name, *arguments)
      values = [] #: Array[bool | Float | String]
      arguments.each.with_index(2) do |argument, position|
        case argument
        when nil then break
        when true, false, String then values << argument
        when Symbol then values << argument.name
        when Integer, Float then values << argument.to_f
        else
          raise ArgumentError,
            "Argument #{position} can't be stored safely\nExpected boolean, number, string or userdata."
        end
      end
      Native::Event.push(EnumName.of(name), values)
    end

    # Empties the queue, matching love.event.clear
    # (src/modules/event/wrap_Event.cpp, w_clear), and returns +nil+.
    #
    # Pumping while a canvas is the target raises RuntimeError, as pump
    # does. Raises RuntimeError when the event module is not open.
    #
    # === Example
    #
    #   Lota::Event.clear
    def self.clear
      Native::Event.clear
    end

    # Asks the game to quit, matching love.event.quit
    # (src/modules/event/wrap_Event.cpp, w_quit).
    #
    # [exit_status] Integer the program exits with; 0 when +nil+ or left
    #   out.
    #
    # The request joins the queue. On the next frame the loop calls your
    # +quit+ callback, which can return a truthy value to keep the game
    # running, as LÖVE's love.quit can. The status leaves the queue as an
    # Integer, as LÖVE's C++ holds an exit status (love.cpp, runlove), so
    # <tt>quit(3)</tt> exits with 3 (ADR 001, rule 14). Returns +true+.
    # LÖVE also takes <tt>"restart"</tt> to start the game again; Lota
    # does not restart games yet.
    #
    # === Example
    #
    #   Lota::Event.quit     # exits with 0
    #   Lota::Event.quit(1)  # exits with 1
    def self.quit(exit_status = nil)
      Native::Event.quit(exit_status&.to_f)
    end
  end
end
