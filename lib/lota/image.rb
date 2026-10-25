# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "image/image_data"

module Lota
  # Images as pixels in memory, translated from love.image.
  #
  # A texture lives on the graphics card, where drawing is fast and
  # reading is slow. Checking a pixel, saving a screenshot, or comparing
  # a frame with the one you expected all need the pixels back on the
  # CPU, one color at a time.
  #
  # This module holds ImageData, the engine's grid of decoded pixels.
  # Unlike Lota::Graphics, it runs on any thread, as love.image does in
  # LÖVE.
  module Image
  end
end
