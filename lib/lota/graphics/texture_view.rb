# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes a view of a Lota::Graphics::Texture, as
    # love.graphics.newTextureView makes a Texture, and matches what it
    # makes.
    #
    # A view shares another texture's pixels, seen through a range of its
    # mipmaps or layers, another texture type, or another pixel format the
    # texture's +viewformats+ setting allows, as for drawing one layer of
    # an array texture as a 2D texture, or reading an sRGB texture as
    # linear.
    #
    # LÖVE has no TextureView class, and cannot tell a view from any other
    # Texture. So TextureView is a module, as Image is (ADR 001, rule 2),
    # whose +new+ returns a Texture and whose <tt>TextureView ===
    # object</tt> is true of every Texture.
    #
    # === Example
    #
    #   frames = Lota::Graphics::ArrayTexture.new(%w[a.png b.png])
    #   second = Lota::Graphics::TextureView.new(frames, type: :"2d", layerstart: 2)
    module TextureView
      # Creates a view of +texture+, matching love.graphics.newTextureView
      # (src/modules/graphics/wrap_Graphics.cpp, w_newTextureView), whose
      # settings table becomes keywords (ADR 001, rule 10); each is the
      # texture's own when left out.
      #
      # [texture] Lota::Graphics::Texture the view sees.
      # [format] Pixel format the view reads, its own or one the texture's
      #   +viewformats+ allows.
      # [type] Texture type, such as <tt>:"2d"</tt> for one layer of an
      #   array texture.
      # [mipmapstart] Integer first mipmap, counting from 1.
      # [mipmapcount] Integer number of mipmaps.
      # [layerstart] Integer first layer or face, counting from 1.
      # [layers] Integer number of layers.
      # [debugname] String the graphics debugger shows.
      #
      # Raises TypeError for a +texture+ that is not a Texture,
      # ArgumentError for an unknown format or type, RuntimeError with
      # LÖVE's message for a view the texture cannot give, and ThreadError
      # off the main thread.
      #
      # === Example
      #
      #   Lota::Graphics::TextureView.new(canvas, format: :srgba8)
      def self.new(texture, format: nil, type: nil, mipmapstart: nil, mipmapcount: nil, layerstart: nil, layers: nil,
        debugname: nil
      )
        raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.is_a?(Texture)

        settings = [
          format && EnumName.of(format),
          type && EnumName.of(type),
          mipmapstart,
          mipmapcount,
          layerstart,
          layers,
          debugname,
]
        Texture.__send__(:from_native, Native::Graphics.new_texture_view(texture.__send__(:native), settings))
      end

      # Whether +object+ is a Lota::Graphics::Texture, which every view is,
      # and which LÖVE cannot tell from a view.
      #
      # === Example
      #
      #   Lota::Graphics::TextureView === Lota::Graphics::Canvas.new(8, 8) # => true
      def self.===(object)
        case object
        when Texture then true
        else false
        end
      end
    end
  end
end
