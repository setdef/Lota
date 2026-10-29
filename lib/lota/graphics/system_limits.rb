# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # The renderer's limits, which Lota::Graphics.system_limits returns,
    # translated from the table love.graphics.getSystemLimits returns
    # (src/modules/graphics/wrap_Graphics.cpp, w_getSystemLimits): a
    # frozen value with a field for each of LÖVE's limit names (ADR 001,
    # rule 10), each a Float, as LÖVE holds it.
    #
    # === Example
    #
    #   Lota::Graphics.system_limits.texturesize # => 16384.0
    class SystemLimits < ::Data.define(:pointsize, :texturesize, :volumetexturesize, :cubetexturesize, :texturelayers,
      :texelbuffersize, :shaderstoragebuffersize, :threadgroupsx,
      :threadgroupsy, :threadgroupsz, :multicanvas, :texturemsaa, :anisotropy)
      include Record
    end
  end
end
