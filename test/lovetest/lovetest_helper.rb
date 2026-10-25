# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../engine_helper"

# Lövetest, LÖVE's own test suite (vendor/love/testing), translated to Ruby
# by ADR 001's rules (Plan 001, "What correct means"). Each translated test
# runs in a real window, as Lövetest does, and compares what Lota draws
# with the images LÖVE drew.
module Lovetest
  # LÖVE's expected images (vendor/love/testing/output/expected).
  EXPECTED = File.expand_path("../../vendor/love/testing/output/expected", __dir__)

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from Lövetest's TestMethod
  # (vendor/love/testing/classes/TestMethod.lua): the fields a graphics
  # test reads (lines 10-50) and compareImg (lines 266-356). Lua's
  # assertEquals becomes Minitest's assert_equal, with the same message.
  # compareImg also collects the differing pixels, saves the actual image,
  # and draws a picture of the differences for Lövetest's HTML report
  # (lines 326-353). That reporting is left out: Minitest reports the
  # first failing pixel itself, where Lövetest records every one, and the
  # test fails in both on the same images.
  class TestMethod < Minitest::Test
    # Run in the main thread, where Lota::Graphics runs.
    def setup
      EngineHelper.open_window
      @rgba_tolerance = 0
      @pixel_tolerance = 0
      @imgs = 1
    end

    # The Lövetest method this test translates: test_clear translates
    # love.test.graphics.clear.
    def lovetest_method
      name.delete_prefix("test_")
    end

    # Compares +imgdata+ with LÖVE's expected image, pixel by pixel, with a
    # tolerance of @rgba_tolerance 8-bit steps in each component and
    # @pixel_tolerance pixels in any direction.
    def compare_img(imgdata)
      expected_path = File.join(EXPECTED, "love.test.graphics.#{lovetest_method}-#{@imgs}.png")
      begin
        expected = Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(File.binread(expected_path),
          File.basename(expected_path)))
      rescue => e
        return assert_equal(true, false, e.message)
      end
      iw = imgdata.width - 1
      ih = imgdata.height - 1
      # Lua's 1/255 divides as floats; Ruby's would divide as integers.
      rgba_tolerance = @rgba_tolerance * (1.0 / 255)

      # for each pixel, compare the expected vs the actual pixel data
      # by default rgba_tolerance is 0
      (0..iw).each do |ix|
        (0..ih).each do |iy|
          ir, ig, ib, ia = imgdata.pixel(ix, iy)
          points = [
            expected.pixel(ix, iy),
          ]
          if @pixel_tolerance > 0
            points << expected.pixel(ix - 1, iy + 1) if ix > 0 && iy < ih - 1
            points << expected.pixel(ix - 1, iy) if ix > 0
            points << expected.pixel(ix - 1, iy - 1) if ix > 0 && iy > 0
            points << expected.pixel(ix, iy + 1) if iy < ih - 1
            points << expected.pixel(ix, iy - 1) if iy > 0
            points << expected.pixel(ix + 1, iy + 1) if ix < iw - 1 && iy < ih - 1
            points << expected.pixel(ix + 1, iy) if ix < iw - 1
            points << expected.pixel(ix + 1, iy - 1) if ix < iw - 1 && iy > 0
          end
          has_match_r = false
          has_match_g = false
          has_match_b = false
          has_match_a = false
          points.each do |epoint|
            has_match_r = true if ir >= epoint[0] - rgba_tolerance && ir <= epoint[0] + rgba_tolerance
            has_match_g = true if ig >= epoint[1] - rgba_tolerance && ig <= epoint[1] + rgba_tolerance
            has_match_b = true if ib >= epoint[2] - rgba_tolerance && ib <= epoint[2] + rgba_tolerance
            has_match_a = true if ia >= epoint[3] - rgba_tolerance && ia <= epoint[3] + rgba_tolerance
          end
          matching = has_match_r && has_match_g && has_match_b && has_match_a
          ymatch = ""
          nmatch = ""
          if has_match_r then ymatch += "r" else nmatch += "r" end
          if has_match_g then ymatch += "g" else nmatch += "g" end
          if has_match_b then ymatch += "b" else nmatch += "b" end
          if has_match_a then ymatch += "a" else nmatch += "a" end
          pixel = "#{ir},#{ig},#{ib},#{ia}"
          assert_equal(true, matching, "compare image pixel (#{pixel}) at #{ix},#{iy}, matching = #{ymatch}, " \
            "not matching = #{nmatch} (#{lovetest_method}-#{@imgs})")
        end
      end
      @imgs += 1
    end
  end
  # SPDX-SnippetEnd
end
