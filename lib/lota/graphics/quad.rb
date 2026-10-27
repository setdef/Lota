# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A rectangle of a texture, matching LÖVE's Quad class
    # (src/modules/graphics/Quad.h).
    #
    # Games keep many small images in one texture, a sprite sheet or a
    # tile set, and draw one part at a time. A quad names that part:
    # Lota::Graphics.draw draws a texture through it, and a
    # Lota::Graphics::SpriteBatch adds sprites of it.
    #
    # === Example
    #
    #   sheet = Lota::Graphics::Image.new("assets/tiles.png")
    #   grass = Lota::Graphics::Quad.new(0, 0, 16, 16, sheet)
    #   Lota::Graphics.draw(sheet, grass, 100, 100)
    class Quad
      include Object

      # The engine's Quad, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Quad the engine made. :nodoc:
      def self.from_native(native)
        quad = allocate
        quad.instance_variable_set(:@native, native)
        quad
      end

      # Makes a quad, matching love.graphics.newQuad
      # (src/modules/graphics/wrap_Graphics.cpp, w_newQuad).
      #
      # [x] Float or Integer left edge of the rectangle, in the texture's
      #   pixels.
      # [y] Float or Integer top edge.
      # [w] Float or Integer width.
      # [h] Float or Integer height.
      # [first] The size of the texture the rectangle is in: the
      #   Lota::Graphics::Texture itself, or its width and height as two
      #   numbers; either may follow the Integer layer of an array texture
      #   the quad shows, counting from 1, which is 1 when left out.
      #
      # LÖVE chooses the form by what follows the rectangle, in this order:
      # a texture; a layer and a texture; a layer, a width, and a height;
      # and otherwise a width and a height.
      #
      # Raises ArgumentError for fewer than five arguments or more than
      # seven, or a width without a height, TypeError for a size that is
      # neither a texture nor numbers,
      # RuntimeError with LÖVE's message when no window is open, and
      # ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::Quad.new(0, 0, 16, 16, sheet)
      #   Lota::Graphics::Quad.new(0, 0, 16, 16, 256, 256)
      #
      # :call-seq:
      #   new(x, y, w, h, texture)
      #   new(x, y, w, h, layer, texture)
      #   new(x, y, w, h, sw, sh)
      #   new(x, y, w, h, layer, sw, sh)
      def self.new(x, y, w, h, first, second = nil, third = nil)
        native = if first.is_a?(Texture)
          Native::Graphics.new_quad_of_texture(1, [x, y, w, h], first.native)
        elsif second.is_a?(Texture)
          Native::Graphics.new_quad_of_texture(first, [x, y, w, h], second.native)
        elsif third.nil?
          raise ArgumentError, "wrong number of arguments (given 5, expected 6..7)" if second.nil?

          Native::Graphics.new_quad(1, [x, y, w, h], first, second)
        else
          raise TypeError, "wrong argument type nil (expected Float)" if second.nil?

          Native::Graphics.new_quad(first, [x, y, w, h], second, third)
        end
        from_native(native)
      end

      # The rectangle the quad shows, as an Array of its left edge, top
      # edge, width, and height, each a Float, matching Quad:getViewport
      # (src/modules/graphics/wrap_Quad.cpp, w_Quad_getViewport).
      #
      # === Example
      #
      #   Lota::Graphics::Quad.new(0, 8, 16, 16, sheet).viewport # => [0.0, 8.0, 16.0, 16.0]
      def viewport
        @native.viewport
      end

      # Moves the rectangle the quad shows, matching Quad:setViewport
      # (src/modules/graphics/wrap_Quad.cpp, w_Quad_setViewport).
      #
      # [viewport] Its left edge, top edge, width, and height, then
      #   optionally the width and height of the texture it is in, as
      #   several values or one Array; the texture's size stays as it was
      #   when left out.
      #
      # Raises ArgumentError for any count of values but 4 or 6, TypeError
      # for one that is not a number, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   quad.viewport = 16, 0, 16, 16
      #   quad.viewport = 16, 0, 16, 16, 512, 512
      def viewport=(viewport)
        values = Array(viewport)
        unless values.size == 4 || values.size == 6
          raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 4 or 6)"
        end

        @native.set_viewport(values.first(4), values[4], values[5])
      end

      # The width and height of the texture the quad is in, as an Array of
      # Floats, matching Quad:getTextureDimensions
      # (src/modules/graphics/wrap_Quad.cpp, w_Quad_getTextureDimensions).
      #
      # === Example
      #
      #   Lota::Graphics::Quad.new(0, 0, 16, 16, 64, 32).texture_dimensions # => [64.0, 32.0]
      def texture_dimensions
        @native.texture_dimensions
      end

      # The layer of an array texture the quad shows, an Integer counting
      # from 1, matching Quad:getLayer (src/modules/graphics/wrap_Quad.cpp,
      # w_Quad_getLayer).
      #
      # === Example
      #
      #   Lota::Graphics::Quad.new(0, 0, 16, 16, sheet).layer # => 1
      def layer
        @native.layer
      end

      # Sets the layer of an array texture the quad shows, counting from 1,
      # matching Quad:setLayer (src/modules/graphics/wrap_Quad.cpp,
      # w_Quad_setLayer). A texture with no layers draws the same whatever
      # it is.
      #
      # Raises TypeError for a +layer+ that is not a number, and
      # ThreadError off the main thread.
      #
      # === Example
      #
      #   quad.layer = 2
      def layer=(layer)
        @native.set_layer(layer)
      end
    end
  end
end
