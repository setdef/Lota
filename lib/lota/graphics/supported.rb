# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Which optional features the renderer has, which
    # Lota::Graphics.supported returns, translated from the table
    # love.graphics.getSupported returns
    # (src/modules/graphics/wrap_Graphics.cpp, w_getSupported): a frozen
    # value with a field for each of LÖVE's feature names (rule 10 of
    # doc/contributors/design/translation.md), +true+ or +false+.
    #
    # === Example
    #
    #   Lota::Graphics.supported.glsl3 # => true
    class Supported < ::Data.define(:multicanvasformats, :clampzero, :clampone, :lighten, :fullnpot,
      :pixelshaderhighp, :shaderderivatives, :glsl3, :glsl4, :instancing,
      :texelbuffer, :copytexturetobuffer, :indirectdraw, :vertexwrite, :pixelwrite)
      include Record
    end
  end
end
