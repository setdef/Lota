# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"

# An image read from a PNG in plain Ruby, and compared with another by
# Lövetest's rule, for a check that runs where Lota is not loaded, such as
# the fuse workflow's (.github/fuse_check.rb).
module LovetestImage
  # The expected image of Lövetest's captureScreenshot test, in
  # vendor/love/testing/output/expected.
  SCREENSHOT = "love.test.graphics.captureScreenshot-1.png"

  # Raised for a file that is not a PNG this reads, or images of different
  # sizes.
  class Error < StandardError; end

  # An image +width+ by +height+ pixels, whose +pixels+ are row by row,
  # each [red, green, blue, alpha] from 0 to 255.
  class Image < Data.define(:width, :height, :pixels)
    # The pixel at +x+, +y+.
    def pixel(x, y) = pixels[(y * width) + x]
  end

  SIGNATURE = "\x89PNG\r\n\x1A\n".b

  # The channels of each of PNG's colour types: grey, RGB, indexed, grey
  # with alpha, and RGBA.
  CHANNELS = { 0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4 }.freeze

  # Reads the PNG at +path+: of any colour type and bit depth, but not
  # interlaced, which no image Lövetest expects or LÖVE saves is. A
  # 16-bit sample keeps its high byte.
  module_function def read(path)
    header, palette, alphas, data = chunks(File.binread(path), path)
    width, height, depth, color, _, _, interlace = header.unpack("NNC5")
    raise Error, "#{path} is interlaced" unless interlace.zero?
    raise Error, "#{path} has colour type #{color}" unless CHANNELS.key?(color)

    channels = CHANNELS.fetch(color)
    rows = unfilter(Zlib::Inflate.inflate(data), height, ((width * channels * depth) + 7) / 8,
      [(channels * depth) / 8, 1].max)
    pixels = rows.flat_map do |row|
      samples(row, depth).first(width * channels).each_slice(channels).map do |sample|
        rgba(sample, color, depth, palette, alphas)
      end
    end
    Image.new(width:, height:, pixels:)
  end

  # The header, palette, transparency, and joined image data of +png+.
  module_function def chunks(png, path)
    raise Error, "#{path} is not a PNG" unless png.start_with?(SIGNATURE)

    found = Hash.new { |hash, key| hash[key] = +"".b }
    at = SIGNATURE.bytesize
    while at < png.bytesize
      length, type = png.unpack("Na4", offset: at)
      found[type] << png.byteslice(at + 8, length)
      at += length + 12
    end
    [found["IHDR"], found["PLTE"].bytes.each_slice(3).to_a, found["tRNS"].bytes, found["IDAT"]]
  end

  # The rows of +data+, each +stride+ bytes, with PNG's filters undone,
  # for pixels +step+ bytes apart.
  module_function def unfilter(data, height, stride, step)
    previous = Array.new(stride, 0)
    Array.new(height) do |y|
      filter, *row = data.byteslice(y * (stride + 1), stride + 1).bytes
      row.each_index do |i|
        left = (i >= step) ? row[i - step] : 0
        up = previous[i]
        corner = (i >= step) ? previous[i - step] : 0
        row[i] = (row[i] + predict(filter, left, up, corner)) & 0xFF
      end
      previous = row
    end
  end

  # What +filter+ predicts from the bytes to the left, above, and above
  # to the left.
  module_function def predict(filter, left, up, corner)
    case filter
    when 0 then 0
    when 1 then left
    when 2 then up
    when 3 then (left + up) / 2
    when 4 then paeth(left, up, corner)
    else raise Error, "unknown PNG filter #{filter}"
    end
  end

  module_function def paeth(left, up, corner)
    estimate = left + up - corner
    distances = [left, up, corner].map { |value| (estimate - value).abs }
    return left if distances[0] <= distances[1] && distances[0] <= distances[2]

    (distances[1] <= distances[2]) ? up : corner
  end

  # The samples of +row+, each +depth+ bits.
  module_function def samples(row, depth)
    case depth
    when 8 then row
    when 16 then row.each_slice(2).map(&:first)
    else row.flat_map { |byte| (8 / depth).times.map { |i| (byte >> (8 - (depth * (i + 1)))) & ((1 << depth) - 1) } }
    end
  end

  # A pixel's 8-bit RGBA from its +sample+. For an indexed image,
  # +alphas+ holds each palette entry's alpha; for a grey or RGB one, the
  # transparent colour, a 16-bit value for each channel, of which a
  # 16-bit sample keeps the high byte as it does of its own.
  module_function def rgba(sample, color, depth, palette, alphas)
    return [*palette.fetch(sample[0]), alphas.fetch(sample[0], 255)] if color == 3

    scale = (depth < 8) ? 255 / ((1 << depth) - 1) : 1
    values = sample.map { |value| value * scale }
    transparent = alphas.each_slice(2).map { |high, low| (depth == 16) ? high : low }
    alpha = (sample == transparent) ? 0 : 255
    case color
    when 0 then [values[0], values[0], values[0], alpha]
    when 2 then [*values, alpha]
    when 4 then [values[0], values[0], values[0], values[1]]
    else values
    end
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # The pixels where +actual+ is not +expected+, by Lövetest's compareImg
  # (vendor/love/testing/classes/TestMethod.lua:266-325) at the tolerance
  # a test leaves unless it sets one, as its captureScreenshot test does:
  # none, so each component of each pixel must be the one expected. Each
  # is [x, y, actual pixel, expected pixel], column by column, the order
  # compareImg visits them. compareImg reads the expected image at each
  # pixel of the actual one, which fails for a smaller one, so images of
  # different sizes raise.
  module_function def differences(actual, expected)
    unless [actual.width, actual.height] == [expected.width, expected.height]
      raise Error, "the image is #{actual.width}x#{actual.height}, " \
        "and the expected image #{expected.width}x#{expected.height}"
    end

    (0...(actual.width)).flat_map do |x|
      (0...(actual.height)).filter_map do |y|
        pixel = actual.pixel(x, y)
        [x, y, pixel, expected.pixel(x, y)] unless pixel == expected.pixel(x, y)
      end
    end
  end
  # SPDX-SnippetEnd
end
