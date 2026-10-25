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
  # An error in the game ends the program with Ruby's own backtrace,
  # where LÖVE shows its error screen; how Lota shows errors is not
  # decided yet (Plan 001, "Design questions").
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
      mouse: nil,
      touch: nil,
      sound: nil,
      system: nil,
      sensor: nil,
      audio: nil,
      image: -> { Native::Image.open },
      video: nil,
      font: nil,
      window: -> { Native::Window.open },
      graphics: -> { Native::Graphics.open },
      math: nil,
      physics: nil,
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
    #
    # === Example
    #
    #   Lota::Boot.new("games/pong", ["--two-players"])
    def initialize(path, arguments = [])
      @path = path
      @directory = File.expand_path(path || ".")
      @arguments = arguments
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
    # love.init, and love.run's frame.
    #
    # Lota drains its release queue after every frame, so that graphics
    # objects Ruby's garbage collector freed on another thread are released
    # on the main thread (ADR 001, section 5). A frame that returns an
    # Integer or Float exits with it; any other truthy value exits with 0,
    # as LÖVE's love.cpp treats a value that is not a number.
    #
    # === Example
    #
    #   status = Lota::Boot.new("games/pong").call
    def call
      Callbacks.parsed_game_arguments = @arguments.dup.freeze
      Callbacks.raw_game_arguments = [@path, *@arguments].compact.freeze
      init
      frame = Lota.run
      loop do
        status = frame.call
        Native.drain_release_queue
        next unless status

        return (status.is_a?(Integer) || status.is_a?(Float)) ? status.to_i : 0
      end
    end

    # Brings the game up to the point where its loop starts, as love.init
    # does (boot.lua:173-456): configures it, opens its modules and its
    # window, and loads main.rb.
    #
    # An error in conf.rb waits until the modules are open, as in LÖVE,
    # whose error screen needs the window. Raises RuntimeError
    # (<tt>"Could not set window mode"</tt>) when the system refuses the
    # window, and RuntimeError when the folder holds neither main.rb nor
    # conf.rb.
    #
    # === Example
    #
    #   Lota::Boot.new("games/pong").init
    #   Lota::Graphics.dimensions # => [800, 600]
    def init
      conf_error = configure
      prepare_engine
      open_modules

      # boot.lua checks t.version against the engine's here (lines
      # 378-392); what a Lota game's version means is not decided yet.

      raise conf_error if conf_error

      open_window

      # The first couple event pumps on some systems (e.g. macOS) can take a
      # while. We'd rather hit that slowdown here than in event processing
      # within the first frames.
      2.times { Event.pump } if Native::Event.open?

      # Our first timestep, because window creation can take some time
      Timer.step if Native::Timer.open?

      require main_file if File.exist?(main_file)
      return unless no_game_code?

      gamestr = @path.nil? ? "" : " at #{@path}"
      raise "No code to run#{gamestr}\nYour game might be packaged incorrectly.\n" \
        "Make sure main.rb is at the top level of the zip or folder."
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

    # Gets desired modules (boot.lua:347-372). Lota's event handlers
    # (love.createhandlers, boot.lua:374-376) are a constant,
    # Callbacks::HANDLERS, so nothing more happens here.
    private def open_modules
      MODULES.each do |name, open|
        open&.call if @settings.modules.public_send(name)
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
