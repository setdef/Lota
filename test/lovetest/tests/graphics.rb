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
  TYPES = %w[Font Quad SpriteBatch].freeze

  # Lövetest runs its modules in a fixed order, graphics before window
  # (vendor/love/testing/main.lua:81-85), so its graphics tests draw in
  # the window conf.lua opens, with depth and stencil buffers. Minitest
  # runs test classes in random order, and the window tests'
  # love.window.updateMode turns both buffers off (window.lua:398), so a
  # graphics test that runs after them, such as setDepthMode on the
  # window's depth buffer, gets the window back as Lövetest has it.
  #
  # Lövetest also runs a module's tests in the order of their names
  # (classes/TestModule.lua:68-71), so getColor, which checks the default
  # color, runs before resetProjection, which leaves the color blue, as
  # its Lua does; each test here starts with the default color.
  def setup
    super
    Lota::Graphics.color = 1, 1, 1, 1 if Lota.graphics
    return unless Lota.window

    _width, _height, flags = Lota::Window.mode
    Lota::Window.update_mode(depth: true, stencil: true) unless flags.depth && flags.stencil
  end

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

  # Translated to Ruby from love.test.graphics.Font
  # (vendor/love/testing/tests/graphics.lua:264-308), all but its check of
  # font substitution (lines 310-321), whose newImageFont waits for
  # slice 4's image fonts: newFont becomes Font.new (rule 2), the getters
  # drop get (rule 3), getDPIScale is dpi_scale (rule 13), getFilter's
  # results an Array whose first Lua keeps (rule 4), setFilter and
  # setLineHeight writers (rules 5 and 6), hasGlyphs glyphs? (rule 8), and
  # getWrap's two results an Array, its lines an Array counted from 0;
  # setFont, setCanvas, and newCanvas as test_set_font has them.
  def test_font
    # create obj
    font = Lota::Graphics::Font.new("resources/font.ttf", 8)
    assert_object(font)

    # check ascent/descent
    assert_equal(6, font.ascent, "check ascent")
    assert_equal(-2, font.descent, "check descent")

    # check baseline
    assert_equal(6, font.baseline, "check baseline")

    # check dpi
    assert_equal(1, font.dpi_scale, "check dpi")

    # check filter
    assert_equal(:nearest, font.filter.first, "check filter def")
    font.filter = :linear, :linear
    assert_equal(:linear, font.filter.first, "check filter change")
    font.filter = :nearest, :nearest

    # check height + lineheight
    assert_equal(8, font.height, "check height")
    assert_equal(1, font.line_height, "check line height")
    font.line_height = 2
    assert_equal(2, font.line_height, "check changed line height")
    font.line_height = 1 # reset for drawing + wrap later

    # check width + kerning
    assert_equal(0, font.kerning("a", "b"), "check kerning")
    assert_equal(24, font.width("test"), "check data size")

    # check specific glyphs
    assert_true(font.glyphs?("test"), "check data size")

    # check font wrapping
    width, wrappedtext = font.wrap("LÖVE is an *awesome* framework you can use to make 2D games in Lua.", 50)
    assert_equal(48, width, "check actual wrap width")
    assert_equal(8, wrappedtext.size, "check wrapped lines")
    assert_equal("LÖVE is an ", wrappedtext[0], "check wrapped line")

    # check drawing font
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.font = font
    Lota::Graphics.print("Aa", 0, 5)
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
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

  # Translated to Ruby from love.test.graphics.discard
  # (vendor/love/testing/tests/graphics.lua:1417-1420): test:skipTest
  # becomes Minitest's skip, as Lövetest skips it.
  def test_discard
    # from the docs: "on some desktops this may do nothing"
    skip("cant test this worked")
  end

  # Translated to Ruby from love.test.graphics.points
  # (vendor/love/testing/tests/graphics.lua:1540-1553): points keeps its
  # name (rule 13), push takes its stack type as a symbol (rule 9), and
  # Lua's table of numbers is a Ruby Array, by the rules test_circle
  # names.
  def test_points
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.translate(0.5, 0.5) # draw points at the center of pixels
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.points(0, 0, 15, 0, 15, 15, 0, 15, 0, 0)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.points([1, 1, 7, 7, 14, 1, 7, 8, 14, 14, 8, 8, 1, 14, 8, 7])
    Lota::Graphics.pop
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.polygon
  # (vendor/love/testing/tests/graphics.lua:1557-1569): polygon keeps its
  # name (rule 13), with its draw mode a symbol (rule 9), by the rules
  # test_points names.
  def test_polygon
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.polygon(:fill, 1, 1, 4, 5, 8, 10, 16, 2, 7, 3, 5, 16, 16, 16, 1, 8)
    Lota::Graphics.color = 1, 1, 0, 1
    Lota::Graphics.polygon(:line, [2, 2, 4, 5, 3, 7, 8, 15, 12, 4, 5, 10])
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.getBackgroundColor
  # (vendor/love/testing/tests/graphics.lua:1852-1867), by the rules
  # test_get_color names.
  def test_get_background_color
    # check default bg is black
    r, g, b, a = Lota::Graphics.background_color
    assert_equal(0, r, "check default background r")
    assert_equal(0, g, "check default background g")
    assert_equal(0, b, "check default background b")
    assert_equal(1, a, "check default background a")
    # check set value returns correctly
    Lota::Graphics.background_color = 1, 1, 1, 0
    r, g, b, a = Lota::Graphics.background_color
    assert_equal(1, r, "check updated background r")
    assert_equal(1, g, "check updated background g")
    assert_equal(1, b, "check updated background b")
    assert_equal(0, a, "check updated background a")
    Lota::Graphics.background_color = 0, 0, 0, 1 # reset
  end

  # Translated to Ruby from love.test.graphics.getBlendMode
  # (vendor/love/testing/tests/graphics.lua:1871-1882): getBlendMode
  # becomes blend_mode (rule 3), whose two values come back as an Array
  # (rule 4), and setBlendMode a writer of several values (rule 6), with
  # the modes as symbols (rule 9).
  def test_get_blend_mode
    # check default blend mode
    mode, alphamode = Lota::Graphics.blend_mode
    assert_equal(:alpha, mode, "check default blend mode")
    assert_equal(:alphamultiply, alphamode, "check default alpha blend")
    # check set mode returns correctly
    Lota::Graphics.blend_mode = :add, :premultiplied
    mode, alphamode = Lota::Graphics.blend_mode
    assert_equal(:add, mode, "check changed blend mode")
    assert_equal(:premultiplied, alphamode, "check changed alpha blend")
    Lota::Graphics.blend_mode = :alpha, :alphamultiply # reset
  end

  # Translated to Ruby from love.test.graphics.getCanvas
  # (vendor/love/testing/tests/graphics.lua:1886-1894): getCanvas becomes
  # canvas (rule 3), and assertEquals(nil, ...) assert_nil, by the rules
  # test_circle names.
  def test_get_canvas
    # by default should be nil if drawing to real screen
    assert_nil(Lota::Graphics.canvas, "check no canvas set")
    # should return not nil when we target a canvas
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    assert_object(Lota::Graphics.canvas)
    Lota::Graphics.canvas = nil
  end

  # Translated to Ruby from love.test.graphics.getColorMask
  # (vendor/love/testing/tests/graphics.lua:1917-1932): getColorMask
  # becomes color_mask (rule 3), whose four values come back as an Array
  # (rule 4), and setColorMask a writer of several values (rule 6).
  def test_get_color_mask
    # by default should all be active
    r, g, b, a = Lota::Graphics.color_mask
    assert_true(r, "check default color mask r")
    assert_true(g, "check default color mask g")
    assert_true(b, "check default color mask b")
    assert_true(a, "check default color mask a")
    # check set color mask is returned correctly
    Lota::Graphics.color_mask = false, false, true, false
    r, g, b, a = Lota::Graphics.color_mask
    assert_false(r, "check changed color mask r")
    assert_false(g, "check changed color mask g")
    assert_true(b, "check changed color mask b")
    assert_false(a, "check changed color mask a")
    Lota::Graphics.color_mask = true, true, true, true # reset
  end

  # Translated to Ruby from love.test.graphics.getDepthMode
  # (vendor/love/testing/tests/graphics.lua:1946-1951): getDepthMode
  # becomes depth_mode (rule 3), whose two values come back as an Array
  # (rule 4), with the compare mode a symbol (rule 9).
  def test_get_depth_mode
    # by default should be always/write
    comparemode, write = Lota::Graphics.depth_mode
    assert_equal(:always, comparemode, "check default compare depth")
    assert_false(write, "check default depth buffer write")
  end

  # Translated to Ruby from love.test.graphics.getFont
  # (vendor/love/testing/tests/graphics.lua:1955-1957): getFont becomes
  # font (rule 3).
  def test_get_font
    assert_object(Lota::Graphics.font)
  end

  # Translated to Ruby from love.test.graphics.getFrontFaceWinding
  # (vendor/love/testing/tests/graphics.lua:1961-1968):
  # getFrontFaceWinding becomes front_face_winding (rule 3) and
  # setFrontFaceWinding a writer (rule 5), with the windings as symbols
  # (rule 9).
  def test_get_front_face_winding
    # check default winding
    assert_equal(:ccw, Lota::Graphics.front_face_winding)
    # check setting value changes it correctly
    Lota::Graphics.front_face_winding = :cw
    assert_equal(:cw, Lota::Graphics.front_face_winding)
    Lota::Graphics.front_face_winding = :ccw # reset
  end

  # Translated to Ruby from love.test.graphics.getLineJoin
  # (vendor/love/testing/tests/graphics.lua:1972-1979): getLineJoin
  # becomes line_join (rule 3) and setLineJoin a writer (rule 5), with
  # the joins as symbols (rule 9).
  def test_get_line_join
    # check default line join
    assert_equal(:miter, Lota::Graphics.line_join)
    # check set value returned correctly
    Lota::Graphics.line_join = :none
    assert_equal(:none, Lota::Graphics.line_join)
    Lota::Graphics.line_join = :miter # reset
  end

  # Translated to Ruby from love.test.graphics.getMeshCullMode
  # (vendor/love/testing/tests/graphics.lua:2005-2012): getMeshCullMode
  # becomes mesh_cull_mode (rule 3) and setMeshCullMode a writer (rule
  # 5), with the modes as symbols (rule 9).
  def test_get_mesh_cull_mode
    # get default mesh culling
    assert_equal(:none, Lota::Graphics.mesh_cull_mode)
    # check set value returned correctly
    Lota::Graphics.mesh_cull_mode = :front
    assert_equal(:front, Lota::Graphics.mesh_cull_mode)
    Lota::Graphics.mesh_cull_mode = :back # reset
  end

  # Translated to Ruby from love.test.graphics.getPointSize
  # (vendor/love/testing/tests/graphics.lua:2016-2023): getPointSize
  # becomes point_size (rule 3) and setPointSize a writer (rule 5).
  def test_get_point_size
    # get default point size
    assert_equal(1, Lota::Graphics.point_size)
    # check set value returned correctly
    Lota::Graphics.point_size = 10
    assert_equal(10, Lota::Graphics.point_size)
    Lota::Graphics.point_size = 1 # reset
  end

  # Translated to Ruby from love.test.graphics.getScissor
  # (vendor/love/testing/tests/graphics.lua:2027-2042): getScissor
  # becomes scissor (rule 3), whose values come back as an Array (rule
  # 4), empty where LÖVE returns none, so each is nil as in Lua;
  # setScissor becomes a writer of several values (rule 6), and
  # setScissor() with no arguments scissor = nil, as setCanvas() is
  # canvas = nil. assertEquals(nil, ...) becomes assert_nil.
  def test_get_scissor
    # should be no scissor atm
    x, y, w, h = Lota::Graphics.scissor
    assert_nil(x, "check no scissor")
    assert_nil(y, "check no scissor")
    assert_nil(w, "check no scissor")
    assert_nil(h, "check no scissor")
    # check set value returned correctly
    Lota::Graphics.scissor = 0, 0, 16, 16
    x, y, w, h = Lota::Graphics.scissor
    assert_equal(0, x, "check scissor set")
    assert_equal(0, y, "check scissor set")
    assert_equal(16, w, "check scissor set")
    assert_equal(16, h, "check scissor set")
    Lota::Graphics.scissor = nil # reset
  end

  # Translated to Ruby from love.test.graphics.getStackDepth
  # (vendor/love/testing/tests/graphics.lua:2053-2068): getStackDepth
  # becomes stack_depth (rule 3).
  def test_get_stack_depth
    # by default should be none
    assert_equal(0, Lota::Graphics.stack_depth, "check no transforms in stack")
    # now add 3
    Lota::Graphics.push
    Lota::Graphics.push
    Lota::Graphics.push
    assert_equal(3, Lota::Graphics.stack_depth, "check 3 transforms in stack")
    # now remove 2
    Lota::Graphics.pop
    Lota::Graphics.pop
    assert_equal(1, Lota::Graphics.stack_depth, "check 1 transforms in stack")
    # now back to 0
    Lota::Graphics.pop
    assert_equal(0, Lota::Graphics.stack_depth, "check no transforms in stack")
  end

  # Translated to Ruby from love.test.graphics.getStencilState
  # (vendor/love/testing/tests/graphics.lua:2072-2085): getStencilState
  # becomes stencil_state (rule 3), whose five values come back as an
  # Array (rule 4), of which Lua keeps three, and setStencilState a
  # writer of several values (rule 6), with the action and compare mode
  # as symbols (rule 9); setStencilState() with no arguments is
  # stencil_state = nil, as test_get_scissor names.
  def test_get_stencil_state
    # check default vals
    action, comparemode, value = Lota::Graphics.stencil_state
    assert_equal(:keep, action, "check default stencil action")
    assert_equal(:always, comparemode, "check default stencil compare")
    assert_equal(0, value, "check default stencil value")
    # check set stencil values is returned
    Lota::Graphics.stencil_state = :replace, :less, 255
    action, comparemode, value = Lota::Graphics.stencil_state
    assert_equal(:replace, action, "check changed stencil action")
    assert_equal(:less, comparemode, "check changed stencil compare")
    assert_equal(255, value, "check changed stencil value")
    Lota::Graphics.stencil_state = nil # reset
  end

  # Translated to Ruby from love.test.graphics.intersectScissor
  # (vendor/love/testing/tests/graphics.lua:2089-2105): intersectScissor
  # becomes intersect_scissor (rule 13), by the rules test_get_scissor
  # and test_circle name.
  def test_intersect_scissor
    # make a scissor for the left half, then interset to make the top half
    # then we should be able to fill the canvas with red and only top 4x4 is filled
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.origin
    Lota::Graphics.scissor = 0, 0, 8, 16
    Lota::Graphics.intersect_scissor(0, 0, 4, 4)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 16, 16)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.scissor = nil
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.isActive
  # (vendor/love/testing/tests/graphics.lua:2109-2111): isActive becomes
  # active? (rule 8).
  def test_is_active
    assert_true(Lota::Graphics.active?, "check graphics is active") # i mean if you got this far
  end

  # Translated to Ruby from love.test.graphics.isGammaCorrect
  # (vendor/love/testing/tests/graphics.lua:2115-2118): isGammaCorrect
  # becomes gamma_correct? (rule 8).
  def test_is_gamma_correct
    # we know the config so know this is false
    assert_not_nil(Lota::Graphics.gamma_correct?)
  end

  # Translated to Ruby from love.test.graphics.isWireframe
  # (vendor/love/testing/tests/graphics.lua:2122-2134): getRendererInfo
  # becomes renderer_info (rule 3), whose four values come back as an
  # Array (rule 4), isWireframe wireframe? (rule 8), and setWireframe a
  # writer (rule 5). Lua's string.match with a pattern of plain
  # characters is String#match?.
  def test_is_wireframe
    name, _version, _vendor, _device = Lota::Graphics.renderer_info
    if name.match?("OpenGL ES")
      skip("Wireframe not supported on OpenGL ES")
    else
      # check off by default
      assert_false(Lota::Graphics.wireframe?, "check no wireframe by default")
      # check on when enabled
      Lota::Graphics.wireframe = true
      assert_true(Lota::Graphics.wireframe?, "check wireframe is set")
      Lota::Graphics.wireframe = false # reset
    end
  end

  # Translated to Ruby from love.test.graphics.reset
  # (vendor/love/testing/tests/graphics.lua:2138-2154), by the rules
  # test_get_color, test_get_canvas, and test_set_default_filter name.
  def test_reset
    # reset should reset current canvas and any colors/scissor
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.background_color = 0, 0, 1, 1
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.canvas = canvas
    Lota::Graphics.reset
    r, g, b, a = Lota::Graphics.background_color
    assert_equal(1, r + g + b + a, "check background reset")
    r, g, b, a = Lota::Graphics.color
    assert_equal(4, r + g + b + a, "check color reset")
    assert_nil(Lota::Graphics.canvas, "check canvas reset")
    Lota::Graphics.default_filter = :nearest, :nearest
    Lota::Graphics.line_style = :rough
    Lota::Graphics.point_size = 1
    Lota::Graphics.line_width = 1
  end

  # Translated to Ruby from love.test.graphics.setBackgroundColor
  # (vendor/love/testing/tests/graphics.lua:2158-2167), by the rules
  # test_get_color names.
  def test_set_background_color
    # check background is set
    Lota::Graphics.background_color = 1, 0, 0, 1
    r, g, b, a = Lota::Graphics.background_color
    assert_equal(1, r, "check set bg r")
    assert_equal(0, g, "check set bg g")
    assert_equal(0, b, "check set bg b")
    assert_equal(1, a, "check set bg a")
    Lota::Graphics.background_color = 0, 0, 0, 1
  end

  # Translated to Ruby from love.test.graphics.setBlendMode
  # (vendor/love/testing/tests/graphics.lua:2171-2195), by the rules
  # test_get_blend_mode and test_circle name. test.rgba_tolerance is the
  # test's @rgba_tolerance.
  def test_set_blend_mode
    # create fully white canvas, then draw diff. pixels through blendmodes
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0.5, 0.5, 0.5, 1)
    Lota::Graphics.blend_mode = :add, :alphamultiply
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.blend_mode = :subtract, :alphamultiply
    Lota::Graphics.color = 1, 1, 1, 0.5
    Lota::Graphics.rectangle(:fill, 15, 0, 1, 1)
    Lota::Graphics.blend_mode = :multiply, :premultiplied
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.rectangle(:fill, 15, 15, 1, 1)
    Lota::Graphics.blend_mode = :replace, :premultiplied
    Lota::Graphics.color = 0, 0, 1, 0.5
    Lota::Graphics.rectangle(:fill, 0, 15, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    Lota::Graphics.blend_mode = :alpha, :alphamultiply # reset
    # need 1rgba tolerance here on some machines
    @rgba_tolerance = 1
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setColorMask
  # (vendor/love/testing/tests/graphics.lua:2247-2266), by the rules
  # test_get_color_mask and test_circle name.
  def test_set_color_mask
    # set mask, draw stuff, check output pixels
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    # mask off blue
    Lota::Graphics.color_mask = true, true, false, true
    r, g, b, a = Lota::Graphics.color_mask
    assert_equal(r, true, "check r mask")
    assert_equal(g, true, "check g mask")
    assert_equal(b, false, "check b mask")
    assert_equal(a, true, "check a mask")
    # draw "black" which should then turn to yellow
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 16, 16)
    Lota::Graphics.color_mask = true, true, true, true
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setDepthMode
  # (vendor/love/testing/tests/graphics.lua:2282-2295): setDepthMode
  # becomes a writer of several values (rule 6) and getDepthMode
  # depth_mode, whose values come back as an Array (rule 4), of which
  # Lua's comparison keeps the first, as .first does, with the modes as
  # symbols (rule 9). Lua's numeric for over a table is each.
  def test_set_depth_mode
    # check documented modes are valid
    comparemode, write = Lota::Graphics.depth_mode
    modes = %i[equal notequal less lequal gequal greater never always]
    modes.each do |mode|
      Lota::Graphics.depth_mode = mode, true
      assert_equal(mode, Lota::Graphics.depth_mode.first, "check depth mode #{mode} set")
    end
    Lota::Graphics.depth_mode = comparemode, write
    # @TODO better graphics drawing specific test
  end

  # Translated to Ruby from love.test.graphics.setLineJoin
  # (vendor/love/testing/tests/graphics.lua:2345-2370), by the rules
  # test_get_line_join, test_line, and test_set_font name.
  def test_set_line_join
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.font = Lovetest.font
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    line = [0, 1, 8, 1, 8, 8]
    Lota::Graphics.line_style = :rough
    Lota::Graphics.line_width = 2
    Lota::Graphics.color = 1, 0, 0
    Lota::Graphics.line_join = :bevel
    Lota::Graphics.line(line)
    Lota::Graphics.translate(0, 4)
    Lota::Graphics.color = 1, 1, 0
    Lota::Graphics.line_join = :none
    Lota::Graphics.line(line)
    Lota::Graphics.translate(0, 4)
    Lota::Graphics.color = 0, 0, 1
    Lota::Graphics.line_join = :miter
    Lota::Graphics.line(line)
    Lota::Graphics.color = 1, 1, 1
    Lota::Graphics.line_width = 1
    Lota::Graphics.origin
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setLineStyle
  # (vendor/love/testing/tests/graphics.lua:2374-2396), by the rules
  # test_set_line_join and test_arc name.
  def test_set_line_style
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.font = Lovetest.font
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0
    line = [0, 1, 16, 1]
    Lota::Graphics.line_style = :rough
    Lota::Graphics.line(line)
    Lota::Graphics.translate(0, 4)
    Lota::Graphics.line_style = :smooth
    Lota::Graphics.line(line)
    Lota::Graphics.line_style = :rough
    Lota::Graphics.color = 1, 1, 1
    Lota::Graphics.origin
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    # linux runner needs a 1/255 tolerance for the blend between a rough line + bg
    @rgba_tolerance = 1 if Lovetest::GITHUB_RUNNER && Lovetest.os?("Linux")
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setLineWidth
  # (vendor/love/testing/tests/graphics.lua:2400-2423), by the rules
  # test_set_line_join names.
  def test_set_line_width
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.font = Lovetest.font
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    line = [0, 1, 8, 1, 8, 8]
    Lota::Graphics.color = 1, 0, 0
    Lota::Graphics.line_width = 2
    Lota::Graphics.line(line)
    Lota::Graphics.translate(0, 4)
    Lota::Graphics.color = 1, 1, 0
    Lota::Graphics.line_width = 3
    Lota::Graphics.line(line)
    Lota::Graphics.translate(0, 4)
    Lota::Graphics.color = 0, 0, 1
    Lota::Graphics.line_width = 4
    Lota::Graphics.line(line)
    Lota::Graphics.color = 1, 1, 1
    Lota::Graphics.line_width = 1
    Lota::Graphics.origin
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setMeshCullMode
  # (vendor/love/testing/tests/graphics.lua:2427-2437), by the rules
  # test_get_mesh_cull_mode and test_set_depth_mode name.
  def test_set_mesh_cull_mode
    # check documented modes are valid
    original = Lota::Graphics.mesh_cull_mode
    modes = %i[back front none]
    modes.each do |mode|
      Lota::Graphics.mesh_cull_mode = mode
      assert_equal(mode, Lota::Graphics.mesh_cull_mode, "check mesh cull mode #{mode} was set")
    end
    Lota::Graphics.mesh_cull_mode = original
    # @TODO better graphics drawing specific test
  end

  # Translated to Ruby from love.test.graphics.setScissor
  # (vendor/love/testing/tests/graphics.lua:2441-2456), by the rules
  # test_get_scissor and test_circle name.
  def test_set_scissor
    # make a scissor for the left half
    # then we should be able to fill the canvas with red and only left is filled
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.origin
    Lota::Graphics.scissor = 0, 0, 8, 16
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 16, 16)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.scissor = nil
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.setWireframe
  # (vendor/love/testing/tests/graphics.lua:2508-2531), by the rules
  # test_is_wireframe and test_circle name. test.pixel_tolerance is the
  # test's @pixel_tolerance.
  def test_set_wireframe
    name, _version, _vendor, _device = Lota::Graphics.renderer_info
    if name.match?("OpenGL ES")
      skip("Wireframe not supported on OpenGL ES")
    else
      # check wireframe outlines
      Lota::Graphics.wireframe = true
      canvas = Lota::Graphics::Canvas.new(16, 16)
      Lota::Graphics.canvas = canvas
      Lota::Graphics.clear(0, 0, 0, 1)
      Lota::Graphics.color = 1, 1, 0, 1
      Lota::Graphics.rectangle(:fill, 2, 2, 13, 13)
      Lota::Graphics.color = 1, 1, 1, 1
      Lota::Graphics.canvas = nil
      Lota::Graphics.wireframe = false
      imgdata = Lota::Graphics.readback_texture(canvas)
      # on macOS runners wireframes are drawn 1px off from the target
      @pixel_tolerance = 1 if Lovetest::GITHUB_RUNNER && Lovetest.os?("OS X")
      compare_img(imgdata)
    end
  end

  # Translated to Ruby from love.test.graphics.getRendererInfo
  # (vendor/love/testing/tests/graphics.lua:2888-2894), by the rules
  # test_is_wireframe names.
  def test_get_renderer_info
    name, version, vendor, device = Lota::Graphics.renderer_info
    assert_not_nil(name)
    assert_not_nil(version)
    assert_not_nil(vendor)
    assert_not_nil(device)
  end

  # Translated to Ruby from love.test.graphics.applyTransform
  # (vendor/love/testing/tests/graphics.lua:2541-2555): newTransform
  # becomes Transform.new (rule 2), and applyTransform apply_transform
  # (rule 13), with the rules test_origin names.
  def test_apply_transform
    # use transform object to translate the drawn rectangle
    transform = Lota::Math::Transform.new
    transform.translate(10, 0)
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.apply_transform(transform)
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.inverseTransformPoint
  # (vendor/love/testing/tests/graphics.lua:2559-2570):
  # inverseTransformPoint becomes inverse_transform_point (rule 13), whose
  # two results are an Array (rule 4).
  def test_inverse_transform_point
    # start with 0, 0
    sx, sy = Lota::Graphics.inverse_transform_point(0, 0)
    assert_equal(0, sx, "check starting x is 0")
    assert_equal(0, sy, "check starting y is 0")
    # check translation effects the point
    Lota::Graphics.translate(1, 5)
    sx, sy = Lota::Graphics.inverse_transform_point(1, 5)
    assert_equal(0, sx, "check transformed x is 0")
    assert_equal(0, sy, "check transformed y is 0")
    Lota::Graphics.origin
  end

  # Translated to Ruby from love.test.graphics.replaceTransform
  # (vendor/love/testing/tests/graphics.lua:2639-2656), by the rules
  # test_apply_transform names.
  def test_replace_transform
    # if use transform object to translate
    # set some normal transforms first which should get overwritten
    transform = Lota::Math::Transform.new
    transform.translate(10, 0)
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.scale(2, 2)
    Lota::Graphics.translate(10, 10)
    Lota::Graphics.replace_transform(transform)
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.rotate
  # (vendor/love/testing/tests/graphics.lua:2660-2674): rotate keeps its
  # name (rule 13), with the rules test_origin names. Lua's math.pi is
  # Ruby's Math::PI.
  def test_rotate
    # starting at 0,0, we rotate by 90deg and then draw
    # we can then check the drawn rectangle is rotated
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.translate(4, 0)
    Lota::Graphics.rotate(90 * (Math::PI / 180))
    Lota::Graphics.rectangle(:fill, 0, 0, 4, 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.shear
  # (vendor/love/testing/tests/graphics.lua:2695-2721), by the rules
  # test_origin names.
  def test_shear
    # starting at 0,0, we shear by 2x and then draw
    # we can then check the drawn rectangle has moved over
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.origin
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.shear(2, 0)
    Lota::Graphics.rectangle(:fill, 0, 0, 4, 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata1 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata1)
    # same again at 0,0, we shear by 2y and then draw
    # we can then check the drawn rectangle has moved down
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.origin
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.shear(0, 2)
    Lota::Graphics.rectangle(:fill, 0, 0, 4, 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    imgdata2 = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata2)
  end

  # Translated to Ruby from love.test.graphics.transformPoint
  # (vendor/love/testing/tests/graphics.lua:2725-2735), by the rules
  # test_inverse_transform_point names.
  def test_transform_point
    # start with 0, 0
    sx, sy = Lota::Graphics.transform_point(0, 0)
    assert_equal(0, sx, "check starting x is 0")
    assert_equal(0, sy, "check starting y is 0")
    # check translation effects the point
    Lota::Graphics.translate(1, 5)
    sx, sy = Lota::Graphics.transform_point(0, 0)
    assert_equal(1, sx, "check transformed x is 0")
    assert_equal(5, sy, "check transformed y is 10")
  end

  # Translated to Ruby from love.test.graphics.resetProjection
  # (vendor/love/testing/tests/graphics.lua:2762-2783): setProjection
  # becomes the writer projection=, taking its layout and elements as one
  # Array (rule 6), as ADR 001 makes Transform:setMatrix matrix=, with
  # the layout a symbol (rule 9), and resetProjection reset_projection
  # (rule 13).
  def test_reset_projection
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.origin
    # draw red pixel at (0, 4) using default projection
    Lota::Graphics.color = 1, 0, 0, 1
    Lota::Graphics.rectangle(:fill, 0, 4, 1, 1)
    Lota::Graphics.projection = :row, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0
    # draw a green pixel at that should not show on screen after projection.
    # if setProjection doesn't affect it, the green pixel will show and fail
    # the test.
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.rectangle(:fill, 2, 2, 1, 1)
    # draw a blue pixel at (8, 8) after resetting projection
    Lota::Graphics.reset_projection
    Lota::Graphics.color = 0, 0, 1, 1
    Lota::Graphics.rectangle(:fill, 8, 8, 1, 1)
    Lota::Graphics.canvas = nil
    imgdata = Lota::Graphics.readback_texture(canvas)
    compare_img(imgdata)
  end

  # Translated to Ruby from love.test.graphics.getDimensions
  # (vendor/love/testing/tests/graphics.lua:2801-2807): getDimensions
  # becomes dimensions (rule 3), and love.window.getMode
  # Lota::Window.mode, each of whose results are an Array (rule 4).
  def test_get_dimensions
    # check graphics dimensions match window dimensions
    gwidth, gheight = Lota::Graphics.dimensions
    wwidth, wheight, = Lota::Window.mode
    assert_equal(wwidth, gwidth, "check graphics dimension w matches window w")
    assert_equal(wheight, gheight, "check graphics dimension h matches window h")
  end

  # Translated to Ruby from love.test.graphics.getHeight
  # (vendor/love/testing/tests/graphics.lua:2811-2815): getHeight becomes
  # height (rule 3), with the rules test_get_dimensions names.
  def test_get_height
    # check graphics height match window height
    _wwidth, wheight, = Lota::Window.mode
    assert_equal(wheight, Lota::Graphics.height, "check graphics h matches window h")
  end

  # Translated to Ruby from love.test.graphics.getWidth
  # (vendor/love/testing/tests/graphics.lua:2848-2852): getWidth becomes
  # width (rule 3), with the rules test_get_dimensions names.
  def test_get_width
    # check graphics width match window width
    wwidth, = Lota::Window.mode
    assert_equal(wwidth, Lota::Graphics.width, "check graphics w matches window w")
  end

  # Translated to Ruby from love.test.graphics.getDPIScale
  # (vendor/love/testing/tests/graphics.lua:2795-2797): getDPIScale
  # becomes dpi_scale (rules 3 and 13).
  def test_get_dpi_scale
    assert_not_nil(Lota::Graphics.dpi_scale)
  end

  # Translated to Ruby from love.test.graphics.getPixelDimensions
  # (vendor/love/testing/tests/graphics.lua:2819-2826): getPixelDimensions
  # becomes pixel_dimensions (rules 3 and 13), with the rules
  # test_get_dimensions names.
  def test_get_pixel_dimensions
    # check graphics dimensions match window dimensions relative to dpi
    dpi = Lota::Graphics.dpi_scale
    gwidth, gheight = Lota::Graphics.pixel_dimensions
    wwidth, wheight, = Lota::Window.mode
    assert_equal(wwidth, gwidth / dpi, "check graphics pixel dpi w matches window w")
    assert_equal(wheight, gheight / dpi, "check graphics pixel dpi h matches window h")
  end

  # Translated to Ruby from love.test.graphics.getPixelHeight
  # (vendor/love/testing/tests/graphics.lua:2830-2835): getPixelHeight
  # becomes pixel_height (rules 3 and 13), with the rules
  # test_get_dimensions names.
  def test_get_pixel_height
    # check graphics height match window height relative to dpi
    dpi = Lota::Graphics.dpi_scale
    _wwidth, wheight, = Lota::Window.mode
    assert_equal(wheight, Lota::Graphics.pixel_height / dpi, "check graphics pixel dpi h matches window h")
  end

  # Translated to Ruby from love.test.graphics.getPixelWidth
  # (vendor/love/testing/tests/graphics.lua:2839-2844), which divides
  # getWidth, not getPixelWidth, by the scale, as Lövetest does: getWidth
  # becomes width (rule 3), with the rules test_get_dimensions names.
  def test_get_pixel_width
    # check graphics width match window width relative to dpi
    dpi = Lota::Graphics.dpi_scale
    wwidth, = Lota::Window.mode
    assert_equal(wwidth, Lota::Graphics.width / dpi, "check graphics pixel dpi w matches window w")
  end

  # Translated to Ruby from love.test.graphics.getTextureFormats
  # (vendor/love/testing/tests/graphics.lua:2863-2885): getTextureFormats
  # becomes texture_formats (rule 3), whose table of settings becomes
  # keywords and whose table of results a record that answers brackets
  # (rule 10); Lua's numeric for loop becomes each.
  def test_get_texture_formats
    formats = %w[
      hdr
      r8i
      r8ui
      r16i
      r16ui
      r32i
      r32ui
      rg8i
      rg8ui
      rg16i
      rg16ui
      rg32i
      rg32ui
      bgra8
      r8
      rgba8i
      rgba8ui
      rgba16i
      rg8
      rgba32i
      rgba32ui
      rgba8
      DXT1
      r16
      DXT5
      rg16
      BC4s
      rgba16
      BC5s
      r16f
      BC6hs
      BC7
      PVR1rgb2
      rg16f
      PVR1rgba2
      rgba16f
      ETC1
      r32f
      ETC2rgba
      rg32f
      EACr
      rgba32f
      EACrg
      rgba4
      ASTC4x4
      ASTC5x4
      rgb5a1
      ASTC6x5
      rgb565
      ASTC8x5
      ASTC8x6
      rgb10a2
      ASTC10x5
      rg11b10f
      ASTC10x8
      ASTC10x10
      ASTC12x10
      ASTC12x12
      normal
      srgba8
      la8
      ASTC10x6
      ASTC8x8
      ASTC6x6
      ASTC5x5
      EACrgs
      EACrs
      ETC2rgba1
      ETC2rgb
      PVR1rgba4
      PVR1rgb4
      BC6h
      BC5
      BC4
      DXT3
      rgba16ui
      bgra8srgb
      depth16
      depth24
      depth32f
      depth24stencil8
      depth32fstencil8
      stencil8
    ]
    supported = Lota::Graphics.texture_formats(canvas: true)
    assert_not_nil(supported)
    formats.each do |format|
      refute_equal(nil, supported[format], "expected a key for format: #{format}")
    end
  end

  # Translated to Ruby from love.test.graphics.getStats
  # (vendor/love/testing/tests/graphics.lua:2899-2908): getStats becomes
  # stats (rule 3), a record that answers brackets (rule 10).
  def test_get_stats
    stattypes = %w[
      drawcalls
      canvasswitches
      texturememory
      shaderswitches
      drawcallsbatched
      textures
      fonts
    ]
    stats = Lota::Graphics.stats
    stattypes.each do |stattype|
      refute_equal(nil, stats[stattype], "expected a key for stat: #{stattype}")
    end
  end

  # Translated to Ruby from love.test.graphics.getSupported
  # (vendor/love/testing/tests/graphics.lua:2912-2925): getSupported
  # becomes supported (rule 3), a record that answers brackets (rule 10).
  def test_get_supported
    # cant check values as hardware dependent but we can check the keys in the
    # table match what the documentation lists
    gfs = %w[
      clampzero
      lighten
      glsl3
      instancing
      fullnpot
      pixelshaderhighp
      shaderderivatives
      indirectdraw
      copytexturetobuffer
      multicanvasformats
      clampone
      glsl4
    ]
    features = Lota::Graphics.supported
    gfs.each do |gf|
      refute_equal(nil, features[gf], "expected a key for graphic feature: #{gf}")
    end
  end

  # Translated to Ruby from love.test.graphics.getSystemLimits
  # (vendor/love/testing/tests/graphics.lua:2929-2941): getSystemLimits
  # becomes system_limits (rule 3), a record that answers brackets
  # (rule 10).
  def test_get_system_limits
    # cant check values as hardware dependent but we can check the keys in the
    # table match what the documentation lists
    glimits = %w[
      texelbuffersize
      shaderstoragebuffersize
      threadgroupsx
      threadgroupsy
      pointsize
      texturesize
      texturelayers
      volumetexturesize
      cubetexturesize
      anisotropy
      texturemsaa
      multicanvas
      threadgroupsz
    ]
    limits = Lota::Graphics.system_limits
    glimits.each do |glimit|
      refute_equal(nil, limits[glimit], "expected a key for system limit: #{glimit}")
    end
  end

  # Translated to Ruby from love.test.graphics.getTextureTypes
  # (vendor/love/testing/tests/graphics.lua:2945-2955): getTextureTypes
  # becomes texture_types (rule 3), a record whose 2d field reads with
  # brackets, as in Lua (rule 10).
  def test_get_texture_types
    # cant check values as hardware dependent but we can check the keys in the
    # table match what the documentation lists
    ttypes = %w[2d array cube volume]
    types = Lota::Graphics.texture_types
    ttypes.each do |ttype|
      refute_equal(nil, types[ttype], "expected a key for texture type: #{ttype}")
    end
  end

  # Translated to Ruby from love.test.graphics.flushBatch
  # (vendor/love/testing/tests/graphics.lua:1508-1520): flushBatch becomes
  # flush_batch (rule 13), getStats stats, whose drawcalls reads with
  # brackets as in Lua (rules 3 and 10), and setCanvas the writer canvas=
  # (rule 5).
  def test_flush_batch
    Lota::Graphics.flush_batch
    initial = Lota::Graphics.stats["drawcalls"]
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.rectangle(:fill, 0, 0, 32, 32)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    Lota::Graphics.flush_batch
    after = Lota::Graphics.stats["drawcalls"]
    assert_equal(initial + 1, after, "check drawcalls increased")
  end
  # SPDX-SnippetEnd
end
