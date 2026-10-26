# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # An image on the graphics card, matching LÖVE's Texture class
    # (src/modules/graphics/Texture.h).
    #
    # Whatever a game draws, it draws from a texture or into one. Pixels
    # in memory are slow to draw; a texture keeps them where the graphics
    # card can reach them at once.
    #
    # LÖVE 12 has one class for every texture, where LÖVE 11 had separate
    # Image and Canvas classes. Lota::Graphics::Canvas.new makes a texture
    # you can draw into, and canvas? says whether a texture is one.
    #
    # Use it to draw an image with Lota::Graphics.draw, to read rendered
    # pixels back with Lota::Graphics.readback_texture, and as the target
    # of Lota::Graphics.canvas=.
    #
    # === Examples
    #
    #   texture = Lota::Graphics::Canvas.new(16, 16)
    #   texture.class   # => Lota::Graphics::Texture
    #   texture.canvas? # => true
    #
    #   player = Lota::Graphics::Texture.new("assets/player.png")
    #   Lota::Graphics.draw(player, 100, 100)
    class Texture
      # The engine's Texture, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Texture the engine made. Every Texture the engine hands
      # to Ruby passes through here. :nodoc:
      def self.from_native(native)
        texture = allocate
        texture.instance_variable_set(:@native, native)
        texture
      end

      # Makes a texture from an image, matching love.graphics.newTexture
      # (src/modules/graphics/wrap_Graphics.cpp, w_newTexture and
      # getImageData).
      #
      # [image] String name of an image file in the game's folder, a
      # Lota::Filesystem::FileData holding an encoded image, or a
      # Lota::Image::ImageData.
      # [canvas] Whether you can also draw into the texture, as into a
      #   canvas; +false+ by default. Like the rest of LÖVE's settings, it
      #   is a keyword, which translates LÖVE's table of settings (ADR 001,
      #   rule 10), and any value but +nil+ counts by its truthiness, as
      #   LÖVE reads a flag in the table.
      #
      # LÖVE decodes a PNG, JPEG, BMP, TGA, or one of its other formats to
      # pixels, and keeps a compressed texture format, such as DDS or
      # ASTC, compressed. A file named like "image@2x.png" holds pixels at
      # twice the density, so the texture's DPI scale is 2 and it draws at
      # half its pixel size, as LÖVE parses the name. A file name is a path
      # in the game's folder, as Lota::Graphics::Font.new reads one. LÖVE
      # also makes a texture from several images, or of a size with no
      # pixels, and takes its other settings, such as mipmaps; Lota binds
      # those later.
      #
      # Raises TypeError for anything else, RuntimeError with LÖVE's message
      # when the file cannot be read or decoded, the image or graphics
      # module is not open, or no window is, and ThreadError off the main
      # thread.
      #
      # === Examples
      #
      #   ship = Lota::Graphics::Texture.new("assets/ship.png")
      #   ship.canvas? # => false
      #
      #   paint = Lota::Graphics::Texture.new("assets/wall.png", canvas: true)
      #   paint.canvas? # => true
      def self.new(image, canvas: nil)
        canvas = !!canvas
        native = case image
        when String then Native::Graphics.new_texture_from_data(Native::Filesystem.file_data(image), canvas)
        when Filesystem::FileData then Native::Graphics.new_texture_from_data(image.native, canvas)
        when Lota::Image::ImageData then Native::Graphics.new_texture_from_image_data(image.native, canvas)
        else
          raise TypeError,
            "wrong argument type #{image.class} (expected String, Lota::Filesystem::FileData, or " \
              "Lota::Image::ImageData)"
        end
        from_native(native)
      end

      # Whether you can draw into this texture, matching Texture:isCanvas
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_isCanvas).
      #
      # A texture made by Lota::Graphics::Canvas.new always is. So
      # <tt>Lota::Graphics::Canvas === texture</tt> asks this, and a
      # +case+ can tell canvases from other textures.
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16).canvas? # => true
      def canvas?
        @native.canvas?
      end
    end
  end
end
