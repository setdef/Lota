# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes a Lota::Graphics::Texture you can draw into, as LÖVE 12's
    # love.graphics.newCanvas makes a Texture, and matches the textures it
    # makes.
    #
    # Drawing normally goes straight to the window and is gone by the next
    # frame. Effects such as lighting, a minimap, or a screen-wide shader
    # need a picture they can draw once, keep, and use again.
    #
    # A canvas is that picture. LÖVE 12 has no Canvas class: a canvas is a
    # Texture made to be drawn into. So Canvas is a module, not a class.
    # Canvas.new returns a Texture, and <tt>Canvas === texture</tt> is
    # true for a texture you can draw into, so <tt>when Canvas</tt> works
    # in a +case+.
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
    #
    #   # Telling canvases from other textures.
    #   case texture
    #   when Lota::Graphics::Canvas then draw_into(texture)
    #   end
    module Canvas
      # Creates a Lota::Graphics::Texture to draw into, matching
      # love.graphics.newCanvas(width, height, settings)
      # (src/modules/graphics/wrap_Graphics.cpp, w_newCanvas and
      # luax_checktexturesettings).
      #
      # [width] Integer width, in units of the screen's DPI scale; the
      #   window's width when +nil+ or left out.
      # [height] Integer height, likewise; the window's height when +nil+
      #   or left out.
      # [msaa] Integer count of antialiasing samples drawing into it takes
      #   per pixel, which smooths the edges of shapes; 1, which does not,
      #   by default. Like the rest of LÖVE's settings, it is a keyword,
      #   which translates LÖVE's table of settings (ADR 001, rule 10).
      #
      # The texture takes the screen's DPI scale, so on a high-density
      # display it has more pixels than its width and height say. It starts
      # out transparent black (src/modules/graphics/metal/Texture.mm and
      # opengl/Texture.cpp clear every new canvas). LÖVE reads +msaa+ as it
      # reads a number in its table, so a value that is not a number leaves
      # the default, and the graphics card may use fewer samples than asked
      # for. LÖVE also takes a layer count and its other settings, such as
      # the pixel format; Lota binds those later.
      #
      # Raises RuntimeError when no window is open, and ThreadError off the
      # main thread.
      #
      # === Examples
      #
      #   minimap = Lota::Graphics::Canvas.new(128, 128)
      #   minimap.class # => Lota::Graphics::Texture
      #
      #   smooth = Lota::Graphics::Canvas.new(800, 600, msaa: 4)
      def self.new(width = nil, height = nil, msaa: nil)
        msaa = (msaa.is_a?(Integer) || msaa.is_a?(Float)) ? msaa.to_i : nil
        Texture.from_native(Native::Graphics.new_canvas(width, height, msaa))
      end

      # Whether +object+ is a Lota::Graphics::Texture you can draw into,
      # as Texture#canvas? says, however you got it. Anything else is not
      # a canvas.
      #
      # === Example
      #
      #   Lota::Graphics::Canvas === Lota::Graphics::Canvas.new(16, 16) # => true
      #   Lota::Graphics::Canvas === :canvas                           # => false
      def self.===(object)
        case object
        when Texture then object.canvas?
        else false
        end
      end
    end
  end
end
