# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Which pixel formats a canvas can have, which the deprecated
    # Lota::Graphics.canvas_formats returns, translated from the table
    # love.graphics.getCanvasFormats returns
    # (src/modules/graphics/wrap_Graphics.cpp, w_getCanvasFormats): a
    # frozen value with a field for each of LÖVE's names of a pixel format
    # that is not compressed (ADR 001, rule 28), +true+ or +false+.
    #
    # Lota::Graphics::TextureFormats, from Lota::Graphics.texture_formats,
    # replaces it.
    #
    # === Example
    #
    #   Lota::Graphics.canvas_formats.rgba16f # => true
    class CanvasFormats < ::Data.define(:normal, :hdr, :r8, :r8i, :r8ui, :r16, :r16f, :r16i, :r16ui, :r32f, :r32i,
      :r32ui, :rg8, :rg8i, :rg8ui, :la8, :rg16, :rg16f, :rg16i, :rg16ui,
      :rg32f, :rg32i, :rg32ui, :rgba8, :srgba8, :bgra8, :bgra8srgb, :rgba8i,
      :rgba8ui, :rgba16, :rgba16f, :rgba16i, :rgba16ui, :rgba32f, :rgba32i,
      :rgba32ui, :rgba4, :rgb5a1, :rgb565, :rgb10a2, :rgb10a2ui, :rg11b10f,
      :stencil8, :depth16, :depth24, :depth32f, :depth24stencil8,
      :depth32fstencil8)
      include Record
    end
  end
end
