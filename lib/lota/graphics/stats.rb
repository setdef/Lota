# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # The renderer's counts, which Lota::Graphics.stats returns, translated
    # from the table love.graphics.getStats returns
    # (src/modules/graphics/wrap_Graphics.cpp, w_getStats): a frozen value
    # with LÖVE's field names (ADR 001, rule 10), each an Integer.
    #
    # [drawcalls] Draw calls since the last present.
    # [drawcallsbatched] Draw calls LÖVE saved by drawing several things
    #   at once.
    # [canvasswitches] Times the canvas changed.
    # [shaderswitches] Times the shader changed.
    # [textures] Textures that exist now, canvases among them.
    # [fonts] Fonts that exist now.
    # [buffers] Buffers that exist now.
    # [texturememory] Bytes of video memory the textures take.
    # [buffermemory] Bytes of video memory the buffers take.
    #
    # === Example
    #
    #   Lota::Graphics.stats.drawcalls # => 12
    class Stats < ::Data.define(:drawcalls, :drawcallsbatched, :canvasswitches, :shaderswitches, :textures, :fonts,
      :buffers, :texturememory, :buffermemory)
      include Record
    end
  end
end
