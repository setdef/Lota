# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # Starts a game from its folder, as LÖVE's boot.lua starts one.
  #
  # A game is a folder holding conf.rb and main.rb
  # (doc/contributors/design/game.md). Before its code runs, something has to
  # read its settings, open the modules it wants, and open its window, in the
  # order LÖVE does them, or a game that works in LÖVE breaks in Lota.
  #
  # Boot does that. The +lota+ program makes one for the game you name
  # and calls it: it builds the settings, loads conf.rb and calls
  # <tt>Lota.conf</tt>, opens the modules, opens the window, loads main.rb,
  # and runs <tt>Lota.run</tt>'s loop until the game quits.
  #
  # Use it through the +lota+ program. Tests that draw use init alone, to
  # open a window from a conf.rb.
  #
  # An error in the game shows LÖVE's error screen in the game's window,
  # with Ruby's backtrace, as LÖVE's love.errorhandler does, or whatever
  # the game's own <tt>Lota.errorhandler</tt> shows
  # (doc/contributors/design/game.md).
  #
  # === Examples
  #
  #   # What lota path/to/game level2 does.
  #   exit Lota::Boot.new(nil, ["path/to/game", "level2"]).call
  #
  #   # Open the window a game's conf.rb asks for, without running it.
  #   Lota::Boot.new("path/to/game").init
  class Boot
    # The modules boot.lua opens, in its order (boot.lua:348-368), each
    # paired with how Lota opens it, or +nil+ for one Lota does not have
    # yet. :nodoc:
    MODULES = {
      data: -> { Native::Data.open },
      thread: -> { Native::Thread.open },
      timer: -> { Native::Timer.open },
      event: -> { Native::Event.open },
      keyboard: -> { Native::Keyboard.open },
      joystick: -> { Native::Joystick.open },
      mouse: -> { Native::Mouse.open },
      touch: -> { Native::Touch.open },
      sound: -> { Native::Sound.open },
      system: -> { Native::System.open },
      sensor: -> { Native::Sensor.open },
      audio: -> { Native::Audio.open.each { |line| puts line } },
      image: -> { Native::Image.open },
      video: -> { Native::Video.open },
      font: -> { Native::Font.open },
      window: -> { Native::Window.open },
      graphics: -> { Native::Graphics.open },
      math: -> { Native::Math.open },
      physics: -> { Native::Physics.open },
    }.freeze

    # The game's folder, as an absolute path, or +nil+ with no game.
    attr_reader :directory

    # The Lota::Settings conf.rb changed, once configure has run.
    attr_reader :settings

    # Prepares to start the game in the folder +path+, or the game the
    # program's +arguments+ name.
    #
    # [path] String path of the game's folder, or +nil+ to take the game
    #   from +arguments+, as the +lota+ program does.
    # [arguments] Array of String arguments, read as love.boot reads the
    #   program's (Lota::Arg): LÖVE's options, such as <tt>--fused</tt>
    #   and <tt>--renderers opengl</tt>, wherever they are, then, when
    #   +path+ is +nil+, the game's path, a folder, a <tt>.lota</tt>, or
    #   a Ruby file to run in the game's place of main.rb
    #   (boot.lua:98-128). What is left the game's load callback
    #   receives.
    # [fused] Whether the game is fused into an application of its own, as
    #   a shipped game is, which LÖVE's boot.lua decides from where it
    #   found the game (boot.lua:76-96) and Lota from who starts it:
    #   the +lota+ program leaves it +false+, unless the arguments hold
    #   <tt>--fused</tt>, and the entry script
    #   <tt>lota fuse</tt> writes, which ships a game, passes +true+. A
    #   fused game saves in the system's application data folder under its
    #   identity alone, where LÖVE's fused games save; one that is not
    #   saves in a +Lota+ folder there (doc/contributors/design/game.md).
    #   Only the first Boot in a process sets it, as LÖVE sets it once
    #   (Lota::Filesystem.fused=).
    #
    # === Examples
    #
    #   Lota::Boot.new("games/pong", ["--two-players"])
    #   Lota::Boot.new("Pong.app/Contents/Resources/game", fused: true)
    #   Lota::Boot.new(nil, ["games/pong", "--two-players"])
    def initialize(path, arguments = [], fused: false)
      @fused = fused
      @settings = Settings.new
      @start = [arguments, path]
      @no_game = false
      take_command_line(arguments, path, false)
    end

    # A Boot given no game, with +arguments+ for the game a player drops
    # on the screen it shows, as LÖVE given no game shows nogame.lua's
    # (boot.lua:156-170; Lota::NoGame). :nodoc:
    def self.no_game(arguments = [])
      new(nil, arguments).__send__(:without_game)
    end

    # Takes no game from the arguments, which are then all the game's
    # that a player drops. :nodoc:
    private def without_game
      @no_game = true
      arguments, given = @start
      take_command_line(arguments, given, true)
      self
    end

    # Reads the program's +arguments+ as love.boot does (boot.lua:74-87
    # and 98-128; Lota::Arg): the game is the folder +given+, or, unless
    # +game_set+, the one the arguments name, and the rest, without
    # LÖVE's options, are the game's. A game named by the arguments may
    # be a <tt>file://</tt> URI, and a Ruby file, which runs in the place
    # of main.rb, as a <tt>.lua</tt> file does in LÖVE, from the folder it
    # is in.
    private def take_command_line(arguments, given, game_set)
      line = Arg.parse(arguments, game_set: !given.nil? || game_set)
      @fused ||= line.set?("fused")
      @line = line
      @raw_arguments = given ? [given, *arguments] : arguments
      @arguments = line.game_arguments
      @path = given || line.game
      @main_name = nil
      game = line.game
      @directory = given ? File.expand_path(given) : game && game_source(game)
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # The game's source, for the path +nouri+ the arguments name
    # (boot.lua:100-117): a "content://" URI as it is, as Android opens it
    # (Lota reads none yet), and otherwise its full path, decoded first
    # from a "file://" URI. For a Ruby file it is the folder the file is
    # in, and the file is the game's main file.
    private def game_source(nouri)
      # Ignore "content://" uri as it's used to open a file-descriptor
      # directly for Android.
      return nouri if nouri.start_with?("content://")

      nouri = Boot.uridecode(nouri.delete_prefix("file://")) if nouri.start_with?("file://")

      full_source = File.expand_path(nouri)
      source_leaf = File.basename(full_source)
      return full_source unless source_leaf.end_with?(".rb")

      @main_name = source_leaf
      File.dirname(full_source)
    end

    # +s+ with each <tt>%</tt> and two hex digits made the byte they
    # name, as boot.lua's uridecode makes them (lines 32-36). :nodoc:
    def self.uridecode(s)
      s.b.gsub(/%\h\h/n) { |str| str[1, 2].to_s.hex.chr }.force_encoding(s.encoding)
    end
    # SPDX-SnippetEnd

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
    # on the main thread (doc/contributors/design/engine.md). A frame that
    # returns an Integer or Float exits with it; any other truthy value exits
    # with 0, as LÖVE's love.cpp treats a value that is not a number. A frame
    # that returns <tt>"restart"</tt>, alone or first in an Array with the
    # value the game restarts with, as love.run returns them after
    # Lota::Event.restart (callbacks.lua:177-187), ends the game as a quit
    # ends it, and call runs it again in this process with that value, as
    # love.cpp's main runs it again (Lota::Restart). Raises TypeError,
    # before anything ends, for a restart value that cannot cross.
    #
    # Once Lota.run has returned its frame, each new frame, the error
    # handler's too, goes to the event module before it first runs, as
    # boot.lua hands it to love.event._setDefaultModalDrawCallback (lines
    # 510-514). While the system holds the window in a loop of its own, as
    # Windows does while the player drags its title bar or edge, the event
    # module runs that frame from inside the pump, so the game keeps
    # drawing (Lota::Event.modal_draw_callback=, which a game's own
    # callable overrides). The frame is called there with no error
    # handling of boot's: what it raises comes out of that pump, and so
    # reaches the error handler from the frame the pump is in. When call
    # returns the event module lets go of the frame, as LÖVE's goes with
    # its Lua state.
    #
    # === Example
    #
    #   status = Lota::Boot.new("games/pong").call
    def call
      arguments, given = @start
      Restart.__send__(:in_process, -> { code_directory }) do
        take_command_line(arguments, given, @no_game)
        @code_directory = nil
        start_dropped_game(Lota.restart)
        play
      end
    end

    # Starts the game the no-game screen restarted with, when +restart+,
    # the value the run starts with, is its (Lota::NoGame): puts the path
    # of the file or folder a player dropped on it first, ahead of the
    # game's path and arguments, as love.boot puts it first in arg
    # (boot.lua:51-60), so that it is the game's path and what was there
    # before goes to the game. Each run starts from the path and arguments
    # Boot was given, as each of LÖVE's starts from the program's own
    # (src/love.cpp, main), so a game that was dropped and then restarts
    # with a value of its own starts with no game again, as in LÖVE.
    private def start_dropped_game(restart)
      # nogame.lua returns _noGameRestartInfo when
      # dropping a file or directory on to its window.
      return unless restart.is_a?(Hash)

      was_no_game = restart["_noGameRestartInfo"]
      return unless was_no_game.is_a?(Hash)

      gamepath = was_no_game["gamepath"]
      return unless gamepath.is_a?(String)

      take_command_line([gamepath, *@raw_arguments], nil, false)
    end

    # Runs the game once, as boot.lua's root function does, and returns
    # its exit status.
    private def play
      Callbacks.parsed_game_arguments = @arguments.dup.freeze
      Callbacks.raw_game_arguments = @raw_arguments.dup.freeze
      @inerror = false
      @set_modal_draw_func = false
      @func = method(:earlyinit)
      prev_func = nil #: _Frame?

      while (func = @func)
        if @set_modal_draw_func && Native::Event.open? && !func.equal?(prev_func)
          prev_func = func
          set_default_modal_draw_callback(func)
        end
        _, retval = protect { func.call }
        Native.drain_release_queue
        return finish(retval) if retval
      end

      1
    ensure
      set_default_modal_draw_callback(nil) if Native::Event.open?
    end

    # Makes +frame+, or none for +nil+, what the event module runs while
    # the system holds the window modal, as
    # love.event._setDefaultModalDrawCallback does
    # (src/modules/event/wrap_Event.cpp:223-244), its results read as the
    # results of a game's modal draw callback are (Lota::Variant.results).
    private def set_default_modal_draw_callback(frame)
      Native::Event.set_default_modal_draw_callback(frame && -> { Variant.results(frame.call) })
    end

    # The program's exit status for what the last frame returned
    # (love.cpp, runlove, lines 275-290): LÖVE restarts when the frame's
    # first result is the string <tt>"restart"</tt>, with the second as the
    # value for the new run, which Lota keeps for the run call starts
    # next; and otherwise exits with the first when it is a number, or 0.
    private def finish(retval)
      first, value = retval.is_a?(Array) ? retval : [retval]
      if first == "restart"
        Restart.__send__(:keep, value)
        return 0
      end

      (first.is_a?(Integer) || first.is_a?(Float)) ? first.to_i : 0
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

    # The part of starting up that is love.boot's (boot.lua:43-173): opens
    # the filesystem and the system module, which LÖVE opens before
    # conf.lua whatever the settings say (boot.lua:44-49), unpacks a game
    # in one file, and puts the game's folder on <tt>$LOAD_PATH</tt>. With
    # no game, or a path the filesystem could not load, it prints how to
    # give one and shows the no-game screen, as boot.lua prints LÖVE's
    # usage and runs nogame.lua (lines 156-170), and init_game then
    # reports the path.
    private def boot
      open_filesystem
      Native::System.open
      unpack
      add_to_load_path
      return if @directory && !@invalid_game_path

      require_relative "cli"
      print CLI.usage, "\n"
      NoGame.call
    end

    # For a game in one file, whose archive open_filesystem made the
    # source, as love.filesystem.setSource mounts a .love (boot.lua:123),
    # unpacks it with Lota::Archive into the cache, whose folder then holds
    # the game's Ruby for <tt>require</tt>
    # (doc/contributors/design/packaging.md). A path that is no folder and
    # that the filesystem could not mount, such as a file that is no
    # archive, is no game, as boot.lua finds when setSource fails (lines
    # 123-127): it is kept as the invalid game path, which init_game
    # reports once the window is open.
    private def unpack
      @invalid_game_path = nil
      directory = @directory
      return unless directory && !File.directory?(directory)

      if Filesystem.source.empty?
        @invalid_game_path = directory
        return
      end
      return unless File.file?(directory)

      cache = Archive.cache_directory(Native::System.os, ENV, Filesystem.user_directory)
      @code_directory = Archive.new(directory).unpack(cache)
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

      Native::Filesystem.set_android_save_external(@settings.externalstorage)
      Filesystem.identity = [@settings.identity || Filesystem.identity, @settings.appendidentity]
      main_file = self.main_file
      require main_file if main_file && File.exist?(main_file)

      if no_game_code?
        gamestr = @path.nil? ? "" : " at #{@path}"
        raise "No code to run#{gamestr}\nYour game might be packaged incorrectly.\n" \
          "Make sure main.rb is at the top level of the zip or folder."
      elsif (invalid_game_path = @invalid_game_path)
        raise "Cannot load game at path '#{invalid_game_path}'.\nMake sure a folder exists at the specified path."
      end
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
      if result
        @func = main
        @set_modal_draw_func = true
      end
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
      conf_file = self.conf_file
      if conf_file && !Lota.respond_to?(:conf) && File.exist?(conf_file)
        conf_error = capture { require conf_file }
      end

      # Yes, conf.rb might not exist, but there are other ways of making
      # Lota.conf appear, so we should check for it anyway.
      conf_error = capture { Callbacks.call(:conf, @settings) } if Lota.respond_to?(:conf)
      conf_error
    end

    # Reads the game's settings without starting it: puts the game's
    # folder on <tt>$LOAD_PATH</tt>, as booting does, so that conf.rb can
    # require the files beside it, then configures, and returns the
    # settings. It opens no module and no window, so a tool can read a
    # game's name and identity where no window can open, as
    # <tt>lota fuse</tt> does. Raises what conf.rb or <tt>Lota.conf</tt>
    # raised.
    #
    # === Example
    #
    #   # games/pong/conf.rb sets t.title = "Pong"
    #   Lota::Boot.new("games/pong").read_settings.title # => "Pong"
    def read_settings
      add_to_load_path
      conf_error = configure
      raise conf_error if conf_error

      @settings
    end

    # The settings that reach the engine before any module opens
    # (boot.lua:266-345). The console (lines 240-245 and 261-264) opens
    # only on Windows, so Lota leaves it for later. The audio settings
    # (lines 337-345) do something only on Android and iOS, as LÖVE's
    # audio module decides, and reach it on every system, as in LÖVE.
    # t.gammacorrect, which LÖVE 12 moved to t.graphics.gammacorrect, still
    # wins when set, and is marked deprecated (lines 267-275).
    private def prepare_engine
      graphics = @settings.graphics
      graphics = nil unless graphics.is_a?(Settings::Graphics)

      gammacorrect = graphics ? graphics.gammacorrect : false
      unless @settings.gammacorrect.nil?
        Deprecation.mark("t.gammacorrect in Lota.conf", :field, :replaced, "t.graphics.gammacorrect")
        gammacorrect = @settings.gammacorrect
      end
      Native::Graphics.set_gamma_correct(!!gammacorrect)

      Native::Graphics.set_low_power_preferred(graphics.lowpower) if graphics

      Native::Graphics.set_renderers(renderers(graphics).map(&:to_s))
      Native::Window.set_high_dpi_allowed(!!@settings.highdpi)
      Native::Touch.set_trackpad_touch(!!@settings.trackpadtouch)
      prepare_audio
    end

    # love._setAudioMixWithSystem with t.audio.mixwithsystem, when it is
    # set, and love._requestRecordingPermission with whether t.audio.mic
    # is (boot.lua:337-345).
    private def prepare_audio
      audio = @settings.audio
      audio = nil unless audio.is_a?(Settings::Audio)
      mix = audio&.mixwithsystem
      Native::Audio.set_mix_with_system(mix) unless mix.nil?
      Native::Audio.set_request_recording_permission(audio&.mic ? true : false)
    end

    # The renderers to try, in order (boot.lua:282-326): LÖVE's defaults,
    # or t.renderers, or t.graphics.renderers, without t.excluderenderers
    # or t.graphics.excluderenderers. Each excluded name removes its last
    # occurrence, as boot.lua's loop does. Names may be Symbols, as rule 9
    # makes them, or Strings. The arguments' <tt>--renderers</tt> and
    # <tt>--excluderenderers</tt>, each a list of names with commas between
    # them, win over the settings, as on LÖVE's command line.
    private def renderers(graphics)
      renderers = Native::Graphics.default_renderers.map(&:to_sym)
      deprecated = @settings.renderers
      renderers = deprecated.map(&:to_sym) if deprecated.is_a?(Array)
      chosen = graphics&.renderers
      renderers = chosen.map(&:to_sym) if chosen.is_a?(Array)
      renderersstr = @line.value("renderers")
      renderers = renderersstr.split(",").reject(&:empty?).map(&:to_sym) if renderersstr

      excluderenderers = nil
      deprecated = @settings.excluderenderers
      excluderenderers = deprecated if deprecated.is_a?(Array)
      excluded = graphics&.excluderenderers
      excluderenderers = excluded if excluded.is_a?(Array)
      excludestr = @line.value("excluderenderers")
      excluderenderers = excludestr.split(",").reject(&:empty?) if excludestr

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
    # calls it with pcall. Notices of deprecated names are printed unless
    # the game is fused (line 96), as Lota::Deprecation prints them.
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
      Deprecation.output = !Filesystem.fused?
      begin
        directory = @directory
        Native::Filesystem.set_source(directory) if directory
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
    # names carry Lota's name, as doc/contributors/design/game.md names the
    # folder it saves in. With no game it is the program's name, as
    # boot.lua names it after the program it runs in (lines 67-71 and
    # 131-134).
    private def identity
      directory = @directory
      return Boot.folder_identity(directory) if directory

      program = Native::Filesystem.executable_path
      Boot.folder_identity(program.empty? ? $PROGRAM_NAME : program)
    end

    # The identity boot.lua gives a game folder at +directory+, which a
    # game whose conf.rb sets no <tt>t.identity</tt> saves under, as
    # described for the private identity method above: the folder's name
    # without leading dots or its last extension, with every other dot an
    # underscore, or <tt>"lotagame"</tt> when that leaves nothing.
    # <tt>lota fuse</tt> names the folder it copies such a game into after
    # it, so the fused game saves under the name the +lota+ program gave
    # it.
    #
    # === Example
    #
    #   Lota::Boot.folder_identity("games/.sample.game") # => "sample"
    def self.folder_identity(directory)
      identity = File.basename(directory).sub(/\A\.+/, "").sub(/\.[^.]+\z/, "").tr(".", "_")
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
      directory = code_directory or return
      $LOAD_PATH.unshift(directory) unless $LOAD_PATH.include?(directory)
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
      return if Lota.version_compatible?(@settings.version)

      msg = "This game indicates it was made for version '#{@settings.version}' of LOVE.\n" \
        "It may not be compatible with the running version (#{Native::VERSION})."

      puts msg

      Native::Window.show_message_box("Compatibility Warning", msg, "warning") if Native::Window.open?
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

    # Setup window here (boot.lua:398-426), its icon first, from
    # t.window.icon, an image file's name or anything else
    # Lota::Image::ImageData.new takes, as love.image.newImageData takes it.
    # The assertion's message names Lota's own conf and module
    # (doc/contributors/design/translation.md).
    private def open_window
      window = @settings.window
      return unless window && @settings.modules.window

      if window.icon
        raise "If an icon is set in Lota.conf, Lota::Image must be loaded." unless Lota.image

        Lota::Window.set_icon(Lota::Image::ImageData.new(window.icon))
      end

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
        display: window.display,
        highdpi: window.highdpi,
        usedpiscale: window.usedpiscale,
        x: window.x,
        y: window.y)
      raise "Could not set window mode" unless mode
    end

    # Whether the folder holds neither main.rb nor conf.rb, or, for a game
    # named by its Ruby file, whether that file is missing
    # (boot.lua:152-154). With no game there is no folder, and no code is
    # missing from it.
    private def no_game_code?
      main_file = self.main_file or return false
      conf_file = self.conf_file or return false
      !(File.exist?(main_file) || (!@main_name && File.exist?(conf_file)))
    end

    # SPDX-SnippetEnd

    # The folder the game's Ruby is in: the game's own, or, for a game in
    # one file, the folder unpack put it in, or +nil+ with no game or a
    # path that holds none.
    private def code_directory
      return if @invalid_game_path

      @code_directory || @directory
    end

    private def conf_file
      directory = code_directory
      directory && File.join(directory, "conf.rb")
    end

    # main.rb in the game's folder, or the Ruby file the arguments named.
    private def main_file
      directory = code_directory
      directory && File.join(directory, @main_name || "main.rb")
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
