# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.image tests (vendor/love/testing/tests/image.lua),
# translated to Ruby by ADR 001's rules. They run in the test suite's own
# process (test/lovetest/image_test.rb) and under lota run
# (test/lovetest/game), also from the installed precompiled gem.
class ImageTest < Lovetest::TestMethod
  TYPES = %w[ImageData].freeze

  # test_image_data leaves the Files it opened to the garbage collector,
  # as Lövetest leaves them to Lua's, and a File open in the save
  # directory keeps LÖVE from changing it (physfs/Filesystem.cpp,
  # setIdentity). Lövetest runs love.filesystem's tests before
  # love.image's; Minitest runs tests in any order, so the Files are
  # collected before the next test, which closes them.
  def teardown
    super
    GC.start
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.image.ImageData
  # (vendor/love/testing/tests/image.lua:44-107): newImageData becomes
  # ImageData.new (rule 2), with its pixel format a symbol (rule 9), the
  # getters drop get (rule 3), getDimensions' and getPixel's results are
  # Arrays (rule 4), setPixel and setLinear writers (rules 5 and 6),
  # isLinear linear? (rule 8), and mapPixel's function a block, given the
  # rectangle first (rule 12). openFile becomes open_file, whose result is
  # an Array of what it returns, of which Lua keeps the first (rule 4).
  def test_image_data
    # create obj
    idata = Lota::Image::ImageData.new("resources/love.png")
    assert_object(idata)

    # check string + size
    refute_equal(nil, idata.string, "check data string")
    assert_equal(16384, idata.size, "check data size")

    # check img dimensions
    iw, ih = idata.dimensions
    assert_equal(64, iw, "check image dimension w")
    assert_equal(64, ih, "check image dimension h")
    assert_equal(64, idata.width, "check image direct w")
    assert_equal(64, idata.height, "check image direct h")

    # check format
    assert_equal(:rgba8, idata.format, "check image format")

    # manipulate image data so white heart is black
    idata.map_pixel(0, 0, 64, 64) do |_x, _y, r, g, b, a|
      if r == 1 && g == 1 && b == 1
        r = 0
        g = 0
        b = 0
      end
      [r, g, b, a]
    end
    r1, g1, b1, = idata.pixel(25, 25)
    assert_equal(0, r1 + g1 + b1, "check mapped black")

    # map some other data into the idata
    idata2 = Lota::Image::ImageData.new("resources/loveinv.png")
    idata.paste(idata2, 0, 0, 0, 0)
    r1, g1, b1, = idata.pixel(25, 25)
    assert_equal(3, r1 + g1 + b1, "check back to white")

    # set pixels directly
    idata.pixel = 25, 25, 1, 0, 0, 1
    r2, g2, b2, = idata.pixel(25, 25)
    assert_equal(1, r2 + g2 + b2, "check set to red")

    # check encoding to an image (png)
    idata.encode(:png, "test-encode.png")
    read1 = Lota::Filesystem.open_file("test-encode.png", :r).first
    assert_not_nil(read1)
    Lota::Filesystem.remove("test-encode.png")

    # check encoding to an image (exr)
    edata = Lota::Image::ImageData.new(100, 100, :r16f)
    edata.encode(:exr, "test-encode.exr")
    read2 = Lota::Filesystem.open_file("test-encode.exr", :r).first
    assert_not_nil(read2)
    Lota::Filesystem.remove("test-encode.exr")

    # check linear
    assert_false(idata.linear?, "check not linear")
    idata.linear = true
    assert_true(idata.linear?, "check now linear")
  end
  # SPDX-SnippetEnd
end
