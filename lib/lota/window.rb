# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The game's window, translated from love.window.
  #
  # A game draws into one window, whose size, title, and mode the player
  # sees before anything else. Opening it involves the operating system,
  # which can refuse a mode, and the graphics card, which needs a context
  # to draw with.
  #
  # Lota::Window opens and changes that window through LÖVE's own window
  # module, so it behaves as a LÖVE game's window does. Lota's boot
  # sequence opens it from your settings before your game's main.rb runs.
  # Like Lota::Graphics, it raises ThreadError anywhere but the main
  # thread.
  #
  # Use it to change the window's size or mode, or to set its title.
  #
  # === Examples
  #
  #   Lota::Window.title = "Asteroids"
  #   Lota::Window.set_mode(1280, 720, resizable: true, vsync: 0)
  #
  #   unless Lota::Window.set_mode(1920, 1080, fullscreen: true)
  #     Lota::Window.set_mode(800, 600) # fall back
  #   end
  module Window
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # Opens the window, or changes it, at +width+ by +height+, matching
    # love.window.setMode (src/modules/window/wrap_Window.cpp, w_setMode
    # and readWindowSettings).
    #
    # [width] Integer width, in units of the screen's DPI scale; 0 takes the
    #   desktop's.
    # [height] Integer height, likewise.
    # [fullscreen] Whether the window fills the screen; +false+ by default.
    # [fullscreentype] +:desktop+ (the default) for a borderless window the
    #   size of the desktop, or +:exclusive+ to change the display's mode.
    # [vsync] Integer: 1 waits for the display's refresh, 0 does not, and
    #   -1 waits unless a frame is late; +true+ is 1 and +false+ is 0.
    # [msaa] Integer number of antialiasing samples; 0 by default.
    # [stencil] Whether the window has a stencil buffer; +true+ by default.
    # [depth] Whether the window has a depth buffer; +false+ by default.
    # [resizable] Whether the player can resize the window; +false+ by
    #   default.
    # [minwidth] Integer smallest width the player can resize it to; 1 by
    #   default.
    # [minheight] Integer smallest height; 1 by default.
    # [borderless] Whether the window has no border; +false+ by default.
    # [centered] Whether the window opens centered on its display; +true+
    #   by default.
    # [displayindex] Integer display to open on, counting from 1; 1 by
    #   default.
    # [usedpiscale] Whether sizes count in units of the DPI scale rather
    #   than in pixels; +true+ by default.
    # [refreshrate] Ignored, as LÖVE ignores it: the refresh rate is
    #   read-only.
    # [x] Integer position of the window's left edge on its display.
    # [y] Integer position of its top edge. When neither +x+ nor +y+ is
    #   given, the window's position follows +centered+.
    #
    # Each setting left out, or +nil+, takes its default, which is not the
    # window's current value. Integer settings ignore a value that is not
    # a number, and true-or-false settings take any value's truthiness, as
    # LÖVE reads its table. Returns +false+ when the system refuses the
    # mode, so the game can fall back (ADR 001, rule 7). Raises
    # ArgumentError for an unknown +fullscreentype+, RuntimeError with
    # LÖVE's message while a canvas is the target, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Window.set_mode(800, 600, resizable: true, minwidth: 400, minheight: 300)
    def self.set_mode(width, height, fullscreen: nil, fullscreentype: nil, vsync: nil, msaa: nil, stencil: nil,
      depth: nil, resizable: nil, minwidth: nil, minheight: nil, borderless: nil, centered: nil, displayindex: nil,
      usedpiscale: nil, refreshrate: nil, x: nil, y: nil
    )
      _ = refreshrate
      settings = Native::WindowSettings.new
      unless fullscreentype.nil? || settings.set_fullscreentype(fullscreentype.to_s)
        expected = Native::Window.fullscreen_types.map { |name| "'#{name}'" }.join(", ")
        raise ArgumentError, "Invalid fullscreen type '#{fullscreentype}', expected one of: #{expected}"
      end
      settings.fullscreen = flag(fullscreen, settings.fullscreen)
      settings.msaa = integer(msaa, settings.msaa)
      settings.stencil = flag(stencil, settings.stencil)
      settings.resizable = flag(resizable, settings.resizable)
      settings.minwidth = integer(minwidth, settings.minwidth)
      settings.minheight = integer(minheight, settings.minheight)
      settings.borderless = flag(borderless, settings.borderless)
      settings.centered = flag(centered, settings.centered)
      settings.usedpiscale = flag(usedpiscale, settings.usedpiscale)
      settings.depth = flag(depth, settings.depth)
      settings.displayindex = integer(displayindex, settings.displayindex + 1) - 1
      settings.vsync = vsync_of(vsync, settings.vsync)
      settings.useposition = !(x.nil? && y.nil?)
      if settings.useposition
        settings.x = x.to_i
        settings.y = y.to_i
      end
      Native::Window.set_mode(width, height, settings)
    end

    # luax_boolflag (src/common/runtime.cpp): the default when nil, else
    # the value's truthiness.
    private_class_method def self.flag(value, default)
      value.nil? ? default : !!value
    end

    # luax_intflag (src/common/runtime.cpp): the default unless a number.
    private_class_method def self.integer(value, default)
      (value.is_a?(Integer) || value.is_a?(Float)) ? value.to_i : default
    end

    # readWindowSettings' vsync: a number, or true for 1 and false for 0;
    # anything else leaves the default.
    private_class_method def self.vsync_of(value, default)
      case value
      when Integer, Float then value.to_i
      when true then 1
      when false then 0
      else default
      end
    end

    # SPDX-SnippetEnd

    # Sets the window's title, matching love.window.setTitle
    # (src/modules/window/wrap_Window.cpp, w_setTitle).
    #
    # [title] String shown in the window's title bar.
    #
    # A title set before the window opens waits for it. Lota's boot
    # sequence sets it from <tt>t.window.title</tt>, or <tt>t.title</tt>,
    # in your conf.rb. Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.title = "Level 2"
    def self.title=(title)
      Native::Window.set_title(title)
    end

    # The window's title, matching love.window.getTitle
    # (src/modules/window/wrap_Window.cpp, w_getTitle).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.title # => "Untitled"
    def self.title
      Native::Window.title.force_encoding(Encoding::UTF_8)
    end
  end
end
