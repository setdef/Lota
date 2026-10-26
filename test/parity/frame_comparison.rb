# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "lota"
require "lota_native_test"

module Parity
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Lövetest's compareImg (vendor/love/testing/classes/TestMethod.lua:
  # 272-330), at the tolerances every test starts with (rgba_tolerance and
  # pixel_tolerance 0, lines 23-24), for a whole frame of 8-bit pixels.
  #
  # compareImg reads each pixel of both images as floats and fails on the
  # first one, column by column, whose components are not all equal. With
  # no tolerance, a component matches exactly when it is equal, and two
  # 8-bit components are equal as floats exactly when their bytes are, so
  # two frames match exactly when their bytes do. That one comparison
  # stands in for compareImg's 480,000 pixel by pixel ones on a frame of
  # 800 by 600, which Ruby would take seconds over, frame after frame. When
  # the bytes differ, the pixel compareImg would fail on first is found row
  # by row, and its message is compareImg's own, with the frame for the test
  # name. A frame of another size has no pixel compareImg could compare; it
  # fails with its size instead.
  class FrameComparison
    # The message compareImg's assertion would fail with, or +nil+ when the
    # frames match.
    attr_reader :message

    # Compares +actual+ with +expected+, each a Lota::Image::ImageData, as
    # compareImg does; +label+ names the frame in the message, as
    # compareImg names its test.
    def initialize(expected, actual, label)
      @message = if [expected.width, expected.height] != [actual.width, actual.height]
        "frame is #{actual.width}x#{actual.height}, expected #{expected.width}x#{expected.height} (#{label})"
      elsif bytes(expected) != bytes(actual)
        first_difference(expected, actual, label)
      end
    end

    # Whether the frames match.
    def match?
      @message.nil?
    end

    private def bytes(image)
      LotaNativeTest.image_data_bytes(image.native)
    end

    # compareImg's message for the first pixel it would fail on: the
    # smallest column holding a difference, and the smallest row in it.
    private def first_difference(expected, actual, label)
      row_size = actual.width * 4
      expected_bytes = bytes(expected)
      actual_bytes = bytes(actual)
      ix, iy = (0...(actual.height)).filter_map do |row|
        range = row * row_size, row_size
        next if expected_bytes.byteslice(*range) == actual_bytes.byteslice(*range)

        column = (0...(actual.width)).find do |x|
          expected_bytes.byteslice(range.first + (x * 4), 4) != actual_bytes.byteslice(range.first + (x * 4), 4)
        end
        [column, row]
      end.min
      pixel_message(expected.pixel(ix, iy), actual.pixel(ix, iy), ix, iy, label)
    end

    private def pixel_message(epoint, ipoint, ix, iy, label)
      matches = %w[r g b a].zip(ipoint, epoint).map { |channel, i, e| [channel, i == e] }
      ymatch = matches.filter_map { |channel, matched| channel if matched }.join
      nmatch = matches.filter_map { |channel, matched| channel unless matched }.join
      pixel = ipoint.join(",")
      "compare image pixel (#{pixel}) at #{ix},#{iy}, matching = #{ymatch}, not matching = #{nmatch} (#{label})"
    end
  end
  # SPDX-SnippetEnd
end
