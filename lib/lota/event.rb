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
    # passes tables and its own objects, which Lota does not pass through
    # the queue yet. Raises RuntimeError when the event module is not
    # open.
    #
    # === Example
    #
    #   Lota::Event.push(:keypressed, :space, :space, false)
    def self.push(name, *arguments)
      Native::Event.push(EnumName.of(name), variants(arguments))
    end

    # Waits for the next message and returns it, matching love.event.wait
    # (src/modules/event/wrap_Event.cpp, w_wait), which LÖVE has
    # deprecated in favor of the +wait_timeout+ of #pump. The first use
    # prints LÖVE's notice (Lota::Deprecation), word for word but for the
    # function names ADR 001, section 7, rewrites.
    #
    # It returns the message's name and arguments as one Array (ADR 001,
    # rule 4), as #poll yields them, or +nil+ when what arrives is nothing
    # LÖVE passes on. Unlike #poll it waits for what the operating system
    # reports, not for what is already in the queue, so it blocks the game
    # until something happens. Waiting while a canvas is the target raises
    # RuntimeError, as pump does. Raises RuntimeError when the event
    # module is not open.
    #
    # === Example
    #
    #   name, *arguments = Lota::Event.wait
    def self.wait
      Deprecation.mark("Lota::Event.wait", :function, :replaced, "waitTimeout parameter in Lota::Event.pump",
        where: Deprecation.where(caller_locations(1, 1)))
      message = Callbacks.message(Native::Event.wait)
      message && [message.first, *message.last]
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

    # Asks the game to quit and start again, matching love.event.restart
    # (src/modules/event/wrap_Event.cpp, w_restart): the same as #quit
    # with <tt>"restart"</tt> as its first argument, followed by
    # +arguments+.
    #
    # [arguments] Every argument, +nil+ included, as LÖVE reads each of
    #   them (luax_checkvariant): +nil+, +true+, +false+, numbers, which
    #   leave the queue as Floats, Strings, and Symbols, which become their
    #   names. A Proc or a Method, Ruby's function, is kept as LÖVE keeps a
    #   function, as a value that carries nothing, and leaves the queue as
    #   +nil+.
    #
    # Lota does not restart games yet, so a game that restarts ends, as
    # one that quits with status 0 does, after the +quit+ callback has had
    # its say. Returns +true+. LÖVE also carries tables and its own
    # objects, which Lota does not put in a message yet: raises TypeError
    # for a Hash, an Array, a Lota::Object, or any other value. Raises
    # RuntimeError when the event module is not open.
    #
    # === Example
    #
    #   Lota::Event.restart
    def self.restart(*arguments)
      Native::Event.restart(arguments)
    end

    # Sets the callable the operating system's own loop draws the window
    # with, matching love.event.setModalDrawCallback
    # (src/modules/event/wrap_Event.cpp, w_setModalDrawCallback), which
    # ADR 001's rule 5 makes a writer and its rule 12 lets take any object
    # that answers +call+.
    #
    # [callable] Anything that answers +call+ with no arguments, or +nil+
    #   for none.
    #
    # While the system resizes the window, on macOS and Windows, it does
    # not return to the game, so nothing draws until the player lets go.
    # The event module calls this instead, during the system's loop, and
    # LÖVE's own game loop passes its frame to it. What the callable
    # returns, an exit status or an Array of it and a restart value, as
    # the frame of Lota.run returns them, ends the game as a +quit+
    # message would. Each is read as #restart reads its arguments. An
    # error it raises, a value #restart would refuse, or a +throw+ out of
    # it comes out of the next #pump as RuntimeError, its message after
    # <tt>"Error in modal draw callback: "</tt>, as LÖVE turns every error
    # of the callback into one. Raises TypeError for a value that does not
    # answer +call+, and RuntimeError when the event module is not open.
    #
    # === Example
    #
    #   Lota::Event.modal_draw_callback = -> { Lota::Graphics.present; nil }
    def self.modal_draw_callback=(callable)
      unless callable.nil? || callable.respond_to?(:call)
        raise TypeError, "wrong argument type #{callable.class} (expected a callable)"
      end

      Native::Event.set_modal_draw_callback(callable)
    end

    # The values of a message's +arguments+ as the engine stores them: up
    # to the first +nil+, as LÖVE stops reading there, with numbers as
    # Floats and Symbols as their names. :nodoc:
    private_class_method def self.variants(arguments)
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
      values
    end
  end
end
