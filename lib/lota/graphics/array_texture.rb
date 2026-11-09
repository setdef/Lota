# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes an array Lota::Graphics::Texture, as
    # love.graphics.newArrayTexture makes a Texture, and matches the textures
    # of its type.
    #
    # An array texture holds several images of one size as its layers,
    # which Lota::Graphics.draw_layer draws one at a time and a shader can
    # pick among, as for a sheet of animation frames.
    #
    # LÖVE has no ArrayTexture class: newArrayTexture makes a Texture whose
    # type is +:array+. So ArrayTexture is a module, as Canvas is, whose
    # +new+ returns a Texture and whose <tt>ArrayTexture === texture</tt>
    # asks whether the texture's type is +:array+.
    #
    # === Example
    #
    #   frames = Lota::Graphics::ArrayTexture.new(%w[walk1.png walk2.png walk3.png])
    #   frames.layer_count # => 3
    #   Lota::Graphics.draw_layer(frames, 2, 100, 100)
    module ArrayTexture
      # Creates an array texture of +images+, or of a size, matching
      # love.graphics.newArrayTexture
      # (src/modules/graphics/wrap_Graphics.cpp, w_newArrayTexture).
      #
      # [images] An Array of layers, each what Lota::Graphics::Texture.new
      #   takes for one image, or an Array of a layer's mipmaps; or one
      #   image, which holds a single layer.
      # [width] Integer width, in place of images, for a texture with no
      #   pixels yet, followed by its Integer height and layer count.
      # [settings] LÖVE's settings table, as keywords, as for
      #   Lota::Graphics::Texture.new.
      #
      # Every layer must have the same size. Raises what
      # Lota::Graphics::Texture.new raises.
      #
      # === Example
      #
      #   Lota::Graphics::ArrayTexture.new(%w[a.png b.png], mipmaps: true)
      #
      # :call-seq:
      #   new(images, **settings)
      #   new(width, height, layers, **settings)
      def self.new(*arguments, **settings)
        native = Native::TextureSettings.new
        native.set_type("array")
        images = arguments.first
        if TextureSettings.number?(images)
          TextureSettings.read_size(native, arguments, 3..3, nil)
          TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
          return Texture.__send__(:from_native, Native::Graphics.new_empty_texture(native))
        end

        TextureSettings.check_count(arguments, 1..1)
        dpiscaleset = TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
        Texture.__send__(:from_native, Native::Graphics.new_array_texture(native, dpiscaleset, TextureSettings.images(images)))
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:array+, as newArrayTexture makes.
      #
      # === Example
      #
      #   Lota::Graphics::ArrayTexture === Lota::Graphics::Canvas.new(8, 8, 2) # => true
      def self.===(object)
        case object
        when Texture then object.texture_type == :array
        else false
        end
      end
    end
  end
end
