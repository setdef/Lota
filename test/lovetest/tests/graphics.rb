# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.graphics tests (vendor/love/testing/tests/graphics.lua),
# translated to Ruby by ADR 001's rules. Two runners load them:
# test/lovetest/graphics_test.rb, in the test suite's own process, and
# test/lovetest/game, a game folder that runs them from its update callback
# under lota run, as Lövetest runs them from love.update.
class GraphicsTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.graphics.circle
  # (vendor/love/testing/tests/graphics.lua:1383-1400): newCanvas becomes
  # Canvas.new (rule 2), setCanvas and setColor writers (rules 5 and 6),
  # the draw modes symbols (rule 9), and readbackTexture readback_texture
  # (rule 13).
  def test_circle
    # draw some circles
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.circle(:fill, 16, 16, 16)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.circle(:line, 16, 16, 16)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.circle(:fill, 16, 16, 8)
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.circle(:fill, 16, 16, 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

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

  # Translated to Ruby from love.test.graphics.rectangle
  # (vendor/love/testing/tests/graphics.lua:1611-1637), by the rules
  # test_circle names.
  def test_rectangle
    # setup, draw a 16x16 red rectangle with a blue central square
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 16, 16)
    Lota::Graphics.color = 0, 0, 1, 1
    Lota::Graphics.rectangle(:fill, 6, 6, 4, 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata1 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata1)
    # clear canvas to do some line testing
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:line, 1, 1, 15, 15) # red border
    Lota::Graphics.color = 0, 0, 1, 1
    Lota::Graphics.rectangle(:line, 1, 1, 2, 15) # 3x16 left aligned blue outline
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.rectangle(:line, 11, 1, 5, 15) # 6x16 right aligned green outline
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata2 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata2)
  end

  # Translated to Ruby from love.test.graphics.getColor
  # (vendor/love/testing/tests/graphics.lua:1898-1913): getColor becomes
  # color (rule 3), whose four values come back as an Array (rule 4), and
  # setColor a writer of several values (rule 6).
  def test_get_color
    # by default should be white
    r, g, b, a = Lota::Graphics.color
    assert_equal(1, r, "check default color r")
    assert_equal(1, g, "check default color g")
    assert_equal(1, b, "check default color b")
    assert_equal(1, a, "check default color a")
    # check set color is returned correctly
    Lota::Graphics.color = 0, 0, 0, 0
    r, g, b, a = Lota::Graphics.color
    assert_equal(0, r, "check changed color r")
    assert_equal(0, g, "check changed color g")
    assert_equal(0, b, "check changed color b")
    assert_equal(0, a, "check changed color a")
    Lota::Graphics.color = 1, 1, 1, 1 # reset
  end

  # Translated to Ruby from love.test.graphics.getLineStyle
  # (vendor/love/testing/tests/graphics.lua:1983-1990): getLineStyle
  # becomes line_style (rule 3) and setLineStyle a writer (rule 5), with
  # the styles as symbols (rule 9).
  def test_get_line_style
    # we know this should be as testsuite sets it!
    assert_equal(:rough, Lota::Graphics.line_style)
    # check set value returned correctly
    Lota::Graphics.line_style = :smooth
    assert_equal(:smooth, Lota::Graphics.line_style)
    Lota::Graphics.line_style = :rough # reset
  end

  # Translated to Ruby from love.test.graphics.getLineWidth
  # (vendor/love/testing/tests/graphics.lua:1994-2001): getLineWidth
  # becomes line_width (rule 3) and setLineWidth a writer (rule 5).
  def test_get_line_width
    # we know this should be as testsuite sets it!
    assert_equal(1, Lota::Graphics.line_width)
    # check set value returned correctly
    Lota::Graphics.line_width = 10
    assert_equal(10, Lota::Graphics.line_width)
    Lota::Graphics.line_width = 1 # reset
  end

  # Translated to Ruby from love.test.graphics.setColor
  # (vendor/love/testing/tests/graphics.lua:2220-2243), by the rules
  # test_circle and test_get_color name.
  def test_set_color
    # set colors, draw rect, check color
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    r, g, b, a = Lota::Graphics.color
    assert_equal(1, r, "check r set")
    assert_equal(0, g, "check g set")
    assert_equal(0, b, "check b set")
    assert_equal(1, a, "check a set")

    Lota::Graphics.rectangle(:fill, 0, 0, 16, 1)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 1, 16, 1)
    Lota::Graphics.color = 0, 1, 0, 0.5
    Lota::Graphics.rectangle(:fill, 0, 2, 16, 1)
    Lota::Graphics.color = 0, 0, 1, 1
    Lota::Graphics.rectangle(:fill, 0, 3, 16, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.getDefaultFilter
  # (vendor/love/testing/tests/graphics.lua:1936-1942): getDefaultFilter
  # becomes default_filter (rule 3), whose three values come back as an
  # Array (rule 4), with the filters as symbols (rule 9).
  def test_get_default_filter
    # we set this already for testsuite so we know what it should be
    min, mag, anisotropy = Lota::Graphics.default_filter
    assert_equal(:nearest, min, "check default filter min")
    assert_equal(:nearest, mag, "check default filter mag")
    assert_equal(1, anisotropy, "check default filter mag")
  end

  # Translated to Ruby from love.test.graphics.print
  # (vendor/love/testing/tests/graphics.lua:1573-1588): setFont becomes a
  # writer (rule 5), print keeps its name (rule 13), and Lövetest's global
  # Font is Lovetest.font. Lua's math.pi is Ruby's Math::PI.
  def test_print
    Lota::Graphics.font = Lovetest.font
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.print("love", 0, 3, 0, 1, 1, 0, 0)
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.print("ooo", 0, 3, 0, 2, 2, 0, 0)
    Lota::Graphics.color = 0, 0, 1, 1
    Lota::Graphics.print("hello", 0, 3, 90 * (Math::PI / 180), 1, 1, 0, 8)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.printf
  # (vendor/love/testing/tests/graphics.lua:1592-1607), by the rules
  # test_print names, with the alignments as symbols (rule 9).
  def test_printf
    Lota::Graphics.font = Lovetest.font
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.printf("love", 0, 0, 8, :left)
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.printf("love", 0, 5, 16, :right)
    Lota::Graphics.color = 0, 0, 1, 1
    Lota::Graphics.printf("love", 0, 7, 32, :center)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setDefaultFilter
  # (vendor/love/testing/tests/graphics.lua:2270-2278), by the rules
  # test_get_default_filter names, with setDefaultFilter a writer of
  # several values (rule 6).
  def test_set_default_filter
    # check setting filter val works
    Lota::Graphics.default_filter = :linear, :linear, 1
    min, mag, anisotropy = Lota::Graphics.default_filter
    assert_equal(:linear, min, "check default filter min")
    assert_equal(:linear, mag, "check default filter mag")
    assert_equal(1, anisotropy, "check default filter mag")
    Lota::Graphics.default_filter = :nearest, :nearest, 1 # reset
  end

  # Translated to Ruby from love.test.graphics.setFont
  # (vendor/love/testing/tests/graphics.lua:2299-2311), by the rules
  # test_print names.
  def test_set_font
    # set font doesnt return anything so draw with the test font
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.font = Lovetest.font
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.print("love", 0, 3)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end
  # SPDX-SnippetEnd
end
