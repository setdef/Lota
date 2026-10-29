# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The forms of Font's metrics that Lövetest's Font test does not reach
# (src/modules/graphics/wrap_Font.cpp): a glyph by its code point where a
# string also goes, every argument of hasGlyphs, colored text to wrap,
# fallbacks, and the filter's anisotropy. Lövetest's font.ttf lacks Ö and
# é, which LÖVE's default font, Noto Sans, has.
class FontTest < Minitest::Test
  include NativeHelper

  Font = Lota::Graphics::Font
  FONT = File.expand_path("../../vendor/love/testing/resources/font.ttf", __dir__)

  def setup
    EngineHelper.open_window
  end

  def small_font
    Font.new(Lota::Filesystem::FileData.new(File.binread(FONT), "font.ttf"), 8)
  end

  def noto
    Font.new(12)
  end

  # w_Font_getWidth reads a number as a glyph's code point.
  def test_a_width_is_of_text_or_of_one_glyph
    font = small_font

    assert_equal font.width("A"), font.width(65)
    assert_equal font.width("A") * 2, font.width("AA")
    assert_raises(TypeError) { font.width(nil) }
  end

  # w_Font_hasGlyphs answers for every argument, and needs one.
  def test_glyphs_asks_of_every_argument
    font = small_font

    assert font.glyphs?("AB", 67)
    refute font.glyphs?("A", "Ö")
    refute font.glyphs?(0xE9)
    assert_raises(ArgumentError) { font.glyphs? }
    assert_raises(TypeError) { font.glyphs?(:a) }
  end

  # w_Font_setFallbacks: a fallback's glyphs stand in for those the font
  # lacks, and none clears them.
  def test_fallbacks_supply_the_glyphs_a_font_lacks
    font = small_font
    font.fallbacks = noto

    assert font.glyphs?("é")
    font.fallbacks = []
    refute font.glyphs?("é")
    assert_raises(TypeError) { font.fallbacks = "Noto" }
  end

  def test_kerning_is_between_characters_or_glyphs
    font = noto

    assert_equal font.kerning("A", "V"), font.kerning(65, 86)
    assert_kind_of Float, font.kerning("A", "V")
    assert_raises(TypeError) { font.kerning("A", 86) }
  end

  # w_Font_getWrap reads colored text as print does and returns its
  # lines as text.
  def test_wrap_takes_colored_text_and_returns_its_lines
    width, lines = small_font.wrap(["ab", [1, 0, 0], " cd"], 1000)

    assert_equal ["ab cd"], lines
    assert_equal small_font.width("ab cd"), width
  end

  def test_the_filter_keeps_its_anisotropy
    font = small_font
    font.filter = :nearest, :linear, 4

    assert_equal [:nearest, :linear, 4], font.filter
    font.filter = :linear
    assert_equal [:linear, :linear, 1], font.filter
    assert_raises(ArgumentError) { font.filter = :blurry }
  end

  # Rule 14: Font's C++ holds its ascent and descent as ints, the rest as
  # floats.
  def test_metrics_are_numbers_of_the_types_the_engine_holds
    font = noto

    assert_kind_of Integer, font.ascent
    assert_kind_of Integer, font.descent
    [font.height, font.baseline, font.line_height, font.dpi_scale].each { |metric| assert_kind_of Float, metric }
  end
end
