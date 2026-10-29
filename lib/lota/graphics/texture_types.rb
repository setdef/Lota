# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Which types of texture the renderer has, which
    # Lota::Graphics.texture_types returns, translated from the table
    # love.graphics.getTextureTypes returns
    # (src/modules/graphics/wrap_Graphics.cpp, w_getTextureTypes): a frozen
    # value with a field for each of LÖVE's texture type names (ADR 001,
    # rule 10), +true+ or +false+.
    #
    # No Ruby method can be called +2d+ without +public_send+, so read it
    # with +[]+, as Lua reads it with brackets.
    #
    # === Example
    #
    #   types = Lota::Graphics.texture_types
    #   types["2d"] # => true
    #   types.cube  # => true
    class TextureTypes < ::Data.define(:"2d", :volume, :array, :cube)
      include Record
    end
  end
end
