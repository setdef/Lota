# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A texture you can draw into, then draw or read like any image.
    #
    # Drawing normally goes straight to the window and is gone by the next
    # frame. Effects such as lighting, a minimap, or a screen-wide shader
    # need a picture they can draw once, keep, and use again.
    #
    # A Canvas is that picture. Point Lota::Graphics.canvas= at it, draw,
    # then point drawing back at the window.
    #
    # Use it to render off-screen, to build an image once and reuse it,
    # and to read rendered pixels back with Lota::Graphics.readback_texture.
    #
    # === Examples
    #
    #   # A canvas the size of the window.
    #   canvas = Lota::Graphics::Canvas.new
    #
    #   # A 16 by 16 canvas, cleared to yellow.
    #   canvas = Lota::Graphics::Canvas.new(16, 16)
    #   Lota::Graphics.canvas = canvas
    #   Lota::Graphics.clear(1, 1, 0, 1)
    #   Lota::Graphics.canvas = nil
    class Canvas
      # The engine's Texture, for Lota's own modules. :nodoc:
      attr_reader :native

      # Creates a canvas, matching love.graphics.newCanvas(width, height)
      # (src/modules/graphics/wrap_Graphics.cpp, w_newCanvas).
      #
      # [width] Integer width, in units of the screen's DPI scale; the
      #   window's width when +nil+ or left out.
      # [height] Integer height, likewise; the window's height when +nil+
      #   or left out.
      #
      # The canvas takes the screen's DPI scale, so on a high-density
      # display it has more pixels than its width and height say. It starts
      # out transparent black (src/modules/graphics/metal/Texture.mm and
      # opengl/Texture.cpp clear every new canvas). LÖVE also takes a layer
      # count and a table of settings; Lota binds those forms later.
      #
      # Raises RuntimeError when no window is open, and ThreadError off the
      # main thread.
      #
      # === Example
      #
      #   minimap = Lota::Graphics::Canvas.new(128, 128)
      def initialize(width = nil, height = nil)
        @native = Native::Graphics.new_canvas(width, height)
      end
    end
  end
end
