# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes a volume Lota::Graphics::Texture, as
    # love.graphics.newVolumeTexture makes a Texture, and matches the
    # textures of its type.
    #
    # A volume texture is three-dimensional: its layers are slices of one
    # block, which a shader samples between, as for a color grading table.
    #
    # LÖVE has no VolumeTexture class: newVolumeTexture makes a Texture
    # whose type is +:volume+. So VolumeTexture is a module, as Canvas is,
    # whose +new+ returns a Texture and whose
    # <tt>VolumeTexture === texture</tt> asks whether the texture's type is
    # +:volume+.
    #
    # === Example
    #
    #   grade = Lota::Graphics::VolumeTexture.new(%w[lut1.png lut2.png lut3.png])
    #   grade.depth # => 3
    module VolumeTexture
      # Creates a volume texture of +images+, or of a size, matching
      # love.graphics.newVolumeTexture
      # (src/modules/graphics/wrap_Graphics.cpp, w_newVolumeTexture).
      #
      # [images] An Array of layers, each what Lota::Graphics::Texture.new
      #   takes for one image; an Array of mipmaps, each an Array of
      #   layers; or one image, whose layers love.image cuts from it.
      # [width] Integer width, in place of images, for a texture with no
      #   pixels yet, followed by its Integer height and layer count.
      # [settings] LÖVE's settings table, as keywords, as for
      #   Lota::Graphics::Texture.new.
      #
      # Raises what Lota::Graphics::Texture.new raises.
      #
      # === Example
      #
      #   Lota::Graphics::VolumeTexture.new(%w[a.png b.png], mipmaps: false)
      #
      # :call-seq:
      #   new(images, **settings)
      #   new(width, height, layers, **settings)
      def self.new(*arguments, **settings)
        native = Native::TextureSettings.new
        native.set_type("volume")
        images = arguments.first
        if TextureSettings.number?(images)
          TextureSettings.read_size(native, arguments, 3..3, nil)
          TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
          return Texture.__send__(:from_native, Native::Graphics.new_empty_texture(native))
        end

        TextureSettings.check_count(arguments, 1..1)
        dpiscaleset = TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
        Texture.__send__(:from_native, Native::Graphics.new_volume_texture(native, dpiscaleset, TextureSettings.images(images)))
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:volume+, as newVolumeTexture makes.
      #
      # === Example
      #
      #   Lota::Graphics::VolumeTexture === Lota::Graphics::Canvas.new(8, 8) # => false
      def self.===(object)
        case object
        when Texture then object.texture_type == :volume
        else false
        end
      end
    end
  end
end
