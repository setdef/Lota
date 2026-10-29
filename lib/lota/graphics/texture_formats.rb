# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Which pixel formats a texture can have, which
    # Lota::Graphics.texture_formats returns, translated from the table
    # love.graphics.getTextureFormats returns
    # (src/modules/graphics/wrap_Graphics.cpp, w_getTextureFormats): a
    # frozen value with a field for each of LÖVE's pixel format names
    # (ADR 001, rule 10), +true+ or +false+.
    #
    # Some names start with a capital, as LÖVE spells them; read those
    # with +[]+, as Lua reads them with brackets.
    #
    # === Example
    #
    #   formats = Lota::Graphics.texture_formats(canvas: true)
    #   formats.rgba16f  # => true
    #   formats["DXT1"]  # => false
    class TextureFormats < ::Data.define(:normal, :hdr, :r8, :r8i, :r8ui, :r16, :r16f, :r16i, :r16ui, :r32f, :r32i,
      :r32ui, :rg8, :rg8i, :rg8ui, :la8, :rg16, :rg16f, :rg16i, :rg16ui,
      :rg32f, :rg32i, :rg32ui, :rgba8, :srgba8, :bgra8, :bgra8srgb, :rgba8i,
      :rgba8ui, :rgba16, :rgba16f, :rgba16i, :rgba16ui, :rgba32f, :rgba32i,
      :rgba32ui, :rgba4, :rgb5a1, :rgb565, :rgb10a2, :rgb10a2ui, :rg11b10f,
      :stencil8, :depth16, :depth24, :depth32f, :depth24stencil8,
      :depth32fstencil8, :DXT1, :DXT1srgb, :DXT3, :DXT3srgb, :DXT5,
      :DXT5srgb, :BC4, :BC4s, :BC5, :BC5s, :BC6h, :BC6hs,
      :BC7, :BC7srgb, :PVR1rgb2, :PVR1rgb2srgb, :PVR1rgb4,
      :PVR1rgb4srgb, :PVR1rgba2, :PVR1rgba2srgb, :PVR1rgba4,
      :PVR1rgba4srgb, :ETC1, :ETC2rgb, :ETC2srgb, :ETC2rgba,
      :ETC2srgba, :ETC2rgba1, :ETC2srgba1, :EACr, :EACrs, :EACrg,
      :EACrgs, :ASTC4x4, :ASTC5x4, :ASTC5x5, :ASTC6x5, :ASTC6x6,
      :ASTC8x5, :ASTC8x6, :ASTC8x8, :ASTC10x5, :ASTC10x6,
      :ASTC10x8, :ASTC10x10, :ASTC12x10, :ASTC12x12, :ASTC4x4srgb,
      :ASTC5x4srgb, :ASTC5x5srgb, :ASTC6x5srgb, :ASTC6x6srgb,
      :ASTC8x5srgb, :ASTC8x6srgb, :ASTC8x8srgb, :ASTC10x5srgb,
      :ASTC10x6srgb, :ASTC10x8srgb, :ASTC10x10srgb, :ASTC12x10srgb,
      :ASTC12x12srgb)
      include Record
    end
  end
end
