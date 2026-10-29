# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes a Lota::Graphics::Texture from an image, as LÖVE 12's
    # love.graphics.newImage makes a Texture, and matches the textures it
    # makes.
    #
    # Most of what a game draws starts as a picture in a file: a sprite, a
    # tile, a background. LÖVE 11 loaded one into an Image, a class of its
    # own; LÖVE 12 has one Texture class for every texture, and keeps
    # newImage as another name for newTexture
    # (src/modules/graphics/wrap_Graphics.cpp:1251-1255).
    #
    # So Image is a module, as Canvas is, not a class. Image.new returns
    # a Texture, made as Lota::Graphics::Texture.new makes it, from the
    # same arguments. A texture remembers nothing of which factory made
    # it, and newTexture's canvas setting can make an image you draw into,
    # so <tt>Image === texture</tt> is true for every Texture, canvases
    # included, and <tt>when Image</tt> works in a +case+.
    #
    # Use it to translate a LÖVE game's newImage, and to load the pictures
    # your game draws with Lota::Graphics.draw.
    #
    # === Examples
    #
    #   ship = Lota::Graphics::Image.new("assets/ship.png")
    #   ship.class # => Lota::Graphics::Texture
    #   Lota::Graphics.draw(ship, 100, 100)
    #
    #   case texture
    #   when Lota::Graphics::Image then Lota::Graphics.draw(texture)
    #   end
    module Image
      # Creates a Lota::Graphics::Texture from +image+, or of a size,
      # matching love.graphics.newImage
      # (src/modules/graphics/wrap_Graphics.cpp, w_newImage), which LÖVE 12
      # makes with w_newTexture.
      #
      # [image] String name of an image file in the game's folder, a
      #   Lota::Filesystem::FileData holding an encoded image, a
      #   Lota::Image::ImageData, or an Array of them, its mipmaps; or a
      #   width, a height, and a layer count, as for
      #   Lota::Graphics::Texture.new.
      # [settings] LÖVE's settings table, as keywords, as for
      #   Lota::Graphics::Texture.new.
      #
      # Raises what Lota::Graphics::Texture.new raises.
      #
      # === Examples
      #
      #   Lota::Graphics::Image.new("assets/ship.png").canvas? # => false
      #   card = Lota::Graphics::Image.new("assets/card.png", mipmaps: true)
      #
      # :call-seq:
      #   new(image, **settings)
      #   new(width, height, layers = nil, **settings)
      def self.new(*, **settings)
        Texture.new(*, **settings)
      end

      # Whether +object+ is a Lota::Graphics::Texture: newImage makes
      # every kind of 2D texture newTexture makes, canvases included, and a
      # texture records nothing of which factory made it. Anything else is
      # not an image.
      #
      # === Example
      #
      #   Lota::Graphics::Image === Lota::Graphics::Canvas.new(16, 16) # => true
      #   Lota::Graphics::Image === :image                            # => false
      def self.===(object)
        case object
        when Texture then true
        else false
        end
      end
    end
  end
end
