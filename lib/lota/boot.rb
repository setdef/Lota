# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # Starts a game from its folder, as LÖVE's boot.lua starts one.
  #
  # A game is a folder holding conf.rb and main.rb (ADR 003). Before its
  # code runs, something has to read its settings, open the modules it
  # wants, and open its window, in the order LÖVE does them, or a game
  # that works in LÖVE breaks in Lota.
  #
  # Boot does that. <tt>lota run</tt> makes one for the folder you name
  # and calls it: it builds the settings, loads conf.rb and calls
  # <tt>Lota.conf</tt>, opens the modules, opens the window, loads main.rb,
  # and runs <tt>Lota.run</tt>'s loop until the game quits.
  #
  # Use it through <tt>lota run</tt>. Tests that draw use init alone, to
  # open a window from a conf.rb.
  #
  # An error in the game shows LÖVE's error screen in the game's window,
  # with Ruby's backtrace, as LÖVE's love.errorhandler does, or whatever
  # the game's own <tt>Lota.errorhandler</tt> shows (ADR 003, section 7).
  #
  # === Examples
  #
  #   # What lota run path/to/game level2 does.
  #   exit Lota::Boot.new("path/to/game", ["level2"]).call
  #
  #   # Open the window a game's conf.rb asks for, without running it.
  #   Lota::Boot.new("path/to/game").init
  class Boot
    # The modules boot.lua opens, in its order (boot.lua:348-368), each
    # paired with how Lota opens it, or +nil+ for one Lota does not have
    # yet. :nodoc:
    MODULES = {
      data: nil,
      thread: nil,
      timer: -> { Native::Timer.open },
      event: -> { Native::Event.open },
      keyboard: -> { Native::Keyboard.open },
      joystick: nil,
      mouse: -> { Native::Mouse.open },
      touch: nil,
      sound: -> { Native::Sound.open },
      system: -> { Native::System.open },
      sensor: nil,
      audio: -> { Native::Audio.open.each { |line| puts line } },
      image: -> { Native::Image.open },
      video: nil,
      font: -> { Native::Font.open },
      window: -> { Native::Window.open },
      graphics: -> { Native::Graphics.open },
      math: -> { Native::Math.open },
      physics: -> { Native::Physics.open },
    }.freeze

    # The game's folder, as an absolute path.
    attr_reader :directory

    # The Lota::Settings conf.rb changed, once configure has run.
    attr_reader :settings

    # Prepares to start the game in the folder +path+.
    #
    # [path] String path of the game's folder, as given on the command
    #   line, or +nil+ for the current directory.
    # [arguments] Array of String arguments for the game, which its load
    #   callback receives.
    # [fused] Whether the game is fused into an application of its own, as
    #   a shipped game is, which LÖVE's boot.lua decides from where it
    #   found the game (boot.lua:76-96) and Lota from who starts it:
    #   <tt>lota run</tt> leaves it +false+, and ADR 002's launcher, which
    #   ships a game, is to pass +true+. A fused game saves in the
    #   system's application data folder under its identity alone, where
    #   LÖVE's fused games save; one that is not saves in a +Lota+ folder
    #   there (ADR 003, section 8). Only the first Boot in a process sets
    #   it, as LÖVE sets it once (Lota::Filesystem.fused=).
    #
    # === Examples
    #
    #   Lota::Boot.new("games/pong", ["--two-players"])
    #   Lota::Boot.new("Pong.app/Contents/Resources/game", fused: true)
    def initialize(path, arguments = [], fused: false)
      @path = path
      @directory = File.expand_path(path || ".")
      @arguments = arguments
      @fused = fused
      @settings = Settings.new
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Translated from vendor/love/src/modules/love/boot.lua, as cited on
    # each method.

    # Runs the game until it quits, and returns the program's exit status,
    # as boot.lua's root function (lines 470-521) runs love.boot,
    # love.init, and love.run's frame, with LÖVE's error handling.
    #
    # An error in booting the engine prints its error and returns 1. An
    # error your game raises from conf.rb onward goes to
    # <tt>Lota.errorhandler</tt>, whose frame then runs in place of the
    # game's until it returns a status, or the program exits with 1 when
    # the handler returns +nil+. An error in the error handler itself is
    # printed, and the program exits with 1.
    #
    # Lota drains its release queue after every frame, so that graphics
    # objects Ruby's garbage collector freed on another thread are released
    # on the main thread (ADR 001, section 5). A frame that returns an
    # Integer or Float exits with it; any other truthy value exits with 0,
    # as LÖVE's love.cpp treats a value that is not a number. LÖVE also
    # hands each new frame to the event module, to draw while the system
    # holds the window modal (lines 511-514); Lota does not bind that yet.
    #
    # === Example
    #
    #   status = Lota::Boot.new("games/pong").call
    def call
      Callbacks.parsed_game_arguments = @arguments.dup.freeze
      Callbacks.raw_game_arguments = [@path, *@arguments].compact.freeze
      @inerror = false
      @func = method(:earlyinit)

      while (func = @func)
        _, retval = protect { func.call }
        Native.drain_release_queue
        return (retval.is_a?(Integer) || retval.is_a?(Float)) ? retval.to_i : 0 if retval
      end

      1
    end

    # Brings the game up to the point where its loop starts, as love.boot
    # and love.init do (boot.lua:43-456): puts the game's folder on
    # <tt>$LOAD_PATH</tt>, configures the game, opens its modules and its
    # window, and loads main.rb.
    #
    # An error in conf.rb waits until the modules are open, as in LÖVE,
    # whose error screen needs the window. Raises RuntimeError
    # (<tt>"Could not set window mode"</tt>) when the system refuses the
    # window, and RuntimeError when the folder holds neither main.rb nor
    # conf.rb. It raises what the game raises, and shows no error screen,
    # which call shows.
    #
    # === Example
    #
    #   Lota::Boot.new("games/pong").init
    #   Lota::Graphics.dimensions # => [800, 600]
    def init
      boot
      init_game
    end

    # The part of starting up that is love.boot's (boot.lua:43-173): puts
    # the game's folder on <tt>$LOAD_PATH</tt>, and opens the filesystem
    # and the system module, which LÖVE opens before conf.lua whatever the
    # settings say (boot.lua:44-49).
    private def boot
      add_to_load_path
      open_filesystem
      Native::System.open
    end

    # The part of starting up that is love.init's (boot.lua:175-456):
    # configures the game, opens its modules and its window, and loads
    # main.rb.
    private def init_game
      conf_error = configure
      prepare_engine
      open_modules
      check_version

      raise conf_error if conf_error

      open_window

      # The first couple event pumps on some systems (e.g. macOS) can take a
      # while. We'd rather hit that slowdown here than in event processing
      # within the first frames.
      2.times { Event.pump } if Native::Event.open?

      # Our first timestep, because window creation can take some time
      Timer.step if Native::Timer.open?

      # boot.lua also passes t.externalstorage on (line 441), which
      # matters only on Android.
      Filesystem.identity = [@settings.identity || Filesystem.identity, @settings.appendidentity]
      require main_file if File.exist?(main_file)
      return unless no_game_code?

      gamestr = @path.nil? ? "" : " at #{@path}"
      raise "No code to run#{gamestr}\nYour game might be packaged incorrectly.\n" \
        "Make sure main.rb is at the top level of the zip or folder."
    end

    # The first frame boot.lua's root function runs (earlyinit, lines
    # 483-505): boots, initializes, and runs the game, and makes the frame
    # Lota.run returns the next to run. An error in booting prints and
    # returns 1; an error after it goes to the error handler, whose frame
    # runs next.
    private def earlyinit
      @func = nil

      # If boot fails, return 1 and finish immediately
      begin
        boot
      rescue *Callbacks::ERRORS => e
        Callbacks.error_printer(e)
        return 1
      end

      # If init or run fails, don't return a value,
      # as we want the error handler to take over
      result, = protect { init_game }
      return unless result

      # NOTE: We can't assign to @func directly, as we'd
      # overwrite the result of handle_error with nil on error
      result, main = protect { Lota.run }
      @func = main if result
      # boot.lua prints an error raised in the error handler here (lines
      # 502-503), when Lua could not call deferErrhand for it; handle_error
      # has always printed it already.
      nil
    end

    # Runs the block as boot.lua runs a function with xpcall and
    # deferErrhand (lines 492, 498, and 515), and returns +true+ and the
    # block's value, or +false+ once the error handler has taken what it
    # raised.
    private def protect
      [true, yield]
    rescue *Callbacks::ERRORS => e
      handle_error(e)
      [false, nil]
    end

    # deferErrhand (boot.lua:475-481): hands +error+ to the game's error
    # handler, <tt>Lota.errorhandler</tt> or, when the game has removed it,
    # <tt>Lota.errhand</tt>, and makes the frame it returns the next to
    # run. While handling an error, the error printer takes its place, so
    # an error the handler raises is printed, as Lua calls deferErrhand
    # again for it with inerror set, and the game ends.
    private def handle_error(error)
      errhand = %i[errorhandler errhand].find { |name| Lota.respond_to?(name) }
      handler = !@inerror && errhand
      @inerror = true
      @func = handler ? Callbacks.call(handler, error) : Callbacks.error_printer(error) #: _Frame?
      @inerror = false
    rescue *Callbacks::ERRORS => e
      handle_error(e)
    end

    # Builds the settings and lets the game change them, as love.init does
    # (boot.lua:175-259): loads conf.rb when the game has not defined
    # <tt>Lota.conf</tt> already, then calls <tt>Lota.conf</tt> with the
    # settings if it is defined.
    #
    # Returns the error conf.rb or <tt>Lota.conf</tt> raised, or +nil+,
    # rather than raising it: LÖVE raises it only once the modules are
    # open (init).
    #
    # === Example
    #
    #   boot = Lota::Boot.new("games/pong")
    #   boot.configure # => nil
    #   boot.settings.window.width # => 1280
    def configure
      @settings = Settings.new
      conf_error = nil

      # If config file exists, load it and allow it to update config table.
      unless Lota.respond_to?(:conf) || !File.exist?(conf_file)
        conf_error = capture { require conf_file }
      end

      # Yes, conf.rb might not exist, but there are other ways of making
      # Lota.conf appear, so we should check for it anyway.
      conf_error = capture { Callbacks.call(:conf, @settings) } if Lota.respond_to?(:conf)
      conf_error
    end

    # The settings that reach the engine before any module opens
    # (boot.lua:266-335). The console (lines 240-245 and 261-264) opens
    # only on Windows, and the audio settings (lines 337-345) matter only
    # on Android and iOS, so Lota leaves them for later.
    private def prepare_engine
      graphics = @settings.graphics
      graphics = nil unless graphics.is_a?(Settings::Graphics)

      gammacorrect = graphics ? graphics.gammacorrect : false
      gammacorrect = @settings.gammacorrect unless @settings.gammacorrect.nil?
      Native::Graphics.set_gamma_correct(!!gammacorrect)

      Native::Graphics.set_low_power_preferred(graphics.lowpower) if graphics

      Native::Graphics.set_renderers(renderers(graphics).map(&:to_s))
      Native::Window.set_high_dpi_allowed(!!@settings.highdpi)
      Native::Touch.set_trackpad_touch(!!@settings.trackpadtouch)
    end

    # The renderers to try, in order (boot.lua:282-326): LÖVE's defaults,
    # or t.renderers, or t.graphics.renderers, without t.excluderenderers
    # or t.graphics.excluderenderers. Each excluded name removes its last
    # occurrence, as boot.lua's loop does. Names may be Symbols, as rule 9
    # makes them, or Strings. LÖVE also takes --renderers and
    # --excluderenderers on its command line; lota run does not yet.
    private def renderers(graphics)
      renderers = Native::Graphics.default_renderers.map(&:to_sym)
      deprecated = @settings.renderers
      renderers = deprecated.map(&:to_sym) if deprecated.is_a?(Array)
      chosen = graphics&.renderers
      renderers = chosen.map(&:to_sym) if chosen.is_a?(Array)

      excluderenderers = nil
      deprecated = @settings.excluderenderers
      excluderenderers = deprecated if deprecated.is_a?(Array)
      excluded = graphics&.excluderenderers
      excluderenderers = excluded if excluded.is_a?(Array)

      excluderenderers&.each do |v|
        index = renderers.rindex(v.to_sym)
        renderers.delete_at(index) if index
      end
      renderers
    end

    # Opens the filesystem and makes the game's folder its source, as
    # love.boot does (boot.lua:46, 63-65, and 123 for a game folder given
    # by name), so that files the game names, such as a font, are read from
    # its folder wherever the game was started. The filesystem opens and
    # initializes once per process, as LÖVE boots once, with Ruby's program
    # name for LÖVE's argv[0], and is marked fused or not then
    # (love.filesystem.setFused, boot.lua:90-92). A source already set
    # stays, as love.filesystem.setSource refuses a second, and boot.lua
    # calls it with pcall. LÖVE also stops printing deprecation warnings
    # in a fused game (line 94); Lota prints none yet.
    #
    # Then it names the game's save directory after its folder, as
    # boot.lua does for a game folder (lines 136-150), with pcall, so that
    # conf.rb's files are found before saved ones: love.init names it
    # again from t.identity once conf.rb has run (line 442).
    private def open_filesystem
      unless Native::Filesystem.open?
        Native::Filesystem.open
        Native::Filesystem.init($PROGRAM_NAME)
        Filesystem.fused = @fused
      end
      begin
        Native::Filesystem.set_source(@directory)
      rescue RuntimeError
        nil
      end
      begin
        Filesystem.identity = [identity, true]
      rescue RuntimeError
        nil
      end
    end

    # The save directory's name boot.lua gives a game folder: the name of
    # the folder main.rb is in, which is the game's (boot.lua:136-142),
    # without leading dots or its last extension, and with every other dot
    # an underscore (lines 145-147). A name left empty becomes "lotagame",
    # where LÖVE's is "lovegame" (line 148), so that Lota's own folder
    # names carry Lota's name, as ADR 003, section 8 names the folder it
    # saves in.
    private def identity
      identity = File.basename(@directory).sub(/\A\.+/, "").sub(/\.[^.]+\z/, "").tr(".", "_")
      identity.empty? ? "lotagame" : identity
    end

    # Puts the game's folder at the front of <tt>$LOAD_PATH</tt>, once, so
    # that conf.rb and main.rb can <tt>require "player"</tt> for the
    # player.rb beside them. love.boot makes the game's folder the source
    # LÖVE's filesystem reads (boot.lua:123) before conf.lua loads, and
    # LÖVE's require looks there before anywhere but package.preload
    # (src/modules/filesystem/wrap_Filesystem.cpp:897-929 and 1122-1124).
    # Like LÖVE, it leaves the working directory alone.
    private def add_to_load_path
      $LOAD_PATH.unshift(@directory) unless $LOAD_PATH.include?(@directory)
    end

    # Gets desired modules (boot.lua:347-372). Lota's event handlers
    # (love.createhandlers, boot.lua:374-376) are a constant,
    # Callbacks::HANDLERS, so nothing more happens here.
    private def open_modules
      MODULES.each do |name, open|
        open&.call if @settings.modules.public_send(name)
      end
    end

    # Check the version (boot.lua:378-393): turns t.version into a String,
    # as boot.lua does with Lua's tostring, and when the engine is not
    # compatible with it prints LÖVE's warning and, with the window module
    # open, shows it in a dialog, which waits until the player dismisses
    # it. boot.lua also compares the major and minor numbers of a version
    # written major.minor.revision with love._version_major and
    # _version_minor, but those are numbers and the captures are strings,
    # which never equal each other in Lua, so every version the engine is
    # not compatible with is warned about.
    private def check_version
      @settings.version = tostring(@settings.version)
      return if version_compatible?(@settings.version)

      msg = "This game indicates it was made for version '#{@settings.version}' of LOVE.\n" \
        "It may not be compatible with the running version (#{Native::VERSION})."

      puts msg

      Native::Window.show_message_box("Compatibility Warning", msg, "warning") if Native::Window.open?
    end

    # Whether the engine is compatible with the String +version+, as
    # love.isVersionCompatible decides for a string (love.cpp:309-352): a
    # version with fewer than two dots gains ".0", once, and must then
    # equal one of love._version_compat, each written the same way.
    private def version_compatible?(version)
      version = revision(version)
      Native::VERSION_COMPATIBILITY.any? { |v| revision(v) == version }
    end

    # +version+ with ".0" appended when it has fewer than two dots
    # (love.cpp:317-319 and 339-341).
    private def revision(version)
      (version.count(".") < 2) ? "#{version}.0" : version
    end

    # +value+ as Lua's tostring writes it, for the values a setting holds:
    # +nil+ as <tt>"nil"</tt>, a Float as LuaJIT writes a number, with up
    # to 14 significant digits (<tt>12.0</tt> as <tt>"12"</tt>), and
    # anything else as its +to_s+.
    private def tostring(value)
      case value
      when nil then "nil"
      when Float then format("%.14g", value)
      else value.to_s
      end
    end

    # Setup window here (boot.lua:398-426). LÖVE also sets the icon from
    # t.window.icon, which Lota's settings do not have yet.
    private def open_window
      window = @settings.window
      return unless window && @settings.modules.window

      Lota::Window.title = window.title || @settings.title
      mode = Lota::Window.set_mode(window.width, window.height,
        fullscreen: window.fullscreen,
        fullscreentype: window.fullscreentype,
        vsync: window.vsync,
        msaa: window.msaa,
        stencil: window.stencil,
        depth: window.depth,
        resizable: window.resizable,
        minwidth: window.minwidth,
        minheight: window.minheight,
        borderless: window.borderless,
        centered: window.centered,
        displayindex: window.displayindex,
        usedpiscale: window.usedpiscale,
        x: window.x,
        y: window.y)
      raise "Could not set window mode" unless mode
    end

    # Whether the folder holds neither main.rb nor conf.rb (boot.lua:152-154).
    private def no_game_code?
      !(File.exist?(main_file) || File.exist?(conf_file))
    end

    # SPDX-SnippetEnd

    private def conf_file
      File.join(@directory, "conf.rb")
    end

    private def main_file
      File.join(@directory, "main.rb")
    end

    # Runs the block and returns what it raised, or +nil+, as Lua's pcall
    # does. A SyntaxError in conf.rb is a ScriptError, not a
    # StandardError, so both are caught.
    private def capture
      yield
      nil
    rescue StandardError, ScriptError => e
      e
    end
  end
end
