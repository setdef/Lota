# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Image
    # A grid of pixels in memory, decoded from a file or read back from a
    # canvas.
    #
    # What a game draws ends up on the graphics card, out of Ruby's reach.
    # A test that asks "is this pixel yellow?" or a tool that compares two
    # frames needs each pixel's color as numbers.
    #
    # An ImageData holds those numbers. Decode one from an image file, or
    # get one from Lota::Graphics.readback_texture, then read its pixels.
    #
    # Use it to check what a canvas holds, to compare an image with the
    # one you expected, or to inspect a decoded file.
    #
    # === Examples
    #
    #   data = Lota::Filesystem::FileData.new(File.binread("logo.png"), "logo.png")
    #   logo = Lota::Image::ImageData.new(data)
    #   logo.width  # => 64
    #
    #   canvas = Lota::Graphics::Canvas.new(16, 16)
    #   Lota::Graphics.canvas = canvas
    #   Lota::Graphics.clear(1, 1, 0)
    #   Lota::Graphics.canvas = nil
    #   Lota::Graphics.readback_texture(canvas).pixel(8, 8) # => [1.0, 1.0, 0.0, 1.0]
    class ImageData
      # The engine's ImageData, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps an ImageData the engine made, such as one read back from a
      # canvas. :nodoc:
      def self.from_native(native)
        image_data = allocate
        image_data.instance_variable_set(:@native, native)
        image_data
      end

      # Decodes the image file in +data+, matching
      # love.image.newImageData(filedata)
      # (src/modules/image/wrap_Image.cpp, w_newImageData).
      #
      # [data] Lota::Filesystem::FileData holding an image in a format
      #   LÖVE's image module decodes, such as PNG, JPEG, or QOI.
      #
      # Raises RuntimeError with LÖVE's message when no decoder can read
      # the data. LÖVE also makes a blank ImageData from a width and a
      # height, and decodes a file by name; Lota binds neither form yet.
      #
      # === Example
      #
      #   png = File.binread("logo.png")
      #   Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(png, "logo.png"))
      def initialize(data)
        @native = Native::Image.new_image_data(data.native)
      end

      # The width in pixels, matching ImageData:getWidth
      # (src/modules/image/wrap_ImageData.cpp).
      #
      # === Example
      #
      #   image_data.width # => 16
      def width
        @native.width
      end

      # The height in pixels, matching ImageData:getHeight
      # (src/modules/image/wrap_ImageData.cpp).
      #
      # === Example
      #
      #   image_data.height # => 16
      def height
        @native.height
      end

      # The color of the pixel at +x+, +y+, as an Array of red, green,
      # blue, and alpha, each from 0.0 to 1.0, matching
      # ImageData:getPixel(x, y) (src/modules/image/wrap_ImageData.cpp).
      #
      # [x] Integer column, from 0 at the left to <tt>width - 1</tt>.
      # [y] Integer row, from 0 at the top to <tt>height - 1</tt>.
      #
      # The engine stores each component as a single-precision float and
      # converts it as LÖVE does, so an 8-bit 255 reads as exactly 1.0.
      # Raises RuntimeError ("Attempt to get out-of-range pixel!") outside
      # the image.
      #
      # === Example
      #
      #   red, green, blue, alpha = image_data.pixel(0, 0)
      def pixel(x, y)
        @native.pixel(x, y)
      end
    end
  end
end
