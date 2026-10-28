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
  # <tt>def Lota.keypressed(key)</tt> receives the key alone; a required
  # parameter beyond LÖVE's receives +nil+, as in Lua, and an optional one
  # keeps its default.
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
    # A callback that takes a splat receives every argument. A required
    # parameter LÖVE does not pass receives +nil+, as a Lua function
    # receives nil for arguments its caller left out (ADR 003, section 3).
    # An optional parameter LÖVE does not pass keeps its default: Lua has
    # no defaults, so one is the game's own Ruby, which Lota leaves alone.
    # LÖVE passes no keywords, so a keyword parameter keeps its default,
    # and a required one raises ArgumentError, as Ruby does for any call
    # that leaves it out.
    def self.call(name, *arguments)
      return unless Lota.respond_to?(name)

      Lota.public_send(name, *declared(Lota.method(name).parameters, arguments))
    end

    # The parameters +callable+ declares, as Method#parameters gives them:
    # a Proc's or a Method's own, or those of the +call+ method of any
    # other object that answers +call+. :nodoc:
    def self.parameters(callable)
      case callable
      when Proc, Method then callable.parameters
      else callable.method(:call).parameters
      end
    end

    # As many of +arguments+ as +parameters+ declare, as #call passes a
    # game's callback (ADR 003, section 3): every one to a splat, +nil+
    # for each required parameter beyond them, and none for an optional
    # parameter beyond them, which keeps its default. A Proc that is not a
    # lambda declares each of its parameters optional, and so receives as
    # many as it names. :nodoc:
    def self.declared(parameters, arguments)
      types = parameters.map(&:first)
      required = types.count(:req)
      accepted = types.include?(:rest) ? [arguments.size, required].max : required + types.count(:opt)
      count = arguments.size.clamp(required, accepted)
      Array.new(count) { |index| arguments[index] }
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

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Event arguments LÖVE's C++ holds as integers, by event and position,
    # so that they reach a callback as Integers (ADR 001, rule 14). LÖVE
    # passes every number through its Variant as a double; these are the
    # ones event/sdl/Event.cpp casts to double from an integer: a text
    # edit's start and length (SDL's Sint32, lines 326-327), a mouse
    # button as LÖVE numbers it and its click count (int and Uint8, lines
    # 358-379), a joystick's button, axis, and hat, counting from 1 (Uint8
    # plus 1, lines 645, 657, and 672), and a rotated display's index,
    # counting from 1 (line 507). A window's new size is the graphics
    # module's int width and height (lines 811-835), while that module is
    # open (argument). A quit's first argument is the program's exit
    # status, which love.cpp's runlove holds as an int
    # (vendor/love/src/love.cpp:282-283). Every other number, such as a
    # position, a wheel's travel, or an axis's value, is a float in SDL or
    # in LÖVE and stays a Float. :nodoc:
    INTEGER_ARGUMENTS = {
      textedited: [1, 2],
      mousepressed: [2, 4],
      mousereleased: [2, 4],
      joystickpressed: [1],
      joystickreleased: [1],
      joystickaxis: [1],
      joystickhat: [1],
      displayrotated: [0],
      resize: [0, 1],
      quit: [0],
    }.freeze

    # SPDX-SnippetEnd

    # The next message in the event queue, as its name and an Array of its
    # arguments, or +nil+ when the queue is empty. :nodoc:
    #
    # The message's name becomes a Symbol, as do its arguments that are
    # names in LÖVE (ENUM_ARGUMENTS); the strings SDL gives are UTF-8.
    # Numbers LÖVE holds as integers (INTEGER_ARGUMENTS) become Integers,
    # and the rest stay Floats.
    def self.poll
      message = Native::Event.poll
      return unless message

      name = message.first.to_s.to_sym
      arguments = message.drop(1).map.with_index { |argument, index| argument(name, index, argument) }
      [name, arguments]
    end

    # The argument at +index+ of the event +name+, as Ruby sees it.
    # :nodoc:
    #
    # Without the graphics module, LÖVE's resize gives the window's size in
    # DPI-scaled units, which it computes as doubles
    # (event/sdl/Event.cpp:826-832), so a resize's size is an Integer
    # only while Lota::Graphics is open.
    def self.argument(name, index, argument)
      case argument
      when String
        argument = argument.dup.force_encoding(Encoding::UTF_8)
        ENUM_ARGUMENTS.fetch(name, []).include?(index) ? argument.to_sym : argument
      when Float
        integer = INTEGER_ARGUMENTS.fetch(name, []).include?(index)
        integer &&= Native::Graphics.open? if name == :resize
        integer ? argument.to_i : argument
      else
        argument
      end
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
      Event.poll do |name, a, b, c, d, e, f, g, h|
        if name == :quit && (c || !Lota.respond_to?(:quit) || !call(:quit))
          return a || 0
        end

        handle(name, a, b, c, d, e, f, g, h)
      end
    end

    # Runs the handler for the event +name+ with +arguments+, raising
    # RuntimeError, as LÖVE does, for an event it has no handler for.
    # :nodoc:
    def self.handle(name, *)
      HANDLERS.fetch(name) { raise "Unknown event: #{name}" }.call(*)
    end

    # SPDX-SnippetEnd

    # The errors a game's code raises that Lota's error handler takes, as
    # Lua's xpcall takes every error: the StandardError and ScriptError a
    # program's mistakes raise (a SyntaxError in main.rb among them), and
    # SystemStackError, Ruby's stack overflow. SystemExit, Interrupt, and
    # Ruby's other signals pass through to end the program, as Ruby ends it.
    # :nodoc:
    ERRORS = [StandardError, ScriptError, SystemStackError].freeze

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # The text of +error+, as Lua's tostring gives an error's message
    # (callbacks.lua:222). A Lua error's message starts with where it was
    # raised ("main.lua:3: boom"); a Ruby exception's text, as Ruby prints
    # one it does not rescue, is where it was raised and its detailed
    # message ("main.rb:3:in 'Lota.update': boom (RuntimeError)"). Anything
    # else a game passes an error handler is its +to_s+. :nodoc:
    def self.error_message(error)
      return error.to_s unless error.is_a?(Exception)

      message = error.detailed_message(highlight: false)
      location = error.backtrace&.first
      location ? "#{location}: #{message}" : message
    end

    # The Ruby counterpart of Lua's debug.traceback for +frames+, the
    # backtrace of an exception, or of where the error handler was called
    # for anything else: "stack traceback:" and a line for each frame,
    # starting with a tab, as debug.traceback lays them out. :nodoc:
    def self.traceback(frames)
      ["stack traceback:", *frames.map { |frame| "\t#{frame}" }].join("\n")
    end

    # Prints +error+ and its traceback, as error_printer does
    # (callbacks.lua:217-219, and boot.lua:462-464, its copy): "Error: ",
    # the error's text, and its traceback without the outermost frame,
    # which error_printer drops. +frames+ is the traceback's frames.
    # :nodoc:
    def self.error_printer(error, frames = error.is_a?(Exception) ? error.backtrace.to_a : caller)
      puts "Error: #{error_message(error)}\n#{traceback(frames)}".sub(/\n[^\n]+\z/, "")
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
    # arguments as it declares; a required parameter beyond them receives
    # +nil+, as in Lua, and an optional one keeps its default. Numbers LÖVE holds as integers, such as a
    # mouse button or a resized window's width, are Integers; the rest,
    # such as positions and +dt+, are Floats:
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

    # Shows LÖVE's error screen for +msg+, an error your game raised, and
    # returns the screen's frame: Lota's default error handler, translated
    # from love.errorhandler (vendor/love/src/modules/love/callbacks.lua:
    # 221-349).
    #
    # When your game raises, Lota calls <tt>Lota.errorhandler</tt> with
    # what it raised, as LÖVE calls love.errorhandler (ADR 003, section 7).
    # This one prints the error and its backtrace, then, in the game's
    # window, opening one at 800 by 600 if the game has none, puts the
    # mouse and the drawing state back as they start and shows the error
    # in white, in LÖVE's default font at 15 pixels, on LÖVE's blue: the
    # word "Error", the error's text, and its backtrace under
    # "Traceback", without the frames of Lota's boot.rb, as LÖVE leaves out
    # those of its boot.lua. Where LÖVE shows a Lua traceback, Lota shows
    # Ruby's backtrace. When no window can open it shows the error in a
    # message box instead and returns +nil+, and without the window module
    # it only prints.
    #
    # The frame it returns pumps and polls the event queue, as the frames
    # of Lota.run do, until the player quits, which exits with the quit's
    # status or 1, or presses Escape, which exits with 1. Ctrl+C copies the
    # error and its backtrace to the clipboard, and a touch asks whether
    # to quit in a message box with a button that copies them. A string
    # +msg+ is shown as given, with the backtrace of where the handler was
    # called.
    #
    # Define <tt>Lota.errorhandler</tt> yourself to replace it, as a LÖVE
    # game can replace love.errorhandler: receive the error, and return a
    # frame for Lota to call until it returns an exit status, or +nil+ to
    # exit with 1. An error your handler raises is printed, and the
    # program exits with 1.
    #
    # === Example
    #
    #   def Lota.errorhandler(error)
    #     File.write("crash.log", error.full_message(highlight: false))
    #     super
    #   end
    def errorhandler(msg)
      frames = msg.is_a?(Exception) ? msg.backtrace.to_a : caller
      error = msg
      msg = Callbacks.error_message(msg)

      Callbacks.error_printer(error, frames)

      return unless Native::Window.open?

      if !Native::Graphics.open? || !Native::Event.open? || !Graphics.created? || !Window.open?
        success = status = nil
        if Native::Graphics.open? && Native::Event.open?
          success, status = begin
            [true, Window.set_mode(800, 600)]
          rescue *Callbacks::ERRORS
            [false, nil]
          end
        end
        unless success && status
          Native::Window.show_message_box("Initialization error", msg, "error", false)
          return
        end
      end

      # Reset state.
      if Native::Mouse.open?
        Mouse.visible = true
        Mouse.grabbed = false
        Mouse.set_relative_mode(false)
        Mouse.cursor = nil if Mouse.cursor_supported?
      end
      # LÖVE also stops every joystick's vibration and all audio here
      # (lines 250-256); Lota has no love.joystick or love.audio yet.

      Graphics.reset
      Graphics.font = Graphics::Font.new(15)

      Graphics.color = 1, 1, 1

      trace = Callbacks.traceback(frames)

      Graphics.origin

      sanitizedmsg = msg.b.scan(/[\x00-\x7F\xC2-\xFD][\x80-\xBF]*/n).join.force_encoding(Encoding::UTF_8)

      err = [] #: Array[String]

      err << "Error\n"
      err << sanitizedmsg

      err << "Invalid UTF-8 string in error message." if sanitizedmsg.bytesize != msg.bytesize

      err << "\n"

      trace.each_line(chomp: true) do |l|
        next if l.empty? || l.match?(/boot.rb/)

        err << l.sub("stack traceback:", "Traceback\n")
      end

      p = err.join("\n")

      p = p.delete("\t")
      # LÖVE also unwraps the names Lua gives code loaded from a string
      # ([string "name"]), which Ruby's backtraces do not have.

      draw = lambda do
        next unless Graphics.active?

        pos = 60
        Graphics.clear(89 / 255.0, 157 / 255.0, 220 / 255.0)
        Graphics.printf(p, pos, pos, Graphics.width - pos)
        Graphics.present
      end

      full_error_text = p
      copy_to_clipboard = lambda do
        next unless Native::System.open?

        System.clipboard_text = full_error_text
        p += "\nCopied to clipboard!"
      end

      p += "\n\nPress Ctrl+C or tap to copy this error" if Native::System.open?

      lambda do
        Event.pump(0.1)

        # Lua returns from inside its for loop; a Ruby block breaks out of
        # Event.poll with the status instead, which the frame returns.
        status = Event.poll do |e, a, _b, _c|
          if e == :quit
            # LÖVE also passes on a restart's arguments, and Lota does not
            # restart games yet.
            break a || 1
          elsif e == :keypressed && a == :escape
            break 1
          elsif e == :keypressed && a == :c && Keyboard.down?(:lctrl, :rctrl)
            copy_to_clipboard.call
          elsif e == :touchpressed
            name = Window.title
            name = "Game" if name.empty? || name == "Untitled"
            buttons = ["OK", "Cancel"]
            buttons[2] = "Copy to clipboard" if Native::System.open?
            pressed = Native::Window.show_message_box_with_buttons("Quit #{name}?", "", buttons)
            if pressed == 1
              break 1
            elsif pressed == 3
              copy_to_clipboard.call
            end
          end
        end
        next status if status

        draw.call

        Timer.sleep(0.001) if Native::Timer.open?
        nil
      end
    end

    # Legacy code support: LÖVE keeps love.errhand as another name for
    # love.errorhandler (callbacks.lua:351-352), and boot.lua calls
    # love.errorhandler, or love.errhand only when a game has removed
    # love.errorhandler (boot.lua:476). So does Lota: a game that defines
    # only <tt>Lota.errhand</tt> keeps this default handler, as a LÖVE 12
    # game that defines only love.errhand does.
    alias errhand errorhandler

    # SPDX-SnippetEnd
  end

  extend DefaultCallbacks
end
