# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes a cube Lota::Graphics::Texture, as LÖVE 12's
    # love.graphics.newCubeImage makes a Texture, and matches the textures
    # of its type.
    #
    # A cube texture has six square faces, which a shader samples by
    # direction, as for a sky or a reflection.
    #
    # LÖVE 12 has no CubeImage class: newCubeImage makes a Texture whose
    # type is +:cube+. So CubeImage is a module, as Canvas is, whose +new+
    # returns a Texture and whose <tt>CubeImage === texture</tt> asks
    # whether the texture's type is +:cube+.
    #
    # === Example
    #
    #   sky = Lota::Graphics::CubeImage.new("assets/sky.png")
    #   sky.texture_type # => :cube
    module CubeImage
      # Creates a cube texture of +images+, or of a size, matching
      # love.graphics.newCubeImage (src/modules/graphics/wrap_Graphics.cpp,
      # w_newCubeImage), which LÖVE 12 makes with w_newCubeTexture.
      #
      # [images] One image, as Lota::Graphics::Texture.new takes it, that
      #   holds all six faces, laid out as love.image cuts them; an Array
      #   of six faces, each an image or an Array of its mipmaps; or an
      #   Array of six square images.
      # [size] Integer width and height of each face, in place of images,
      #   for a texture with no pixels yet.
      # [settings] LÖVE's settings table, as keywords, as for
      #   Lota::Graphics::Texture.new.
      #
      # Raises RuntimeError ("Cubemap images must have 6 faces.") for an
      # Array of mipmaps that does not hold six faces, and what
      # Lota::Graphics::Texture.new raises.
      #
      # === Example
      #
      #   Lota::Graphics::CubeImage.new("assets/sky.png", mipmaps: false)
      #
      # :call-seq:
      #   new(images, **settings)
      #   new(size, **settings)
      def self.new(*arguments, **settings)
        TextureSettings.check_count(arguments, 1..1)
        native = Native::TextureSettings.new
        native.set_type("cube")
        images = arguments.first
        if TextureSettings.number?(images)
          native.width = native.height = TextureSettings.size(images, "size")
          TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
          return Texture.from_native(Native::Graphics.new_empty_texture(native))
        end

        dpiscaleset = TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
        Texture.from_native(Native::Graphics.new_cube_texture(native, dpiscaleset, TextureSettings.images(images)))
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:cube+, as newCubeImage makes.
      #
      # === Example
      #
      #   Lota::Graphics::CubeImage === Lota::Graphics::Canvas.new(8, 8) # => false
      def self.===(object)
        case object
        when Texture then object.texture_type == :cube
        else false
        end
      end
    end
  end
end
