# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The settings a game starts with, which its conf.rb can change.
  #
  # Some choices have to be made before a game's code runs: how large the
  # window opens, which modules load, which renderer draws. By the time
  # main.rb runs, the window is already open.
  #
  # So Lota builds a Settings with LÖVE's defaults and passes it to
  # <tt>Lota.conf</tt>, if your game's conf.rb defines one, before it
  # opens any module (ADR 003). Each setting keeps the name and nesting of
  # LÖVE's <tt>t</tt> table, so <tt>t.window.width = 1280</tt> reads as it
  # does in a LÖVE tutorial, and names that were strings in LÖVE are
  # symbols here (<tt>t.window.fullscreentype = :exclusive</tt>).
  #
  # Use it in conf.rb to size and title the window and to turn off modules
  # your game does not use.
  #
  # A setting LÖVE does not know is accepted and ignored, as LÖVE ignores
  # a key it does not read in its table (ADR 003, section 5), so a
  # translated conf.lua that sets keys of its own still runs. Reading one
  # back returns what was set, and reading a setting never set returns
  # +nil+, as reading a missing key does in Lua.
  # Lota reads the settings boot.lua reads, except +console+,
  # +externalstorage+, and +audio+, which LÖVE reads only on Windows,
  # Android, and iOS.
  #
  # === Examples
  #
  #   # conf.rb
  #   def Lota.conf(t)
  #     t.window.title = "Asteroids"
  #     t.window.width = 1280
  #     t.window.height = 720
  #     t.window.fullscreentype = :exclusive
  #     t.modules.physics = false
  #   end
  #
  #   # A game without a window.
  #   def Lota.conf(t)
  #     t.window = false
  #   end
  class Settings
    # The settings LÖVE does not know, which each part of Settings accepts
    # and keeps, as a Lua table keeps any key it is given, and which no
    # part of Lota reads. :nodoc:
    module UnknownSettings
      # The name of a writer a setting could have: a Lua identifier, as
      # <tt>t.name = value</tt> spells it, followed by =.
      WRITER = /\A[A-Za-z_]\w*=\z/

      # The name of a setting's reader: a Lua identifier, as
      # <tt>t.name</tt> spells it.
      READER = /\A[A-Za-z_]\w*\z/

      # Keeps +value+ for <tt>name=</tt>, or returns what was kept for
      # +name+, or +nil+ for a setting never set, as Lua returns nil for a
      # missing key (ADR 003, section 5). Anything else, such as a reader
      # given arguments, raises NoMethodError.
      private def method_missing(name, *arguments)
        if WRITER.match?(name) && arguments.size == 1
          kept = @unknown_settings ||= {} #: Hash[Symbol, top]
          kept[name.name.chomp("=").to_sym] = arguments.first
        elsif arguments.empty? && READER.match?(name)
          @unknown_settings&.[](name)
        else
          super
        end
      end

      # Whether +name+ is a setting's writer, or the reader of a setting
      # already kept. A setting never set reads as +nil+ but is not one
      # the object responds to, so that Ruby's implicit conversions, which
      # ask respond_to? first, find no +to_ary+ or +to_str+ here.
      private def respond_to_missing?(name, include_private = false)
        WRITER.match?(name) || @unknown_settings&.key?(name.to_sym) || super
      end
    end

    include UnknownSettings

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Translated from love.init's default settings
    # (vendor/love/src/modules/love/boot.lua:178-238), with the window
    # settings boot.lua reads but does not default (title, stencil, depth,
    # display, and highdpi, lines 405-421), which stay nil until set.

    # How the window opens: <tt>t.window</tt>.
    class Window
      include UnknownSettings

      # Integer width, in units of the screen's DPI scale; 800 by default.
      attr_accessor :width

      # Integer height, likewise; 600 by default.
      attr_accessor :height

      # Integer position of the window's left edge, or +nil+ (the default)
      # to let +centered+ place it.
      attr_accessor :x

      # Integer position of the window's top edge, or +nil+ (the default).
      attr_accessor :y

      # Integer smallest width the player can resize to; 1 by default.
      attr_accessor :minwidth

      # Integer smallest height the player can resize to; 1 by default.
      attr_accessor :minheight

      # Whether the window fills the screen; +false+ by default.
      attr_accessor :fullscreen

      # +:desktop+ (the default) or +:exclusive+.
      attr_accessor :fullscreentype

      # Integer display to open on, counting from 1; 1 by default.
      attr_accessor :displayindex

      # Integer vertical sync: 1 (the default) waits for the display, 0
      # does not, -1 waits unless a frame is late.
      attr_accessor :vsync

      # Integer number of antialiasing samples; 0 by default.
      attr_accessor :msaa

      # Whether the window has no border; +false+ by default.
      attr_accessor :borderless

      # Whether the player can resize the window; +false+ by default.
      attr_accessor :resizable

      # Whether the window opens centered; +true+ by default.
      attr_accessor :centered

      # Whether sizes count in units of the DPI scale; +true+ by default.
      attr_accessor :usedpiscale

      # String title of the window, or +nil+ (the default) for the game's
      # +title+.
      attr_accessor :title

      # Whether the window has a stencil buffer, or +nil+ (the default)
      # for Lota::Window.set_mode's default, +true+.
      attr_accessor :stencil

      # Whether the window has a depth buffer, or +nil+ (the default) for
      # Lota::Window.set_mode's default, +false+.
      attr_accessor :depth

      # Deprecated, as in LÖVE 12, for +displayindex+: the display to open
      # on, counting from 1, or +nil+ (the default) for +displayindex+.
      attr_accessor :display

      # Deprecated, as in LÖVE 12, for <tt>t.highdpi</tt>: whether high
      # DPI is allowed, or +nil+ (the default) for <tt>t.highdpi</tt>.
      attr_accessor :highdpi

      # LÖVE's defaults for <tt>t.window</tt>.
      #
      # === Example
      #
      #   Lota::Settings::Window.new.width # => 800
      def initialize
        @width = 800
        @height = 600
        @x = nil
        @y = nil
        @minwidth = 1
        @minheight = 1
        @fullscreen = false
        @fullscreentype = :desktop
        @displayindex = 1
        @vsync = 1
        @msaa = 0
        @borderless = false
        @resizable = false
        @centered = true
        @usedpiscale = true
        @title = nil
        @stencil = nil
        @depth = nil
        @display = nil
        @highdpi = nil
      end
    end

    # How the graphics module starts: <tt>t.graphics</tt>.
    class Graphics
      include UnknownSettings

      # Whether colors blend in linear space; +false+ by default.
      attr_accessor :gammacorrect

      # Whether to prefer a low-power graphics card on machines with two;
      # +false+ by default.
      attr_accessor :lowpower

      # Array of renderer names to try, in order, such as
      # <tt>[:metal, :opengl]</tt>, or +nil+ (the default) for LÖVE's own
      # order.
      attr_accessor :renderers

      # Array of renderer names never to try, or +nil+ (the default).
      attr_accessor :excluderenderers

      # LÖVE's defaults for <tt>t.graphics</tt>.
      #
      # === Example
      #
      #   Lota::Settings::Graphics.new.gammacorrect # => false
      def initialize
        @gammacorrect = false
        @lowpower = false
        @renderers = nil
        @excluderenderers = nil
      end
    end

    # Which modules open: <tt>t.modules</tt>, every one +true+ by default.
    # Lota opens the modules it has (timer, event, keyboard, image,
    # window, and graphics) when theirs is +true+; the rest wait for Lota
    # to bind them.
    class Modules
      include UnknownSettings

      # Whether love.data opens.
      attr_accessor :data

      # Whether Lota::Event opens.
      attr_accessor :event

      # Whether the keyboard module opens.
      attr_accessor :keyboard

      # Whether love.mouse opens.
      attr_accessor :mouse

      # Whether Lota::Timer opens.
      attr_accessor :timer

      # Whether love.joystick opens.
      attr_accessor :joystick

      # Whether love.touch opens.
      attr_accessor :touch

      # Whether Lota::Image opens.
      attr_accessor :image

      # Whether Lota::Graphics opens.
      attr_accessor :graphics

      # Whether love.audio opens.
      attr_accessor :audio

      # Whether love.math opens.
      attr_accessor :math

      # Whether love.physics opens.
      attr_accessor :physics

      # Whether love.sensor opens.
      attr_accessor :sensor

      # Whether love.sound opens.
      attr_accessor :sound

      # Whether love.system opens.
      attr_accessor :system

      # Whether love.font opens.
      attr_accessor :font

      # Whether love.thread opens.
      attr_accessor :thread

      # Whether Lota::Window opens.
      attr_accessor :window

      # Whether love.video opens.
      attr_accessor :video

      # Every module on, as in LÖVE.
      #
      # === Example
      #
      #   Lota::Settings::Modules.new.physics # => true
      def initialize
        @data = true
        @event = true
        @keyboard = true
        @mouse = true
        @timer = true
        @joystick = true
        @touch = true
        @image = true
        @graphics = true
        @audio = true
        @math = true
        @physics = true
        @sensor = true
        @sound = true
        @system = true
        @font = true
        @thread = true
        @window = true
        @video = true
      end
    end

    # How audio starts on phones: <tt>t.audio</tt>.
    class Audio
      include UnknownSettings

      # Whether the game's audio mixes with other apps' on Android and
      # iOS; +true+ by default.
      attr_accessor :mixwithsystem

      # Whether to ask for the microphone on Android; +false+ by default.
      attr_accessor :mic

      # LÖVE's defaults for <tt>t.audio</tt>.
      #
      # === Example
      #
      #   Lota::Settings::Audio.new.mic # => false
      def initialize
        @mixwithsystem = true
        @mic = false
      end
    end

    # String name of the game, the window's title unless
    # <tt>t.window.title</tt> is set; <tt>"Untitled"</tt> by default.
    attr_accessor :title

    # String version of LÖVE's engine the game was made for; the engine's
    # own version by default. One the engine is not compatible with makes
    # <tt>lota run</tt> print LÖVE's warning and show it in a dialog, as
    # boot.lua does.
    attr_accessor :version

    # Settings::Window, or +false+ or +nil+ to open no window.
    attr_accessor :window

    # Settings::Graphics.
    attr_accessor :graphics

    # Settings::Modules.
    attr_accessor :modules

    # Settings::Audio.
    attr_accessor :audio

    # Whether to open a console on Windows; +false+ by default.
    attr_accessor :console

    # String name of the game's save directory, or +false+ (the default)
    # for one named after the game's folder.
    attr_accessor :identity

    # Whether to search the save directory after the game's folder;
    # +false+ by default.
    attr_accessor :appendidentity

    # Whether to save to external storage on Android; +false+ by default.
    attr_accessor :externalstorage

    # Whether colors blend in linear space, or +nil+ (the default) for
    # <tt>t.graphics.gammacorrect</tt>. LÖVE 12 moved it there.
    attr_accessor :gammacorrect

    # Whether the window uses the display's full resolution on high-DPI
    # displays; +false+ by default.
    attr_accessor :highdpi

    # Array of renderer names, or +nil+ (the default) for
    # <tt>t.graphics.renderers</tt>. LÖVE 12 moved it there.
    attr_accessor :renderers

    # Array of renderer names never to try, or +nil+ (the default) for
    # <tt>t.graphics.excluderenderers</tt>. LÖVE 12 moved it there.
    attr_accessor :excluderenderers

    # Whether a trackpad reports touches; +false+ by default.
    attr_accessor :trackpadtouch

    # LÖVE's defaults, for <tt>Lota.conf</tt> to change.
    #
    # === Example
    #
    #   t = Lota::Settings.new
    #   t.window.width # => 800
    #   t.title        # => "Untitled"
    def initialize
      @title = "Untitled"
      @version = Native::VERSION
      @window = Window.new
      @graphics = Graphics.new
      @modules = Modules.new
      @audio = Audio.new
      @console = false
      @identity = false
      @appendidentity = false
      @externalstorage = false
      @gammacorrect = nil
      @highdpi = false
      @renderers = nil
      @excluderenderers = nil
      @trackpadtouch = false
    end

    # SPDX-SnippetEnd
  end
end
