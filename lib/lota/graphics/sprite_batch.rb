# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Many sprites of one texture, drawn at once, matching LÖVE's
    # SpriteBatch class (src/modules/graphics/SpriteBatch.h).
    #
    # Each call to Lota::Graphics.draw costs the time of a call from Ruby
    # into the engine, and the graphics card's time to start drawing. A
    # batch keeps its sprites' places on the graphics card, so a tile map
    # or a swarm of particles draws in one call, however many sprites it
    # has. It is the way to draw many sprites, in Lota as in LÖVE.
    #
    # Add each sprite once, with add, change it with set when it moves,
    # and draw the whole batch with Lota::Graphics.draw.
    #
    # === Example
    #
    #   tiles = Lota::Graphics::Image.new("assets/tiles.png")
    #   grass = Lota::Graphics::Quad.new(0, 0, 16, 16, tiles)
    #   map = Lota::Graphics::SpriteBatch.new(tiles, 40 * 30)
    #   40.times { |x| 30.times { |y| map.add(grass, x * 16, y * 16) } }
    #
    #   def Lota.draw = Lota::Graphics.draw(map)
    class SpriteBatch
      include Object

      # The engine's SpriteBatch, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a SpriteBatch the engine made. :nodoc:
      def self.from_native(native)
        batch = allocate
        batch.instance_variable_set(:@native, native)
        batch
      end

      # Makes a batch, matching love.graphics.newSpriteBatch
      # (src/modules/graphics/wrap_Graphics.cpp, w_newSpriteBatch).
      #
      # [texture] Lota::Graphics::Texture the sprites are drawn from.
      # [size] Integer number of sprites the batch holds, 1000 when +nil+
      #   or left out. LÖVE grows it when a sprite is added to a full batch.
      # [usage] How often the sprites change, which tells the graphics card
      #   where to keep them: +:dynamic+ (the default when left out),
      #   +:static+, or +:stream+.
      #
      # Raises TypeError for a +texture+ that is not a Texture,
      # ArgumentError for an unknown +usage+, RuntimeError with LÖVE's
      # message when no window is open, and ThreadError off the main
      # thread.
      #
      # === Examples
      #
      #   Lota::Graphics::SpriteBatch.new(tiles)
      #   Lota::Graphics::SpriteBatch.new(tiles, 5000, :static)
      def self.new(texture, size = nil, *usage)
        raise ArgumentError, "wrong number of arguments (given #{usage.size + 2}, expected 1..3)" if usage.size > 1
        raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.is_a?(Texture)

        from_native(Native::Graphics.new_sprite_batch(texture.native, size, usage.empty? ? nil : EnumName.of(usage.first)))
      end

      # Adds a sprite, matching SpriteBatch:add
      # (src/modules/graphics/wrap_SpriteBatch.cpp, w_SpriteBatch_add), and
      # returns its Integer index, counting from 1, for set.
      #
      # [quad] Lota::Graphics::Quad of the part of the texture the sprite
      #   shows; the whole texture when left out.
      # [placement] Where the sprite goes, as Lota::Graphics.draw places a
      #   texture: its position, angle, scale, origin, and shear, each
      #   taking its default when +nil+ or left out.
      #
      # :call-seq:
      #   add(x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
      #   add(quad, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
      #
      # Raises ArgumentError for more than nine numbers, TypeError for a
      # +nil+ in place of a quad with numbers after it, as LÖVE raises, or
      # for a number of the wrong type, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   batch.add(100, 50)
      #   batch.add(grass, 16, 0, 0, 2) # twice the size
      def add(quad = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil, ky = nil)
        placement = Graphics.placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky)
        @native.add(quad.is_a?(Quad) ? quad.native : nil, placement)
      end

      # Replaces the sprite at +index+, counting from 1, as add made it,
      # matching SpriteBatch:set (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_set). It takes the quad and placement add takes.
      #
      # Raises what add raises, and RuntimeError with LÖVE's message for an
      # index the batch does not hold.
      #
      # === Example
      #
      #   batch.set(id, grass, player_x, player_y)
      def set(index, quad = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil, ky = nil)
        placement = Graphics.placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky)
        @native.set(index, quad.is_a?(Quad) ? quad.native : nil, placement)
      end

      # Removes every sprite, matching SpriteBatch:clear
      # (src/modules/graphics/wrap_SpriteBatch.cpp, w_SpriteBatch_clear).
      #
      # === Example
      #
      #   batch.clear
      #   batch.count # => 0
      def clear
        @native.clear
      end

      # Sends sprites added or set since the batch was last drawn to the
      # graphics card now, rather than when the batch is next drawn,
      # matching SpriteBatch:flush (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_flush).
      #
      # === Example
      #
      #   batch.flush
      def flush
        @native.flush
      end

      # Sets the texture the sprites are drawn from, matching
      # SpriteBatch:setTexture (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_setTexture).
      #
      # Raises TypeError for a +texture+ that is not a Texture,
      # RuntimeError with LÖVE's message for a texture of another kind, such
      # as an array texture for a batch of a 2D one, and ThreadError off the
      # main thread.
      #
      # === Example
      #
      #   batch.texture = night_tiles
      def texture=(texture)
        raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.is_a?(Texture)

        @native.set_texture(texture.native)
      end

      # The Lota::Graphics::Texture the sprites are drawn from, matching
      # SpriteBatch:getTexture (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_getTexture).
      #
      # === Example
      #
      #   batch.texture.width # => 256
      def texture
        Texture.from_native(@native.texture)
      end

      # Sets the color the sprites added or set from now on are drawn in,
      # matching SpriteBatch:setColor
      # (src/modules/graphics/wrap_SpriteBatch.cpp, w_SpriteBatch_setColor).
      #
      # [color] Red, green, blue, and optionally alpha, each a Float or
      #   Integer from 0 to 1, as several values or one Array; alpha is 1
      #   when left out.
      #
      # Sprites already in the batch keep their color. The color drawing
      # is tinted with, Lota::Graphics.color, tints the whole batch too.
      #
      # Raises ArgumentError for any count of components but 3 or 4,
      # TypeError for one that is not a number, and ThreadError off the main
      # thread.
      #
      # === Example
      #
      #   batch.color = 1, 0, 0 # red from now on
      def color=(color)
        components = Array(color)
        unless components.size == 3 || components.size == 4
          raise ArgumentError, "wrong number of arguments (given #{components.size}, expected 3 or 4)"
        end

        @native.set_color(components.fetch(0), components.fetch(1), components.fetch(2), components.fetch(3, 1.0))
      end

      # The color sprites are added in, as an Array of red, green, blue,
      # and alpha, each a Float, matching SpriteBatch:getColor
      # (src/modules/graphics/wrap_SpriteBatch.cpp, w_SpriteBatch_getColor).
      # It starts as opaque white.
      #
      # === Example
      #
      #   batch.color # => [1.0, 1.0, 1.0, 1.0]
      def color
        @native.color
      end

      # The Integer number of sprites in the batch, matching
      # SpriteBatch:getCount (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_getCount).
      #
      # === Example
      #
      #   batch.count # => 1200
      def count
        @native.count
      end

      # The Integer number of sprites the batch holds before it grows,
      # matching SpriteBatch:getBufferSize
      # (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_getBufferSize).
      #
      # === Example
      #
      #   Lota::Graphics::SpriteBatch.new(tiles, 5000).buffer_size # => 5000
      def buffer_size
        @native.buffer_size
      end

      # Draws only some of the sprites, matching SpriteBatch:setDrawRange
      # (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_setDrawRange).
      #
      # [range] The Integer index of the first sprite to draw, counting from
      #   1, and the Integer number of sprites, as two values or an Array;
      #   or +nil+ to draw every sprite again, as LÖVE's form without
      #   arguments does.
      #
      # Raises ArgumentError for any count of values but 2, RuntimeError
      # with LÖVE's message for a range that starts before the first sprite
      # or counts none, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   batch.draw_range = 1, 100
      #   batch.draw_range = nil
      def draw_range=(range)
        if range.nil?
          @native.set_draw_range
        else
          values = Array(range)
          raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 2)" unless values.size == 2

          @native.set_draw_range(values.fetch(0), values.fetch(1))
        end
      end

      # The sprites drawn, as an Array of the index of the first, counting
      # from 1, and how many, or +nil+ when every sprite is drawn, matching
      # SpriteBatch:getDrawRange (src/modules/graphics/wrap_SpriteBatch.cpp,
      # w_SpriteBatch_getDrawRange), which returns nothing then.
      #
      # === Example
      #
      #   batch.draw_range = 1, 100
      #   batch.draw_range # => [1, 100]
      def draw_range
        @native.draw_range
      end
    end
  end
end
