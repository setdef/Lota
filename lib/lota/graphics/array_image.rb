# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes an array Lota::Graphics::Texture, as LÖVE 12's
    # love.graphics.newArrayImage makes a Texture, and matches the textures
    # of its type.
    #
    # An array texture holds several images of one size as its layers,
    # which Lota::Graphics.draw_layer draws one at a time and a shader can
    # pick among, as for a sheet of animation frames.
    #
    # LÖVE 12 has no ArrayImage class: newArrayImage makes a Texture whose
    # type is +:array+. So ArrayImage is a module, as Canvas is, whose
    # +new+ returns a Texture and whose <tt>ArrayImage === texture</tt>
    # asks whether the texture's type is +:array+.
    #
    # === Example
    #
    #   frames = Lota::Graphics::ArrayImage.new(%w[walk1.png walk2.png walk3.png])
    #   frames.layer_count # => 3
    #   Lota::Graphics.draw_layer(frames, 2, 100, 100)
    module ArrayImage
      # Creates an array texture of +images+, or of a size, matching
      # love.graphics.newArrayImage
      # (src/modules/graphics/wrap_Graphics.cpp, w_newArrayImage), which
      # LÖVE 12 makes with w_newArrayTexture.
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
      #   Lota::Graphics::ArrayImage.new(%w[a.png b.png], mipmaps: true)
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
          return Texture.from_native(Native::Graphics.new_empty_texture(native))
        end

        TextureSettings.check_count(arguments, 1..1)
        dpiscaleset = TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
        Texture.from_native(Native::Graphics.new_array_texture(native, dpiscaleset, TextureSettings.images(images)))
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:array+, as newArrayImage makes.
      #
      # === Example
      #
      #   Lota::Graphics::ArrayImage === Lota::Graphics::Canvas.new(8, 8, 2) # => true
      def self.===(object)
        case object
        when Texture then object.texture_type == :array
        else false
        end
      end
    end
  end
end
