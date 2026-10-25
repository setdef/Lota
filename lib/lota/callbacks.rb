# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # Calls a game's callbacks, as LÖVE's callbacks.lua does. :nodoc:
  #
  # A game's callbacks are methods it defines on Lota (ADR 003, section
  # 2). Lota calls one only when the game defined it, and passes it only
  # as many of LÖVE's arguments as it declares (section 3), so
  # <tt>def Lota.keypressed(key)</tt> receives the key alone.
  module Callbacks
    # The arguments after the game's folder on the command line, which
    # Lota's loop passes to the load callback first. :nodoc:
    #
    # LÖVE's Lua tables keep the program's own name at negative indices;
    # a Ruby Array has none, so these hold the game's arguments alone.
    @parsed_game_arguments = [] #: Array[String]
    @parsed_game_arguments.freeze

    # Every argument <tt>lota run</tt> received, the game's folder first,
    # which Lota's loop passes to the load callback second. :nodoc:
    @raw_game_arguments = [] #: Array[String]
    @raw_game_arguments.freeze

    class << self
      # The arguments the game's load callback receives first. :nodoc:
      attr_accessor :parsed_game_arguments

      # The arguments the game's load callback receives second. :nodoc:
      attr_accessor :raw_game_arguments
    end

    # Calls the callback +name+ with as many of +arguments+ as it
    # declares, and returns what it returns, or +nil+ when the game did
    # not define it. :nodoc:
    #
    # A callback that takes a splat receives every argument. One that
    # declares more than LÖVE passes raises ArgumentError, as any Ruby
    # method called with too few arguments does.
    def self.call(name, *arguments)
      return unless Lota.respond_to?(name)

      parameters = Lota.method(name).parameters
      unless parameters.any? { |type, _| type == :rest }
        arguments = arguments.first(parameters.count { |type, _| type == :req || type == :opt })
      end
      Lota.public_send(name, *arguments)
    end

    # Event arguments that are names in LÖVE (enum strings), by event and
    # position, so that they reach a callback as symbols (ADR 001, rule
    # 9); the positions are those event/sdl/Event.cpp gives them. Every
    # other String, such as the text of a +textinput+, stays a String.
    # :nodoc:
    ENUM_ARGUMENTS = {
      keypressed: [0, 1],
      keyreleased: [0, 1],
      wheelmoved: [2],
      touchpressed: [6],
      touchreleased: [6],
      touchmoved: [6],
      joystickhat: [2],
      gamepadpressed: [1],
      gamepadreleased: [1],
      gamepadaxis: [1],
      joysticksensorupdated: [1],
      sensorupdated: [0],
      displayrotated: [1],
    }.freeze

    # The next message in the event queue, as its name and an Array of its
    # arguments, or +nil+ when the queue is empty. :nodoc:
    #
    # The message's name becomes a Symbol, as do its arguments that are
    # names in LÖVE (ENUM_ARGUMENTS); the strings SDL gives are UTF-8.
    def self.poll
      message = Native::Event.poll
      return unless message

      name = message.first.to_s.to_sym
      enums = ENUM_ARGUMENTS.fetch(name, [])
      arguments = message.drop(1).map.with_index do |argument, index|
        next argument unless argument.is_a?(String)

        argument = argument.dup.force_encoding(Encoding::UTF_8)
        enums.include?(index) ? argument.to_sym : argument
      end
      [name, arguments]
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Translated from love.createhandlers
    # (vendor/love/src/modules/love/callbacks.lua:27-162). Each handler
    # takes LÖVE's arguments, with nil for any the message lacks and the
    # rest ignored, as a Lua function does. Two of LÖVE's handlers are left
    # out: threaderror, because Lota has no love.thread, and
    # audiodisconnected, because Lota has no love.audio to pick a new
    # playback device with; neither event can arrive without its module.

    # Standard callback handlers. :nodoc:
    HANDLERS = {
      keypressed: -> (b = nil, s = nil, r = nil, *) { Callbacks.call(:keypressed, b, s, r) },
      keyreleased: -> (b = nil, s = nil, *) { Callbacks.call(:keyreleased, b, s) },
      textinput: -> (t = nil, *) { Callbacks.call(:textinput, t) },
      textedited: -> (t = nil, s = nil, l = nil, *) { Callbacks.call(:textedited, t, s, l) },
      mousemoved: -> (x = nil, y = nil, dx = nil, dy = nil, t = nil, *) {
        Callbacks.call(:mousemoved, x, y, dx, dy, t)
      },
      mousepressed: -> (x = nil, y = nil, b = nil, t = nil, c = nil, *) {
        Callbacks.call(:mousepressed, x, y, b, t, c)
      },
      mousereleased: -> (x = nil, y = nil, b = nil, t = nil, c = nil, *) {
        Callbacks.call(:mousereleased, x, y, b, t, c)
      },
      wheelmoved: -> (x = nil, y = nil, px = nil, py = nil, dir = nil, *) {
        Callbacks.call(:wheelmoved, x, y, px, py, dir)
      },
      touchpressed: -> (id = nil, x = nil, y = nil, dx = nil, dy = nil, p = nil, t = nil, m = nil, *) {
        Callbacks.call(:touchpressed, id, x, y, dx, dy, p, t, m)
      },
      touchreleased: -> (id = nil, x = nil, y = nil, dx = nil, dy = nil, p = nil, t = nil, m = nil, *) {
        Callbacks.call(:touchreleased, id, x, y, dx, dy, p, t, m)
      },
      touchmoved: -> (id = nil, x = nil, y = nil, dx = nil, dy = nil, p = nil, t = nil, m = nil, *) {
        Callbacks.call(:touchmoved, id, x, y, dx, dy, p, t, m)
      },
      joystickpressed: -> (j = nil, b = nil, *) { Callbacks.call(:joystickpressed, j, b) },
      joystickreleased: -> (j = nil, b = nil, *) { Callbacks.call(:joystickreleased, j, b) },
      joystickaxis: -> (j = nil, a = nil, v = nil, *) { Callbacks.call(:joystickaxis, j, a, v) },
      joystickhat: -> (j = nil, h = nil, v = nil, *) { Callbacks.call(:joystickhat, j, h, v) },
      gamepadpressed: -> (j = nil, b = nil, *) { Callbacks.call(:gamepadpressed, j, b) },
      gamepadreleased: -> (j = nil, b = nil, *) { Callbacks.call(:gamepadreleased, j, b) },
      gamepadaxis: -> (j = nil, a = nil, v = nil, *) { Callbacks.call(:gamepadaxis, j, a, v) },
      joystickadded: -> (j = nil, *) { Callbacks.call(:joystickadded, j) },
      joystickremoved: -> (j = nil, *) { Callbacks.call(:joystickremoved, j) },
      joysticksensorupdated: -> (j = nil, sensor_type = nil, x = nil, y = nil, z = nil, *) {
        Callbacks.call(:joysticksensorupdated, j, sensor_type, x, y, z)
      },
      focus: -> (f = nil, *) { Callbacks.call(:focus, f) },
      mousefocus: -> (f = nil, *) { Callbacks.call(:mousefocus, f) },
      visible: -> (v = nil, *) { Callbacks.call(:visible, v) },
      exposed: -> (*) { Callbacks.call(:exposed) },
      occluded: -> (*) { Callbacks.call(:occluded) },
      quit: -> (*) {},
      resize: -> (w = nil, h = nil, *) {
        next Callbacks.call(:resize, w, h) if Lota.respond_to?(:resize)

        GC.start
      },
      filedropped: -> (f = nil, x = nil, y = nil, *) { Callbacks.call(:filedropped, f, x, y) },
      directorydropped: -> (dir = nil, x = nil, y = nil, *) { Callbacks.call(:directorydropped, dir, x, y) },
      dropbegan: -> (*) { Callbacks.call(:dropbegan) },
      dropmoved: -> (x = nil, y = nil, *) { Callbacks.call(:dropmoved, x, y) },
      dropcompleted: -> (x = nil, y = nil, *) { Callbacks.call(:dropcompleted, x, y) },
      lowmemory: -> (*) {
        Callbacks.call(:lowmemory)
        GC.start
        GC.start
      },
      displayrotated: -> (display = nil, orient = nil, *) { Callbacks.call(:displayrotated, display, orient) },
      localechanged: -> (*) { Callbacks.call(:localechanged) },
      sensorupdated: -> (sensor_type = nil, x = nil, y = nil, z = nil, *) {
        Callbacks.call(:sensorupdated, sensor_type, x, y, z)
      },
      themechanged: -> (*) { Callbacks.call(:themechanged) },
    }.freeze

    # Handles every queued event, as love.run's event loop does
    # (callbacks.lua:177-187), and returns the exit status when one is a
    # quit the game does not cancel, or +nil+. :nodoc:
    #
    # A quit ends the game when its third argument is truthy (a quit an
    # error screen already confirmed, in LÖVE), when the game has no quit
    # callback, or when the quit callback returns a falsy value; the
    # status is its first argument, or 0.
    def self.dispatch
      while (message = poll)
        name, (a, b, c, d, e, f, g, h) = message
        if name == :quit && (c || !Lota.respond_to?(:quit) || !call(:quit))
          return a || 0
        end

        handle(name, a, b, c, d, e, f, g, h)
      end
      nil
    end

    # Runs the handler for the event +name+ with +arguments+, raising
    # RuntimeError, as LÖVE does, for an event it has no handler for.
    # :nodoc:
    def self.handle(name, *)
      HANDLERS.fetch(name) { raise "Unknown event: #{name}" }.call(*)
    end

    # SPDX-SnippetEnd
  end

  # The callbacks Lota defines itself, as callbacks.lua defines love.run
  # under "Default callbacks" (vendor/love/src/modules/love/callbacks.lua:
  # 164-166).
  #
  # A LÖVE game can replace love.run with a loop of its own. Lota extends
  # itself with this module, so a game's <tt>def Lota.run</tt> takes the
  # place of the one here, without Ruby's warning about a redefined
  # method, and can call it with +super+.
  module DefaultCallbacks
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # Runs the game: Lota's default game loop, translated from love.run
    # (vendor/love/src/modules/love/callbacks.lua:168-206).
    #
    # Lota calls <tt>Lota.run</tt> once, after your main.rb has loaded. It
    # calls your load callback, then returns the frame: a lambda Lota calls
    # again and again until it returns the program's exit status. Each
    # frame pumps the event queue and calls the callback for each event,
    # steps the timer and calls your update callback with the time since
    # the last frame, then, while the window is active, resets the
    # transformation, clears to the background color, calls your draw
    # callback, and shows the result. It sleeps a millisecond at the end of
    # each frame, as LÖVE does, so the game does not spin the processor.
    #
    # A quit event ends the game unless your quit callback returns a truthy
    # value, which keeps it running. The frame then returns the status given
    # to Lota::Event.quit, or 0.
    #
    # Every callback is optional, and each receives as many of LÖVE's
    # arguments as it declares:
    #
    #   load(arguments, raw_arguments)   update(dt)   draw
    #   quit                             keypressed(key, scancode, isrepeat)
    #   keyreleased(key, scancode)       textinput(text)
    #   focus(focused)                   resize(width, height)
    #   visible(visible)                 mousefocus(focused)
    #
    # and the rest of LÖVE's, under LÖVE's names. +load+ receives the
    # arguments after the game's folder on the command line, then every
    # argument <tt>lota run</tt> received.
    #
    # Define <tt>Lota.run</tt> yourself to replace the loop, as a LÖVE game
    # can replace love.run.
    #
    # === Example
    #
    #   # main.rb
    #   def Lota.load(arguments)
    #     @level = arguments.first || "1"
    #   end
    #
    #   def Lota.update(dt)
    #     @time = (@time || 0) + dt
    #   end
    #
    #   def Lota.keypressed(key)
    #     Lota::Event.quit if key == :escape
    #   end
    def run
      Callbacks.call(:load, Callbacks.parsed_game_arguments, Callbacks.raw_game_arguments)

      # We don't want the first frame's dt to include time taken by love.load.
      Timer.step if Native::Timer.open?

      # Main loop time.
      lambda do
        # Process events.
        if Native::Event.open?
          Event.pump
          status = Callbacks.dispatch
          next status if status
        end

        # Update dt, as we'll be passing it to update
        dt = Native::Timer.open? ? Timer.step : 0

        # Call update and draw
        Callbacks.call(:update, dt) # will pass 0 if love.timer is disabled

        if Native::Graphics.open? && Graphics.active?
          Graphics.origin
          Graphics.clear(*Graphics.background_color)

          Callbacks.call(:draw)

          Graphics.present
        end

        Timer.sleep(0.001) if Native::Timer.open?
        nil
      end
    end

    # SPDX-SnippetEnd
  end

  extend DefaultCallbacks
end
