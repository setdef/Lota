# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

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
    # [canvas] Lota::Graphics::Canvas to draw into, or +nil+ for the window.
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
    # [texture] Lota::Graphics::Canvas to read.
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
  end
end
