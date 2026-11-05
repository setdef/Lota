# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "window/fullscreen_mode"
require_relative "window/mode"

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
  # Use it to change the window's size or mode, to go fullscreen, to ask
  # about the displays, or to set its title.
  #
  # === Examples
  #
  #   Lota::Window.title = "Asteroids"
  #   Lota::Window.set_mode(1280, 720, resizable: true, vsync: 0)
  #
  #   Lota::Window.set_fullscreen(true, :desktop)
  #   Lota::Window.display_count # => 2
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
    # [display] Deprecated, as in LÖVE, for +displayindex+, which it
    #   replaces when given: an Integer display, counting from 1.
    # [highdpi] Deprecated, as in LÖVE, for +t.highdpi+ in Lota.conf:
    #   +true+ or +false+, whether high DPI is allowed, which changes only
    #   while no window is open.
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
    # LÖVE reads its table; a number for +depth+, LÖVE 11's form, is
    # whether it is not zero. The first use of each deprecated form prints
    # LÖVE's notice (Lota::Deprecation). Returns +false+ when the system
    # refuses the mode, so the game can fall back (ADR 001, rule 7).
    # Raises ArgumentError for an unknown +fullscreentype+, TypeError for a
    # +display+ that is not a number or a +highdpi+ that is not +true+ or
    # +false+, RuntimeError with LÖVE's message while a canvas is the
    # target, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.set_mode(800, 600, resizable: true, minwidth: 400, minheight: 300)
    def self.set_mode(width, height, fullscreen: nil, fullscreentype: nil, vsync: nil, msaa: nil, stencil: nil,
      depth: nil, resizable: nil, minwidth: nil, minheight: nil, borderless: nil, centered: nil, displayindex: nil,
      display: nil, highdpi: nil, usedpiscale: nil, refreshrate: nil, x: nil, y: nil
    )
      _ = refreshrate
      settings = read_window_settings(Native::WindowSettings.new, fullscreen:, fullscreentype:, vsync:, msaa:,
        stencil:, depth:, resizable:, minwidth:, minheight:, borderless:, centered:, displayindex:, display:, highdpi:,
        usedpiscale:, x:, y:, where: where(caller_locations(1, 2)))
      Native::Window.set_mode(width, height, settings)
    end

    # Changes some of the window's settings, keeping the rest as they are,
    # matching love.window.updateMode
    # (src/modules/window/wrap_Window.cpp, w_updateMode).
    #
    # [width] Integer new width, as set_mode takes it; the window's own
    #   when left out, with +height+.
    # [height] Integer new height, required with +width+.
    #
    # Its settings are set_mode's, each the window's current value when
    # left out or +nil+, where set_mode takes the default. As LÖVE reads
    # a table of settings only when given one, the window's position is
    # kept when no setting is given, and follows +x+, +y+, and +centered+,
    # as set_mode's does, when any is. Returns +false+
    # when the system refuses the mode (ADR 001, rule 7). Raises
    # RuntimeError (<tt>"Expected at least one argument"</tt>) given
    # neither a size nor a setting, as LÖVE does given nothing, and
    # otherwise raises as set_mode does.
    #
    # === Examples
    #
    #   Lota::Window.update_mode(460, 364)
    #   Lota::Window.update_mode(resizable: true)
    def self.update_mode(width = nil, height = nil, fullscreen: nil, fullscreentype: nil, vsync: nil, msaa: nil,
      stencil: nil, depth: nil, resizable: nil, minwidth: nil, minheight: nil, borderless: nil, centered: nil,
      displayindex: nil, display: nil, highdpi: nil, usedpiscale: nil, refreshrate: nil, x: nil, y: nil
    )
      settings = Native::WindowSettings.new
      w, h = Native::Window.get_window(settings)
      given = [
        fullscreen,
        fullscreentype,
        vsync,
        msaa,
        stencil,
        depth,
        resizable,
        minwidth,
        minheight,
        borderless,
        centered,
        displayindex,
        display,
        highdpi,
        usedpiscale,
        refreshrate,
        x,
        y,
]
      raise "Expected at least one argument" if width.nil? && given.all?(&:nil?)

      if width.is_a?(Integer) || width.is_a?(Float)
        w = width.to_i
        h = Integer(height)
      end
      unless given.all?(&:nil?)
        read_window_settings(settings, fullscreen:, fullscreentype:, vsync:, msaa:, stencil:, depth:, resizable:,
          minwidth:, minheight:, borderless:, centered:, displayindex:, display:, highdpi:, usedpiscale:, x:, y:,
          where: where(caller_locations(1, 2)))
      end
      Native::Window.set_mode(w, h, settings)
    end

    # The window's width, height, and settings, as an Array (ADR 001,
    # rule 4) of two Integers and a frozen Mode with LÖVE's field names
    # (rule 10), matching love.window.getMode
    # (src/modules/window/wrap_Window.cpp, w_getMode).
    #
    # LÖVE also fills in a table the caller passes; a Mode is frozen, so
    # Lota makes a new one each time. Raises ThreadError off the main
    # thread.
    #
    # === Example
    #
    #   width, height, flags = Lota::Window.mode
    #   flags.fullscreen # => false
    def self.mode
      settings = Native::WindowSettings.new
      width, height = Native::Window.get_window(settings)
      [
        width,
        height,
        Mode.new(
          fullscreentype: settings.fullscreentype.to_sym, fullscreen: settings.fullscreen, vsync: settings.vsync,
          msaa: settings.msaa, stencil: settings.stencil, depth: settings.depth, resizable: settings.resizable,
          minwidth: settings.minwidth, minheight: settings.minheight, borderless: settings.borderless,
          centered: settings.centered, displayindex: settings.displayindex + 1, usedpiscale: settings.usedpiscale,
          refreshrate: settings.refreshrate, x: settings.x, y: settings.y
        ),
]
    end

    # The width and height of a display, as an Array (ADR 001, rule 4),
    # matching love.window.getDesktopDimensions
    # (src/modules/window/wrap_Window.cpp, w_getDesktopDimensions).
    #
    # [displayindex] Integer display, counting from 1; the one the window
    #   is on when +nil+ or left out.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   width, height = Lota::Window.desktop_dimensions # => [1728, 1117]
    def self.desktop_dimensions(displayindex = nil)
      Native::Window.desktop_dimensions(displayindex)
    end

    # The part of the window nothing of the system's covers, such as a
    # phone's notch, as an Array (ADR 001, rule 4) of its Integer x, y,
    # width, and height, matching love.window.getSafeArea
    # (src/modules/window/wrap_Window.cpp, w_getSafeArea).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   x, y, width, height = Lota::Window.safe_area # => [0, 0, 800, 600]
    def self.safe_area
      Native::Window.safe_area
    end

    # readWindowSettings (wrap_Window.cpp:56-128): each setting given
    # replaces the one +settings+ holds, which is the default for set_mode
    # and the window's own for update_mode.
    private_class_method def self.read_window_settings(settings, fullscreen:, fullscreentype:, vsync:, msaa:,
      stencil:, depth:, resizable:, minwidth:, minheight:, borderless:, centered:, displayindex:, display:, highdpi:,
      usedpiscale:, x:, y:, where:
    )
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
      settings.depth = depth_of(depth, settings.depth, where)
      settings.displayindex = integer(displayindex, settings.displayindex + 1) - 1
      settings.displayindex = deprecated_display(display, where) - 1 unless display.nil?
      deprecated_highdpi(highdpi, where) unless highdpi.nil?
      settings.vsync = vsync_of(vsync, settings.vsync)
      settings.useposition = !(x.nil? && y.nil?)
      if settings.useposition
        settings.x = x.to_i
        settings.y = y.to_i
      end
      settings
    end

    # depth (wrap_Window.cpp:78-86): a number, LÖVE 11's form, marked
    # deprecated, is whether it is not zero; anything else but nil is its
    # truthiness.
    private_class_method def self.depth_of(value, default, where)
      return flag(value, default) unless value.is_a?(Integer) || value.is_a?(Float)

      Deprecation.mark("window.depth number", :field, :replaced, "window.depth boolean field", where:)
      value.to_i != 0
    end

    # display (wrap_Window.cpp:89-96), marked deprecated: the display,
    # counting from 1, which must be a number (luaL_checkinteger).
    private_class_method def self.deprecated_display(value, where)
      Deprecation.mark("window.display", :field, :replaced, "displayindex field", where:)
      case value
      when Integer, Float then value.to_i
      else raise TypeError, "wrong argument type #{value.class} for display (expected Integer)"
      end
    end

    # highdpi (wrap_Window.cpp:98-107), marked deprecated: whether high DPI
    # is allowed, which must be true or false (luax_checkboolean), and which
    # changes only while no window is open, as setHighDPIAllowed does.
    private_class_method def self.deprecated_highdpi(value, where)
      Deprecation.mark("window.highdpi", :field, :replaced, "t.highdpi in Lota.conf", where:)
      case value
      when true, false then Native::Window.set_high_dpi_allowed(value) unless Native::Window.window_open?
      else raise TypeError, "wrong argument type #{value.class} for highdpi (expected true or false)"
      end
    end

    # Where a caller called from (Deprecation.where).
    private_class_method def self.where(locations)
      Deprecation.where(locations)
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

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # How many displays are connected, matching love.window.getDisplayCount
    # (src/modules/window/wrap_Window.cpp, w_getDisplayCount).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.display_count # => 1
    def self.display_count
      Native::Window.display_count
    end

    # The name of a display, matching love.window.getDisplayName
    # (src/modules/window/wrap_Window.cpp, w_getDisplayName).
    #
    # [index] Integer display, counting from 1.
    #
    # Raises RuntimeError for a display that is not connected, and
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.display_name(1) # => "Built-in Retina Display"
    def self.display_name(index)
      Native::Window.display_name(index).force_encoding(Encoding::UTF_8)
    end

    # The way a display is turned, as a Symbol (ADR 001, rule 9),
    # matching love.window.getDisplayOrientation
    # (src/modules/window/wrap_Window.cpp, w_getDisplayOrientation).
    #
    # [displayindex] Integer display, counting from 1; the one the window
    #   is on when +nil+ or left out.
    #
    # It is +:unknown+, +:landscape+, +:landscapeflipped+, +:portrait+, or
    # +:portraitflipped+. Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.display_orientation # => :landscape
    def self.display_orientation(displayindex = nil)
      Native::Window.display_orientation(displayindex).to_sym
    end

    # The modes a display can be set to, as an Array of frozen
    # FullscreenModes (ADR 001, rules 4 and 10), matching
    # love.window.getFullscreenModes
    # (src/modules/window/wrap_Window.cpp, w_getFullscreenModes).
    #
    # [displayindex] Integer display, counting from 1; the one the window
    #   is on when +nil+ or left out.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   mode = Lota::Window.fullscreen_modes.first
    #   mode.width # => 1920
    def self.fullscreen_modes(displayindex = nil)
      Native::Window.fullscreen_modes(displayindex).map do |width, height, refreshrate|
        FullscreenMode.new(width:, height:, refreshrate:)
      end
    end

    # Whether the window is fullscreen and its fullscreen type, as an
    # Array (ADR 001, rule 4) of a boolean and +:desktop+ or +:exclusive+
    # (rule 9), matching love.window.getFullscreen
    # (src/modules/window/wrap_Window.cpp, w_getFullscreen).
    #
    # The type is the one the window will use when it goes fullscreen, so
    # it is set even while the window is not. Raises ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   fullscreen, type = Lota::Window.fullscreen # => [false, :desktop]
    def self.fullscreen
      fullscreen, type = Native::Window.fullscreen
      [fullscreen, type.to_sym]
    end

    # Makes the window fullscreen, or not, matching love.window.setFullscreen
    # (src/modules/window/wrap_Window.cpp, w_setFullscreen).
    #
    # [fullscreen] +true+ to fill the screen, +false+ for a window.
    # [fullscreentype] +:desktop+ for a borderless window the size of the
    #   desktop, or +:exclusive+ to change the display's mode; the type
    #   the window already has when +nil+ or left out.
    #
    # Returns +false+ when the system refuses (ADR 001, rule 7). Raises
    # ArgumentError for an unknown +fullscreentype+, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Window.set_fullscreen(true, :exclusive) or Lota::Window.set_fullscreen(true)
    def self.set_fullscreen(fullscreen, fullscreentype = nil)
      Native::Window.set_fullscreen(fullscreen, fullscreentype&.to_s)
    end

    # Closes the window, matching love.window.close
    # (src/modules/window/wrap_Window.cpp, w_close), which LÖVE has
    # deprecated without a replacement. The first use prints LÖVE's notice
    # (Lota::Deprecation). Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.close
    def self.close
      Deprecation.mark("Lota::Window.close", :function, :noreplacement, where: where(caller_locations(1, 2)))
      Native::Window.close
    end

    # The window's position, as an Array (ADR 001, rule 4) of the
    # Integer x and y of its top left corner on its display and that
    # display, counting from 1, matching love.window.getPosition
    # (src/modules/window/wrap_Window.cpp, w_getPosition).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   x, y, displayindex = Lota::Window.position # => [100, 100, 1]
    def self.position
      Native::Window.position
    end

    # Moves the window, matching love.window.setPosition
    # (src/modules/window/wrap_Window.cpp, w_setPosition), whose values
    # rule 6 of ADR 001 makes one Array.
    #
    # [position] An Array of the Integer x and y of the window's top left
    #   corner, then optionally the Integer display, counting from 1,
    #   which is the one the window is on when +nil+ or left out, and
    #   whether to wait for the system to move the window, which is +true+
    #   when left out.
    #
    # Raises ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Window.position = 100, 100
    #   Lota::Window.position = 0, 0, 2
    def self.position=(position)
      x, y, displayindex, wait_for_sync = position
      Native::Window.set_position(x, y, displayindex, wait_for_sync.nil? || wait_for_sync)
    end

    # The window's icon, an Lota::Image::ImageData, or +nil+ when none has
    # been set, matching love.window.getIcon
    # (src/modules/window/wrap_Window.cpp, w_getIcon).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.icon # => nil
    def self.icon
      native = Native::Window.icon
      native && Lota::Image::ImageData.from_native(native)
    end

    # Sets the window's icon, matching love.window.setIcon
    # (src/modules/window/wrap_Window.cpp, w_setIcon).
    #
    # [imagedata] Lota::Image::ImageData to show as the icon.
    #
    # LÖVE stores the icon before the system can refuse it, so +icon+
    # answers it even when this returns +false+ (ADR 001, rule 7). Raises
    # TypeError for anything but an ImageData, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Window.set_icon(Lota::Image::ImageData.new("icon.png"))
    def self.set_icon(imagedata)
      unless imagedata.is_a?(Lota::Image::ImageData)
        raise TypeError, "wrong argument type #{imagedata.class} (expected Lota::Image::ImageData)"
      end

      Native::Window.set_icon(imagedata.native)
    end

    # The window's vertical synchronization: 1 waits for the display's
    # refresh, 0 does not, and -1 waits unless a frame is late. Matches
    # love.window.getVSync (src/modules/window/wrap_Window.cpp,
    # w_getVSync).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.vsync # => 1
    def self.vsync
      Native::Window.vsync
    end

    # Sets the window's vertical synchronization, matching
    # love.window.setVSync (src/modules/window/wrap_Window.cpp,
    # w_setVSync).
    #
    # [vsync] Integer 1, 0, or -1, as Lota::Window.vsync answers; +true+
    #   is 1 and +false+ is 0.
    #
    # Raises TypeError for anything else, and ThreadError off the main
    # thread.
    #
    # === Example
    #
    #   Lota::Window.vsync = 0
    def self.vsync=(vsync)
      value = case vsync
      when true then 1
      when false then 0
      when Integer then vsync
      when Float then vsync.to_i
      else raise TypeError, "wrong argument type #{vsync.class} for vsync (expected Integer, true, or false)"
      end
      Native::Window.set_vsync(value)
    end

    # Whether the system may turn the display off while the game runs
    # without input, matching love.window.isDisplaySleepEnabled
    # (src/modules/window/wrap_Window.cpp, w_isDisplaySleepEnabled).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.display_sleep_enabled? # => true
    def self.display_sleep_enabled?
      Native::Window.display_sleep_enabled?
    end

    # Lets the system turn the display off while the game runs without
    # input, or not, matching love.window.setDisplaySleepEnabled
    # (src/modules/window/wrap_Window.cpp, w_setDisplaySleepEnabled).
    #
    # [enable] +true+ to let it, +false+ to keep it on; any other value
    #   counts as its truthiness.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.display_sleep_enabled = false
    def self.display_sleep_enabled=(enable)
      Native::Window.set_display_sleep_enabled(enable)
    end

    # Whether the window has keyboard focus, matching love.window.hasFocus
    # (src/modules/window/wrap_Window.cpp, w_hasFocus).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.focus? # => true
    def self.focus?
      Native::Window.focus?
    end

    # Whether the pointer is over the window, matching
    # love.window.hasMouseFocus (src/modules/window/wrap_Window.cpp,
    # w_hasMouseFocus).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.mouse_focus? # => false
    def self.mouse_focus?
      Native::Window.mouse_focus?
    end

    # Whether the window is shown, matching love.window.isVisible
    # (src/modules/window/wrap_Window.cpp, w_isVisible).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.visible? # => true
    def self.visible?
      Native::Window.visible?
    end

    # Whether another window covers all of this one, matching
    # love.window.isOccluded (src/modules/window/wrap_Window.cpp,
    # w_isOccluded).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.occluded? # => false
    def self.occluded?
      Native::Window.occluded?
    end

    # Whether the window is maximized, matching love.window.isMaximized
    # (src/modules/window/wrap_Window.cpp, w_isMaximized).
    #
    # Some systems answer only after a few frames of the loop.
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.maximized? # => false
    def self.maximized?
      Native::Window.maximized?
    end

    # Whether the window is minimized, matching love.window.isMinimized
    # (src/modules/window/wrap_Window.cpp, w_isMinimized).
    #
    # Some systems answer only after a few frames of the loop.
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.minimized? # => false
    def self.minimized?
      Native::Window.minimized?
    end

    # Makes the window as large as the desktop allows, matching
    # love.window.maximize (src/modules/window/wrap_Window.cpp,
    # w_maximize). Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.maximize
    def self.maximize
      Native::Window.maximize
    end

    # Puts the window away, matching love.window.minimize
    # (src/modules/window/wrap_Window.cpp, w_minimize). Raises ThreadError
    # off the main thread.
    #
    # === Example
    #
    #   Lota::Window.minimize
    def self.minimize
      Native::Window.minimize
    end

    # Brings the window back from being maximized or minimized, matching
    # love.window.restore (src/modules/window/wrap_Window.cpp, w_restore).
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.restore
    def self.restore
      Native::Window.restore
    end

    # Raises the window and asks the system to give it keyboard focus,
    # matching love.window.focus (src/modules/window/wrap_Window.cpp,
    # w_focus). Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.focus
    def self.focus
      Native::Window.focus
    end

    # Asks the system to draw the player's attention to the window,
    # matching love.window.requestAttention
    # (src/modules/window/wrap_Window.cpp, w_requestAttention).
    #
    # [continuous] Whether to keep asking until the player focuses the
    #   window; +false+ by default.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.request_attention(true)
    def self.request_attention(continuous = false)
      Native::Window.request_attention(continuous)
    end

    # How many pixels the window's units make, as a Float, matching
    # love.window.getDPIScale (src/modules/window/wrap_Window.cpp,
    # w_getDPIScale): 2.0 on a Retina display with high DPI allowed, and
    # 1.0 when sizes count in pixels.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.dpi_scale # => 2.0
    def self.dpi_scale
      Native::Window.dpi_scale
    end

    # The scale of the window's display, whatever the window's settings,
    # as a Float, matching love.window.getNativeDPIScale
    # (src/modules/window/wrap_Window.cpp, w_getNativeDPIScale).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.native_dpi_scale # => 2.0
    def self.native_dpi_scale
      Native::Window.native_dpi_scale
    end

    # A length, or a position, in the window's units as pixels, matching
    # love.window.toPixels (src/modules/window/wrap_Window.cpp,
    # w_toPixels).
    #
    # [wx] Float or Integer length, or position across.
    # [wy] Float or Integer position down, when converting a position.
    #
    # Returns a Float for one number, and an Array (ADR 001, rule 4) of two
    # Floats for two. Raises ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Window.to_pixels(50) # => 100.0
    #   Lota::Window.to_pixels(50, 20) # => [100.0, 40.0]
    def self.to_pixels(wx, wy = nil)
      converted = Native::Window.to_pixels(wx, wy)
      wy.nil? ? converted.first : converted
    end

    # A length, or a position, in pixels as the window's units, matching
    # love.window.fromPixels (src/modules/window/wrap_Window.cpp,
    # w_fromPixels).
    #
    # [px] Float or Integer length, or position across.
    # [py] Float or Integer position down, when converting a position.
    #
    # Returns a Float for one number, and an Array (ADR 001, rule 4) of two
    # Floats for two. Raises ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Window.from_pixels(100) # => 50.0
    #   Lota::Window.from_pixels(100, 40) # => [50.0, 20.0]
    def self.from_pixels(px, py = nil)
      converted = Native::Window.from_pixels(px, py)
      py.nil? ? converted.first : converted
    end

    # The theme the system shows its windows in, as a Symbol (ADR 001,
    # rule 9), matching love.window.getSystemTheme
    # (src/modules/window/wrap_Window.cpp, w_getSystemTheme).
    #
    # It is +:unknown+, +:light+, or +:dark+. Raises ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Window.system_theme # => :dark
    def self.system_theme
      Native::Window.system_theme.to_sym
    end

    # Shows a message box, matching love.window.showMessageBox
    # (src/modules/window/wrap_Window.cpp, w_showMessageBox), which takes
    # its arguments in one of two forms.
    #
    # With a message alone, <tt>show_message_box(title, message, type,
    # attachtowindow)</tt> shows it and returns whether it could:
    #
    # [title] String shown in the box's title bar.
    # [message] String shown in the box.
    # [type] +:info+ (the default), +:warning+, or +:error+.
    # [attachtowindow] Whether the box belongs to the window; +true+ by
    #   default.
    #
    # With an Array of button names for its third argument,
    # <tt>show_message_box(title, message, buttons, type, attachtowindow,
    # enterbutton:, escapebutton:)</tt> shows them and returns which the
    # player pressed, counting from 1:
    #
    # [buttons] Array of at least one String.
    # [enterbutton] Integer button Return presses, counting from 1; the
    #   first by default.
    # [escapebutton] Integer button Escape presses; the last by default.
    #
    # LÖVE tells the forms apart by whether its third argument is a table,
    # which also holds the +enterbutton+ and +escapebutton+ settings, so
    # Lota tells them by whether it is an Array, and reads those two as
    # keywords (rule 10). Raises ArgumentError for an empty Array, an
    # unknown +type+, or +enterbutton+ or +escapebutton+ without buttons,
    # and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Window.show_message_box("Saved", "Your game was saved.")
    #   Lota::Window.show_message_box("Quit?", "Unsaved progress is lost.", %w[Quit Stay], :warning, escapebutton: 2)
    def self.show_message_box(title, message, buttons_or_type = nil, *options, enterbutton: nil, escapebutton: nil)
      raise ArgumentError, "wrong number of arguments (given #{options.size + 3}, expected 2..5)" if options.size > 2

      if buttons_or_type.is_a?(Array)
        type, attachtowindow = options
        Native::Window.show_message_box_with_buttons(title, message, buttons_or_type, enterbutton, escapebutton,
          type&.to_s, attachtowindow.nil? || !!attachtowindow)
      else
        unless enterbutton.nil? && escapebutton.nil?
          raise ArgumentError, "enterbutton and escapebutton need an Array of buttons"
        end

        raise ArgumentError, "wrong number of arguments (given #{options.size + 3}, expected 2..4)" if options.size > 1

        attachtowindow = options.first
        Native::Window.show_message_box(title, message, buttons_or_type&.to_s, attachtowindow.nil? || !!attachtowindow)
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

    # Whether the window may use the screen's full resolution where the
    # system scales it, as on a Retina display, matching
    # love.window.isHighDPIAllowed (src/modules/window/wrap_Window.cpp,
    # w_isHighDPIAllowed). +t.highdpi+ in Lota.conf sets it, and so does
    # the deprecated +t.window.highdpi+, as in LÖVE.
    #
    # === Example
    #
    #   Lota::Window.high_dpi_allowed? # => false
    def self.high_dpi_allowed?
      Native::Window.high_dpi_allowed?
    end

    # Whether the window is open, matching love.window.isOpen
    # (src/modules/window/wrap_Window.cpp, w_isOpen).
    #
    # It is +false+ until Lota::Window.set_mode first opens the window, as
    # when the settings open none (<tt>t.window = false</tt>). Raises
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Window.open? # => true
    def self.open?
      Native::Window.window_open?
    end
  end
end
