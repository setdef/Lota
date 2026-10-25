# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "graphics/texture"
require_relative "graphics/canvas"

module Lota
  # Drawing, translated from love.graphics.
  #
  # Everything a player sees passes through one graphics module. It owns
  # the window's drawing surface and a stack of state: where drawing goes,
  # in what color, through what transform. LÖVE keeps that module on the
  # main thread, because macOS draws windows only there.
  #
  # Lota::Graphics drives LÖVE's own renderer, so a frame drawn here
  # matches the same frame drawn in LÖVE. Its methods raise ThreadError
  # when called anywhere but the process's main thread, the one that
  # started Ruby.
  #
  # Use it to clear the screen or a canvas, to choose where drawing goes,
  # and to read pixels back.
  #
  # === Examples
  #
  #   # Clear a canvas to yellow and read it back.
  #   canvas = Lota::Graphics::Canvas.new(16, 16)
  #   Lota::Graphics.canvas = canvas
  #   Lota::Graphics.clear(1, 1, 0, 1)
  #   Lota::Graphics.canvas = nil
  #   pixels = Lota::Graphics.readback_texture(canvas)
  #
  #   # Clear whatever is the target to transparent black.
  #   Lota::Graphics.clear
  module Graphics
    # Sends drawing to +canvas+, or back to the window when +canvas+ is
    # +nil+, matching love.graphics.setCanvas
    # (src/modules/graphics/wrap_Graphics.cpp, w_setCanvas).
    #
    # [canvas] Lota::Graphics::Texture to draw into, made by
    #   Lota::Graphics::Canvas.new, or +nil+ for the window.
    #
    # Everything drawn or cleared afterward lands on the canvas until you
    # set another target. The engine holds on to the active canvas, so it
    # survives even if you drop every reference to it. A canvas cannot be
    # drawn while it is the target. <tt>canvas = nil</tt> is LÖVE's
    # setCanvas() with no arguments. LÖVE also takes several canvases at
    # once, a mipmap level, and a table of options; Lota binds those forms
    # later.
    #
    # Raises RuntimeError with LÖVE's message when the engine refuses the
    # target, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.canvas = shadow_map
    #   draw_shadows
    #   Lota::Graphics.canvas = nil
    def self.canvas=(canvas)
      if canvas
        Native::Graphics.set_canvas(canvas.native)
      else
        Native::Graphics.reset_canvas
      end
    end

    # Fills the active canvas, or the window, with one color, matching
    # love.graphics.clear (src/modules/graphics/wrap_Graphics.cpp, w_clear).
    #
    # [red] Float or Integer, from 0 to 1.
    # [green] Float or Integer, from 0 to 1.
    # [blue] Float or Integer, from 0 to 1.
    # [alpha] Float or Integer, from 0 to 1; 1 when left out.
    #
    # With no arguments it clears to transparent black. Either way it also
    # clears the stencil buffer to 0 and the depth buffer to 1. LÖVE
    # reads each component as a single-precision float, and so does Lota.
    # The scissor rectangle, once Lota binds it, bounds what gets cleared.
    # LÖVE also clears several canvases to different colors and chooses
    # whether to clear stencil and depth; Lota binds those forms later.
    #
    # Raises ArgumentError for any count of components but 0, 3, or 4, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.clear(0.1, 0.1, 0.2)    # a dark blue background
    #   Lota::Graphics.clear(1, 1, 0, 0.5)     # half-transparent yellow
    #   Lota::Graphics.clear                   # transparent black
    def self.clear(*color)
      case color.size
      when 0 then Native::Graphics.clear(0.0, 0.0, 0.0, 0.0)
      when 3, 4 then Native::Graphics.clear(color.fetch(0), color.fetch(1), color.fetch(2), color.fetch(3, 1.0))
      else raise ArgumentError, "wrong number of arguments (given #{color.size}, expected 0, 3, or 4)"
      end
    end

    # Copies every pixel of +texture+ back from the graphics card into a
    # new Lota::Image::ImageData, matching love.graphics.readbackTexture
    # (src/modules/graphics/wrap_Graphics.cpp, w_readbackTexture).
    #
    # [texture] Lota::Graphics::Texture to read, such as a canvas.
    #
    # The copy waits for the graphics card to finish drawing, so it is
    # slow; read back for tests, screenshots, and tools, not every frame.
    # LÖVE also reads one slice, mipmap, or rectangle, and into an
    # ImageData you already have; Lota binds those forms later.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   pixels = Lota::Graphics.readback_texture(canvas)
    #   pixels.pixel(0, 0) # => [1.0, 1.0, 0.0, 1.0]
    def self.readback_texture(texture)
      Image::ImageData.from_native(Native::Graphics.readback_texture(texture.native))
    end

    # Whether drawing reaches the screen, matching love.graphics.isActive
    # (src/modules/graphics/wrap_Graphics.cpp, w_isActive).
    #
    # The graphics module is only completely active when there is an open
    # window, a context to draw with, and the system has not put the game in
    # the background. Lota's loop draws a frame only while this is +true+.
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.active? # => true
    def self.active?
      Native::Graphics.active?
    end

    # Resets the current transformation, matching love.graphics.origin
    # (src/modules/graphics/wrap_Graphics.cpp, w_origin).
    #
    # Afterward, (0, 0) is the window's top-left corner again, with no
    # rotation or scale. Lota's loop calls it before each draw. Raises
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.origin
    def self.origin
      Native::Graphics.origin
    end

    # The color the loop clears the window to before each draw, as an
    # Array of red, green, blue, and alpha, each from 0.0 to 1.0, matching
    # love.graphics.getBackgroundColor
    # (src/modules/graphics/wrap_Graphics.cpp, w_getBackgroundColor).
    #
    # It starts as opaque black. Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   red, green, blue, alpha = Lota::Graphics.background_color # => [0.0, 0.0, 0.0, 1.0]
    def self.background_color
      Native::Graphics.background_color
    end

    # Shows what was drawn since the last present, matching
    # love.graphics.present (src/modules/graphics/wrap_Graphics.cpp,
    # w_present).
    #
    # Drawing goes to a hidden buffer, so the player never sees a frame
    # half drawn; presenting swaps it onto the screen. Lota's loop presents
    # once a frame, after your draw callback. It does nothing while the
    # module is not active. Raises RuntimeError while a canvas is the
    # target, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.clear(0, 0, 0)
    #   Lota::Graphics.present
    def self.present
      Native::Graphics.present
    end

    # The window's width, in units of the screen's DPI scale, matching
    # love.graphics.getWidth (src/modules/graphics/wrap_Graphics.cpp,
    # w_getWidth).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.width # => 800
    def self.width
      Native::Graphics.width
    end

    # The window's height, in units of the screen's DPI scale, matching
    # love.graphics.getHeight (src/modules/graphics/wrap_Graphics.cpp,
    # w_getHeight).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.height # => 600
    def self.height
      Native::Graphics.height
    end

    # The window's width and height, as an Array, matching
    # love.graphics.getDimensions (src/modules/graphics/wrap_Graphics.cpp,
    # w_getDimensions).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   width, height = Lota::Graphics.dimensions # => [800, 600]
    def self.dimensions
      [Native::Graphics.width, Native::Graphics.height]
    end
  end
end
