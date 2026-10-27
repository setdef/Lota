# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest"
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
  # The resources Lövetest's tests read (vendor/love/testing/resources).
  RESOURCES = File.expand_path("../../vendor/love/testing/resources", __dir__)

  class << self
    # The font Lövetest's love.load makes, which its text tests draw in:
    # its Lua global Font.
    attr_reader :font
  end

  # Translated to Ruby from the graphics settings Lövetest's love.load
  # makes before any test runs (vendor/love/testing/main.lua:46-57), once
  # per process, as love.load runs once. Its tests set them back when they
  # change them. setDefaultFilter becomes a writer of several values
  # (rule 6), and newFont Font.new (rule 2), with the hinting a symbol
  # (rule 9). Lövetest reads resources/ from its own folder, which LÖVE's
  # filesystem searches; each of Lota's runners, test/lovetest and
  # test/lovetest/game, has a resources/ beside its conf.rb that links to
  # Lövetest's. updateMode (lines 39-43) has no translation
  # yet: it asks for the 360 by 240 resizable, centered window that
  # test/lovetest/conf.rb already opens. The logo and quad it loads
  # (lines 50-54) are for Lövetest's own screen.
  def self.load
    return if @loaded

    if Lota.window && Lota.graphics
      Lota::Graphics.default_filter = :nearest, :nearest
      Lota::Graphics.line_style = :rough
      Lota::Graphics.line_width = 1
      @font = Lota::Graphics::Font.new("resources/font.ttf", 8, :normal)
    end
    @loaded = true
  end

  # Lövetest's GITHUB_RUNNER (vendor/love/testing/main.lua:86-111): true
  # when the tests run on a GitHub Actions runner, which LÖVE's own CI
  # says with --isRunner (vendor/love/.github/workflows/main.yml) and
  # GitHub says to Lota's with GITHUB_ACTIONS.
  GITHUB_RUNNER = ENV["GITHUB_ACTIONS"] == "true"

  # Lövetest's love.test.windowmode (vendor/love/testing/classes/
  # TestSuite.lua:25): whether the tests run with a window, which they
  # always do in Lota, as in Lövetest unless it is told otherwise.
  WINDOWMODE = true

  # Lövetest's TestMethod:isOS (vendor/love/testing/classes/TestMethod.lua:
  # 406-416): whether any of +names+ is this system's name as
  # love.system.getOS gives it ("OS X", "Windows", "Linux", "Android", or
  # "iOS"). Lota runs on macOS alone so far.
  def self.os?(*names)
    names.include?(RUBY_PLATFORM.include?("darwin") ? "OS X" : RUBY_PLATFORM)
  end

  # The resource file +name+, as the FileData LÖVE reads a resource into.
  def self.resource(name)
    Lota::Filesystem::FileData.new(File.binread(File.join(RESOURCES, name)), name)
  end

  # Translated to Ruby from Lövetest's TestMethod
  # (vendor/love/testing/classes/TestMethod.lua): the fields a graphics
  # test reads (lines 10-50), assertNotNil (lines 249-263), and
  # compareImg (lines 266-356). Lua's assertEquals becomes Minitest's
  # assert_equal, with the same message, and assertNotEquals, which
  # assertNotNil calls (lines 114-123), refute_equal.
  # compareImg also collects the differing pixels, saves the actual image,
  # and draws a picture of the differences for Lövetest's HTML report
  # (lines 326-353). That reporting is left out: Minitest reports the
  # first failing pixel itself, where Lövetest records every one, and the
  # test fails in both on the same images.
  class TestMethod < Minitest::Test
    # Run in the main thread, where Lota::Graphics runs.
    def setup
      EngineHelper.open_window
      Lovetest.load
      @rgba_tolerance = 0
      @pixel_tolerance = 0
      @imgs = 1
    end

    # The types whose tests Lövetest names by the type, capitalized as it
    # is, where it names the rest by a function (love.test.graphics.Quad and
    # love.test.graphics.newQuad); a test class lists its module's.
    TYPES = [].freeze

    # The Lövetest method this test translates: test_clear translates
    # love.test.graphics.clear, test_set_color, named by rule 13,
    # translates love.test.graphics.setColor, and test_sprite_batch, of a
    # type in TYPES, love.test.graphics.SpriteBatch.
    def lovetest_method
      method = name.delete_prefix("test_").gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
      type = method.sub(/\A[a-z]/, &:upcase)
      self.class::TYPES.include?(type) ? type : method
    end

    # Asserts that +value+ is true, as assertTrue does (lines 79-88): true
    # itself, not merely truthy.
    def assert_true(value, label = nil)
      assert_equal(true, value, label)
    end

    # Asserts that +value+ is not nil. An +err+, which Lövetest's tests pass
    # with the message of an error they caught, always fails the test, as
    # it does in Lövetest.
    def assert_not_nil(value, err = nil)
      refute_equal(nil, value, "check not nil")
      flunk(err) unless err.nil?
    end

    # Asserts that +obj+ is one of LÖVE's objects, as assertObject does
    # (lines 211-223): not nil, an object of the engine's, which Lua calls
    # userdata and Lota wraps around its native object, and one with a
    # type, which obj:type() gives in Lua and obj.type in Ruby (ADR 001,
    # rule 16).
    def assert_object(obj)
      assert_not_nil(obj)
      assert_equal(true, obj.respond_to?(:native), "check is userdata")
      refute_equal(nil, obj.type, "check has :type()") unless obj.nil?
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
