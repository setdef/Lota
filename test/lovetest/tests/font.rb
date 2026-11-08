# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.font tests (vendor/love/testing/tests/font.lua),
# translated to Ruby by ADR 001's rules. They run in the test suite's own
# process (test/lovetest/font_test.rb) and under lota run
# (test/lovetest/game). love.font's factories become constructors (rule
# 2): newRasterizer and newGlyphData the classes' own, Rasterizer.new and
# GlyphData.new, and newTrueTypeRasterizer, newBMFontRasterizer, and
# newImageRasterizer modules of those names, since LÖVE has no such
# classes, whose new returns a Rasterizer. The class is FontModuleTest,
# as Lota's is LotaModuleTest, since FontTest is test/native/font_test.rb's.
class FontModuleTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type (love.test.font.GlyphData).
  TYPES = %w[GlyphData Rasterizer].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib

  # Translated to Ruby from love.test.font.GlyphData
  # (vendor/love/testing/tests/font.lua:12-55): the getters drop get (rule
  # 3), getFormat's format is a Symbol (rule 9), and getBoundingBox,
  # getDimensions, and getBearing return Arrays (rule 4). The checks of
  # getGlyph and getGlyphString stay commented out, as Lövetest leaves
  # them.
  def test_glyph_data
    # create obj
    rasterizer = Lota::Font::Rasterizer.new("resources/font.ttf")
    gdata = Lota::Font::GlyphData.new(rasterizer, 97) # 'a'
    assert_object(gdata)

    # check properties match expected
    assert_not_nil(gdata.string)
    assert_equal(128, gdata.size, "check data size")
    assert_equal(9, gdata.advance, "check advance")
    assert_equal(:la8, gdata.format, "check format")

    # @TODO
    #   currently these will return 0 and '' respectively as not implemented
    #   https://github.com/love2d/love/blob/12.0-development/src/modules/font/freetype/TrueTypeRasterizer.cpp#L140-L141
    #   "basically I haven't decided what to do here yet, because of the more
    #   advanced text shaping that happens in love 12 having a unicode codepoint
    #   associated with a glyph probably doesn't make sense in the first place"
    # assert_equal(97, gdata.glyph, "check glyph number") - returns 0
    # assert_equal("a", gdata.glyph_string, "check glyph string") - returns ''

    # check height + width
    assert_equal(8, gdata.height, "check height")
    assert_equal(8, gdata.width, "check width")

    # check boundary / dimensions
    x, y, w, h = gdata.bounding_box
    dw, dh = gdata.dimensions
    assert_equal(0, x, "check bbox x")
    assert_equal(-3, y, "check bbox y")
    assert_equal(8, w, "check bbox w")
    assert_equal(14, h, "check bbox h")
    assert_equal(8, dw, "check dim width")
    assert_equal(8, dh, "check dim height")

    # check bearing
    bw, bh = gdata.bearing
    assert_equal(0, bw, "check bearing w")
    assert_equal(11, bh, "check bearing h")
  end

  # Translated to Ruby from love.test.font.Rasterizer
  # (vendor/love/testing/tests/font.lua:59-83): the getters drop get (rule
  # 3), and hasGlyphs becomes glyphs? (rule 8).
  def test_rasterizer
    # create obj
    rasterizer = Lota::Font::Rasterizer.new("resources/font.ttf")
    assert_object(rasterizer)

    # check advance
    assert_equal(9, rasterizer.advance, "check advance")

    # check ascent/descent
    assert_equal(9, rasterizer.ascent, "check ascent")
    assert_equal(-3, rasterizer.descent, "check descent")

    # check glyphcount
    assert_equal(77, rasterizer.glyph_count, "check glyph count")

    # check specific glyphs
    assert_object(rasterizer.glyph_data("L"))
    assert_true(rasterizer.glyphs?("L", "O", "V", "E"), "check LOVE")

    # check height + lineheight
    assert_equal(12, rasterizer.height, "check height")
    assert_equal(15, rasterizer.line_height, "check line height")
  end

  # Translated to Ruby from love.test.font.newBMFontRasterizer
  # (vendor/love/testing/tests/font.lua:94-97).
  def test_new_bm_font_rasterizer
    rasterizer = Lota::Font::BMFontRasterizer.new("resources/love.png")
    assert_object(rasterizer)
  end

  # Translated to Ruby from love.test.font.newGlyphData
  # (vendor/love/testing/tests/font.lua:102-107): newImageData becomes
  # ImageData.new (rule 2).
  # @NOTE this is just basic nil checking, objs have their own test method
  def test_new_glyph_data
    img = Lota::Image::ImageData.new("resources/love.png")
    rasterizer = Lota::Font::ImageRasterizer.new(img, "ABC", 0, 1)
    glyphdata = Lota::Font::GlyphData.new(rasterizer, 65)
    assert_object(glyphdata)
  end

  # Translated to Ruby from love.test.font.newImageRasterizer
  # (vendor/love/testing/tests/font.lua:112-116).
  # @NOTE this is just basic nil checking, objs have their own test method
  def test_new_image_rasterizer
    img = Lota::Image::ImageData.new("resources/love.png")
    rasterizer = Lota::Font::ImageRasterizer.new(img, "ABC", 0, 1)
    assert_object(rasterizer)
  end

  # Translated to Ruby from love.test.font.newRasterizer
  # (vendor/love/testing/tests/font.lua:121-123).
  # @NOTE this is just basic nil checking, objs have their own test method
  def test_new_rasterizer
    assert_object(Lota::Font::Rasterizer.new("resources/font.ttf"))
  end

  # Translated to Ruby from love.test.font.newTrueTypeRasterizer
  # (vendor/love/testing/tests/font.lua:128-131): the hinting mode is a
  # Symbol (rule 9).
  # @NOTE this is just basic nil checking, objs have their own test method
  def test_new_true_type_rasterizer
    assert_object(Lota::Font::TrueTypeRasterizer.new(12, :normal, 1))
    assert_object(Lota::Font::TrueTypeRasterizer.new("resources/font.ttf", 8, :normal, 1))
  end

  # SPDX-SnippetEnd
end
