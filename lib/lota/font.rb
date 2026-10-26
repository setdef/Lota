# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # LÖVE's font module, translated from love.font.
  #
  # Before a font can draw, its glyphs have to be rasterized: turned from
  # the outlines in a TrueType file, or the pictures in an image font, into
  # pixels. LÖVE's font module does that work, and its graphics module
  # draws with what it makes.
  #
  # Lota opens it, unless <tt>t.modules.font = false</tt>, before the
  # window, as boot.lua opens love.font, and Lota::Graphics::Font.new
  # rasterizes every font through it, as LÖVE's newFont does. Its own
  # functions, which make rasterizers and glyph data, Lota binds later.
  #
  # Use <tt>lota.font</tt> to ask whether the module is open, as a LÖVE
  # game asks <tt>if love.font then</tt>; draw text with
  # Lota::Graphics::Font.
  #
  # === Example
  #
  #   lota.font # => Lota::Font, or nil when the settings turn it off
  module Font
  end
end
