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
  # The types whose tests Lövetest names by the type (love.test.graphics.Quad).
  TYPES = %w[Quad SpriteBatch].freeze

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

  # Translated to Ruby from love.test.graphics.arc
  # (vendor/love/testing/tests/graphics.lua:1329-1378): arc keeps its name
  # (rule 13), with its draw and arc modes as symbols (rule 9), and the
  # rules test_circle names. Lua's math.pi is Ruby's Math::PI.
  # GITHUB_RUNNER and test:isOS are Lovetest::GITHUB_RUNNER and
  # Lovetest.os?.
  def test_arc
    # draw some arcs using pi format
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.arc(:line, :pie, 16, 16, 16, 0 * (Math::PI / 180), 360 * (Math::PI / 180), 10)
    Lota::Graphics.arc(:fill, :pie, 16, 16, 16, 270 * (Math::PI / 180), 45 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.arc(:line, :pie, 16, 16, 16, 0 * (Math::PI / 180), 90 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.arc(:line, :pie, 16, 16, 16, 180 * (Math::PI / 180), 135 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata1 = Lota::Graphics.readback_texture(canvas)
    # draw some arcs with open format
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.arc(:line, :open, 16, 16, 16, 0 * (Math::PI / 180), 315 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.arc(:fill, :open, 16, 16, 16, 0 * (Math::PI / 180), 180 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.arc(:fill, :open, 16, 16, 16, 180 * (Math::PI / 180), 270 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata2 = Lota::Graphics.readback_texture(canvas)
    # draw some arcs with closed format
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.arc(:line, :closed, 16, 16, 16, 0 * (Math::PI / 180), 315 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.arc(:fill, :closed, 16, 16, 16, 0 * (Math::PI / 180), 180 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.arc(:line, :closed, 16, 16, 16, 180 * (Math::PI / 180), 90 * (Math::PI / 180), 10)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata3 = Lota::Graphics.readback_texture(canvas)
    if Lovetest::GITHUB_RUNNER && Lovetest.os?("OS X")
      # on macosx runners, the arcs are not drawn as accurately at low res
      # there's a couple pixels different in the curve of the arc but as we
      # are at such a low resolution I think that can be expected
      # on real hardware the test passes fine though
      assert_equal(true, true, "skip test")
    else
      compare_img(imgdata1)
      compare_img(imgdata2)
      compare_img(imgdata3)
    end
  end

  # Translated to Ruby from love.test.graphics.ellipse
  # (vendor/love/testing/tests/graphics.lua:1490-1504), by the rules
  # test_circle names.
  def test_ellipse
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.ellipse(:fill, 16, 16, 16, 8)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.ellipse(:fill, 24, 24, 10, 24)
    Lota::Graphics.color = 1, 0, 1, 1
    Lota::Graphics.ellipse(:fill, 16, 0, 8, 16)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.line
  # (vendor/love/testing/tests/graphics.lua:1524-1536), by the rules
  # test_circle names. Lua's table of numbers is a Ruby Array.
  def test_line
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.line(1, 1, 16, 1, 16, 16, 1, 16, 1, 1)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.line([0, 0, 8, 8, 16, 0, 8, 8, 16, 16, 8, 8, 0, 16])
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.newFont
  # (vendor/love/testing/tests/graphics.lua:1711-1714): newFont becomes
  # Font.new (rule 2), and its hinting a symbol (rule 9). Lövetest reads
  # resources/ from its own folder, which LÖVE's filesystem searches;
  # Lota's runners have resources/ beside their conf.rb, a link to
  # Lövetest's.
  def test_new_font
    assert_object(Lota::Graphics::Font.new("resources/font.ttf"))
    assert_object(Lota::Graphics::Font.new("resources/font.ttf", 8, :normal, 1))
  end

  # Translated to Ruby from love.test.graphics.newTexture
  # (vendor/love/testing/tests/graphics.lua:1794-1797): newImageData and
  # newTexture become ImageData.new and Texture.new (rule 2), reading
  # resources/ as test_new_font does.
  def test_new_texture
    imgdata = Lota::Image::ImageData.new("resources/love.png")
    assert_object(Lota::Graphics::Texture.new(imgdata))
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

  # Translated to Ruby from love.test.graphics.Quad
  # (vendor/love/testing/tests/graphics.lua:793-818): newImage and newQuad
  # become Image.new and Quad.new (rule 2), getLayer and
  # getTextureDimensions readers (rules 3 and 4), setLayer and
  # setViewport writers (rules 5 and 6), and draw takes the quad after the
  # texture, as in LÖVE. Lua's two results are an Array (rule 4).
  def test_quad
    # create quad obj
    texture = Lota::Graphics::Image.new("resources/love.png")
    quad = Lota::Graphics::Quad.new(0, 0, 32, 32, texture)
    assert_object(quad)

    # check properties
    assert_equal(1, quad.layer, "check default layer")
    quad.layer = 2
    assert_equal(2, quad.layer, "check changed layer")
    sw, sh = quad.texture_dimensions
    assert_equal(64, sw, "check texture w")
    assert_equal(64, sh, "check texture h")

    # check drawing and viewport changes
    canvas = Lota::Graphics::Canvas.new(64, 64)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.draw(texture, quad, 0, 0)
    quad.viewport = 32, 32, 32, 32, 64, 64
    Lota::Graphics.draw(texture, quad, 32, 32)
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.SpriteBatch
  # (vendor/love/testing/tests/graphics.lua:1093-1214): newSpriteBatch
  # becomes SpriteBatch.new (rule 2), getCount, getBufferSize, getTexture,
  # getColor, and getWidth readers (rules 3 and 4), setTexture, setColor,
  # and setDrawRange writers (rules 5 and 6), and add, set, and clear keep
  # their names (rule 13), with the rules test_quad names. Lua's table of
  # sprites, counted from 1, is a Ruby Array, counted from 0, so
  # sprites[s][1] is sprites[s - 1][0]; the indices the batch gives and
  # takes count from 1 in both. Lua's s % 64 == 0 is Ruby's s % 64 == 0.
  #
  # Lövetest's last part draws from an array texture made by
  # newArrayImage, which Lota does not bind yet: rule 2 has not settled
  # what ArrayImage === asks (rake bindings:report). It and the fifth
  # image are left out until it does.
  def test_sprite_batch
    # create batch
    texture1 = Lota::Graphics::Image.new("resources/cubemap.png")
    texture2 = Lota::Graphics::Image.new("resources/love.png")
    quad1 = Lota::Graphics::Quad.new(32, 12, 1, 1, texture2) # lovepink
    quad2 = Lota::Graphics::Quad.new(32, 32, 1, 1, texture2) # white
    sbatch = Lota::Graphics::SpriteBatch.new(texture1, 5000)
    assert_object(sbatch)

    # check initial count
    assert_equal(0, sbatch.count, "check batch size")

    # check buffer size
    assert_equal(5000, sbatch.buffer_size, "check batch size")

    # check height/width/texture
    assert_equal(texture1.width, sbatch.texture.width, "check texture match w")
    assert_equal(texture1.height, sbatch.texture.height, "check texture match h")
    sbatch.texture = texture2
    assert_equal(texture2.width, sbatch.texture.width, "check texture change w")
    assert_equal(texture2.height, sbatch.texture.height, "check texture change h")

    # check colors
    r1, g1, b1, a1 = sbatch.color
    assert_equal(1, r1, "check initial color r")
    assert_equal(1, g1, "check initial color g")
    assert_equal(1, b1, "check initial color b")
    assert_equal(1, a1, "check initial color a")
    sbatch.color = 1, 0, 0, 1
    r2, g2, b2, a2 = sbatch.color
    assert_equal(1, r2, "check set color r")
    assert_equal(0, g2, "check set color g")
    assert_equal(0, b2, "check set color b")
    assert_equal(1, a2, "check set color a")

    # check adding sprites
    offset_x = 0
    offset_y = 0
    color = "white"
    sbatch.color = 1, 1, 1, 1
    sprites = []
    (1..4096).each do |s|
      spr = sbatch.add(quad1, offset_x, offset_y, 0, 1, 1)
      sprites << [spr, offset_x, offset_y]
      offset_x += 1
      next unless s % 64 == 0

      # alternate row colors
      if color == "white"
        color = "red"
        sbatch.color = 1, 0, 0, 1
      else
        color = "white"
        sbatch.color = 1, 1, 1, 1
      end
      offset_y += 1
      offset_x = 0
    end
    assert_equal(4096, sbatch.count)

    # test drawing and setting
    canvas = Lota::Graphics::Canvas.new(64, 64)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(sbatch, 0, 0)
    Lota::Graphics.canvas = nil
    imgdata1 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata1)

    # use set to change some sprites
    (1..2048).each do |s|
      sbatch.set(sprites[s - 1][0], quad2, sprites[s - 1][1], sprites[s - 1][2] + 1, 0, 1, 1)
    end
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(sbatch, 0, 0)
    Lota::Graphics.canvas = nil
    imgdata2 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata2)

    # set drawRange and redraw
    sbatch.draw_range = 1025, 2048
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(sbatch, 0, 0)
    Lota::Graphics.canvas = nil
    imgdata3 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata3)

    # clear and redraw
    sbatch.clear
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(sbatch, 0, 0)
    Lota::Graphics.canvas = nil
    imgdata4 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata4)
  end

  # Translated to Ruby from love.test.graphics.newQuad
  # (vendor/love/testing/tests/graphics.lua:1752-1755), by the rules
  # test_quad names.
  def test_new_quad
    imgdata = Lota::Graphics::Image.new("resources/love.png")
    assert_object(Lota::Graphics::Quad.new(0, 0, 16, 16, imgdata))
  end

  # Translated to Ruby from love.test.graphics.newSpriteBatch
  # (vendor/love/testing/tests/graphics.lua:1778-1781), by the rules
  # test_sprite_batch names.
  def test_new_sprite_batch
    imgdata = Lota::Graphics::Image.new("resources/love.png")
    assert_object(Lota::Graphics::SpriteBatch.new(imgdata, 1000))
  end

  # Translated to Ruby from love.test.graphics.origin
  # (vendor/love/testing/tests/graphics.lua:2574-2591): origin, translate,
  # scale, and shear keep their names (rule 13), with the rules
  # test_circle names.
  def test_origin
    # if we do some translations and scaling
    # using .origin() should reset it all and draw the pixel at 0,0
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.origin
    Lota::Graphics.translate(10, 10)
    Lota::Graphics.scale(1, 1)
    Lota::Graphics.shear(20, 20)
    Lota::Graphics.origin
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.pop
  # (vendor/love/testing/tests/graphics.lua:2595-2612), by the rules
  # test_origin names; push and pop, called apart as here, keep their
  # names (rule 11 adds a block form beside them).
  def test_pop
    # if we push at the start, and then run a pop
    # it should reset it all and draw the pixel at 0,0
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.push
    Lota::Graphics.translate(10, 10)
    Lota::Graphics.scale(1, 1)
    Lota::Graphics.shear(20, 20)
    Lota::Graphics.pop
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.push
  # (vendor/love/testing/tests/graphics.lua:2616-2635), by the rules
  # test_pop names.
  def test_push
    # if we push at the start, do some stuff, then another push
    # 1 pop should only go back 1 push and draw the pixel at 1, 1
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.push
    Lota::Graphics.scale(1, 1)
    Lota::Graphics.shear(20, 20)
    Lota::Graphics.push
    Lota::Graphics.translate(1, 1)
    Lota::Graphics.pop
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.pop
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.scale
  # (vendor/love/testing/tests/graphics.lua:2678-2691), by the rules
  # test_origin names.
  def test_scale
    # starting at 0,0, we scale by 4x and then draw
    # we can then check the drawn rectangle covers the whole canvas
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.scale(4, 4)
    Lota::Graphics.rectangle(:fill, 0, 0, 4, 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.translate
  # (vendor/love/testing/tests/graphics.lua:2739-2758), by the rules
  # test_origin names.
  def test_translate
    # starting at 0,0, we translate 4 times and draw a pixel at each point
    # we can then check the 4 points are now red
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.translate(5, 0)
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.translate(0, 5)
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.translate(-5, 0)
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.translate(0, -5)
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end
  # SPDX-SnippetEnd
end
