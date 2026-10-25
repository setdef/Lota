# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lovetest_helper"

# Lövetest's love.graphics tests (vendor/love/testing/tests/graphics.lua),
# translated to Ruby by ADR 001's rules.
class GraphicsTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.graphics.clear
  # (vendor/love/testing/tests/graphics.lua:1404-1413): newCanvas becomes
  # Canvas.new (rule 2), setCanvas a writer (rule 5), and readbackTexture
  # readback_texture (rule 13).
  def test_clear
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.clear(1, 1, 0, 1)
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end
  # SPDX-SnippetEnd
end
