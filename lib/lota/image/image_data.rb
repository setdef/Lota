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
    # one you expected, to inspect a decoded file, or to draw pixels of
    # your own. It is a Data, so it includes Lota::Data, whose #size and
    # #string give its bytes.
    #
    # Its pixels read and write as LÖVE runs ImageData's methods, in the
    # LuaJIT code that takes over from their C++
    # (src/modules/image/wrap_ImageData.lua): each component is a Float,
    # computed in double precision, where the C++ computes in single
    # precision, so an 8-bit 128 reads as 128 / 255.0, 0.5019607843137255.
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
      include Object
      include Data

      # The engine's ImageData, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps an ImageData the engine made, such as one read back from a
      # canvas. :nodoc:
      def self.from_native(native)
        image_data = allocate
        image_data.instance_variable_set(:@native, native)
        image_data
      end

      # Makes an ImageData, matching love.image.newImageData
      # (src/modules/image/wrap_Image.cpp, w_newImageData), in one of two
      # forms:
      #
      # - <tt>ImageData.new(width, height, format = :rgba8, rawdata =
      #   nil)</tt>: +width+ by +height+ pixels, as Integers, of the
      #   pixel format +format+, a Symbol such as <tt>:rgba8</tt>,
      #   <tt>:r16</tt>, or <tt>:rgba32f</tt> (ADR 001, rule 9), all
      #   transparent black, or a copy of +rawdata+, a String or a
      #   Lota::Data of exactly as many bytes as the pixels take.
      # - <tt>ImageData.new(file)</tt>: the image in +file+, a String
      #   name of an image file in the game's folder, or a
      #   Lota::Filesystem::FileData, decoded from a format LÖVE's image
      #   module reads, such as PNG, JPEG, or QOI. A file name is a path in
      #   the game's folder, as Lota::Graphics::Font.new reads one.
      #
      # Raises RuntimeError with LÖVE's message for a +width+ or +height+
      # below 1, for +rawdata+ of the wrong size, when the file cannot be
      # read or no decoder can read the data, or when the module is not
      # open; and ArgumentError for a pixel format LÖVE does not know.
      #
      # === Examples
      #
      #   Lota::Image::ImageData.new(16, 16)
      #   Lota::Image::ImageData.new(1, 1, :rgba8, "\xFF\x00\x00\xFF")
      #   png = File.binread("logo.png")
      #   Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(png, "logo.png"))
      #   Lota::Image::ImageData.new("assets/logo.png")
      def initialize(source, height = nil, format = nil, rawdata = nil)
        @native = case source
        when Numeric
          bytes = case rawdata
          when Data then data_bytes(rawdata)
          else rawdata
          end
          Native::Image.new_sized_image_data(source, Integer(height), format && EnumName.of(format), bytes)
        when String then Native::Image.new_image_data(Native::Filesystem.file_data(source))
        else Native::Image.new_image_data(source.native)
        end
      end

      # Makes this ImageData, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching ImageData:clone
      # (src/modules/image/wrap_ImageData.cpp, w_ImageData_clone): a new
      # ImageData with a copy of every pixel, so a change to one leaves
      # the other as it was (ADR 001, section 7).
      #
      # === Example
      #
      #   copy = image_data.clone
      #   copy.pixel = 0, 0, 1, 0, 0
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # The width in pixels, as an Integer, matching ImageData:getWidth as
      # LÖVE runs it, in its LuaJIT code
      # (src/modules/image/wrap_ImageData.lua).
      #
      # === Example
      #
      #   image_data.width # => 16
      def width
        @native.width
      end

      # The height in pixels, as an Integer, matching ImageData:getHeight
      # as LÖVE runs it, in its LuaJIT code
      # (src/modules/image/wrap_ImageData.lua).
      #
      # === Example
      #
      #   image_data.height # => 16
      def height
        @native.height
      end

      # The width and height in pixels, as an Array of two Integers (ADR
      # 001, rule 4), matching ImageData:getDimensions as LÖVE runs it, in
      # its LuaJIT code (src/modules/image/wrap_ImageData.lua).
      #
      # === Example
      #
      #   width, height = image_data.dimensions
      def dimensions
        [@native.width, @native.height]
      end

      # The pixel format, as a Symbol (ADR 001, rule 9), matching
      # ImageData:getFormat as LÖVE runs it, in its LuaJIT code
      # (src/modules/image/wrap_ImageData.lua).
      #
      # === Example
      #
      #   Lota::Image::ImageData.new(4, 4).format # => :rgba8
      def format
        @native.format.to_sym
      end

      # Sets whether the pixels hold linear rather than sRGB color, matching
      # ImageData:setLinear (src/modules/image/wrap_ImageData.cpp,
      # w_ImageData_setLinear). It must be +true+ or +false+.
      #
      # === Example
      #
      #   image_data.linear = true
      def linear=(linear)
        raise TypeError, "wrong argument type #{linear.class} (expected true or false)" unless [true, false].include?(linear)

        @native.set_linear(linear == true)
      end

      # Whether the pixels hold linear rather than sRGB color, matching
      # ImageData:isLinear (src/modules/image/wrap_ImageData.cpp,
      # w_ImageData_isLinear).
      #
      # === Example
      #
      #   image_data.linear? # => false
      def linear?
        @native.linear?
      end

      # Copies a rectangle of +source+'s pixels into this ImageData at
      # +dx+, +dy+, matching ImageData:paste
      # (src/modules/image/wrap_ImageData.cpp, w_ImageData_paste), which
      # converts between pixel formats and leaves out what falls outside
      # either image.
      #
      # [source] The Lota::Image::ImageData to copy from.
      # [dx] Integer column to copy to.
      # [dy] Integer row to copy to.
      # [sx] Integer left column of the rectangle in +source+, 0 by default.
      # [sy] Integer top row, 0 by default.
      # [sw] Integer width of the rectangle, +source+'s by default.
      # [sh] Integer height, +source+'s by default.
      #
      # Raises TypeError when +source+ is not an ImageData.
      #
      # === Example
      #
      #   canvas_data.paste(sprite_data, 10, 20)
      def paste(source, dx, dy, sx = 0, sy = 0, sw = nil, sh = nil)
        raise TypeError, "wrong argument type #{source.class} (expected Lota::Image::ImageData)" unless source.is_a?(ImageData)

        @native.paste(source.native, Integer(dx), Integer(dy), Integer(sx), Integer(sy), sw && Integer(sw), sh && Integer(sh))
      end

      # The image encoded as a file in +format+, as a
      # Lota::Filesystem::FileData, matching ImageData:encode
      # (src/modules/image/wrap_ImageData.cpp, w_ImageData_encode). The
      # whole image is encoded by LÖVE's C++, so it takes no Ruby per
      # pixel.
      #
      # [format] +:png+, +:tga+, +:exr+, or another encoded image format
      #   LÖVE knows (ADR 001, rule 9).
      # [filename] When given, the name the file is also written to in the
      #   save directory, as LÖVE writes it; +Image.+ and the format's name
      #   otherwise, as the FileData's name.
      #
      # Raises ArgumentError for a format LÖVE does not know, and
      # RuntimeError, with LÖVE's message, when LÖVE cannot encode the
      # pixel format in +format+, or cannot write the file.
      #
      # === Examples
      #
      #   png = image_data.encode(:png)
      #   image_data.encode(:png, "screenshot.png")
      def encode(format, filename = nil)
        Filesystem::FileData.from_native(@native.encode(EnumName.of(format), filename))
      end

      # The color of the pixel at +x+, +y+, as an Array of red, green,
      # blue, and alpha Floats, matching ImageData:getPixel as LÖVE runs
      # it, in its LuaJIT code (src/modules/image/wrap_ImageData.lua).
      #
      # [x] Float or Integer column, from 0 at the left, rounded down.
      # [y] Float or Integer row, from 0 at the top, rounded down.
      #
      # Each component is computed in double precision from the format's
      # own: an 8-bit component divided by 255.0, a 16-bit one by 65535.0,
      # a float as it is. A component the format lacks reads as 0, and a
      # missing alpha as 1. Raises RuntimeError, with LÖVE's message,
      # outside the image ("Attempt to get out-of-range pixel!"), and for a
      # pixel format the Lua does not read, such as <tt>:srgba8</tt>.
      #
      # === Example
      #
      #   red, green, blue, alpha = image_data.pixel(0, 0)
      def pixel(x, y)
        @native.pixel(x, y)
      end

      # Sets the color of a pixel, matching ImageData:setPixel as LÖVE
      # runs it, in its LuaJIT code (src/modules/image/wrap_ImageData.lua),
      # whose several values rule 6 of ADR 001 makes one Array.
      #
      # [arguments] An Array of the pixel's column and row, each rounded
      #   down, then its red, green, and blue, and an optional alpha, each
      #   a Float or Integer, or an Array of the four.
      #
      # Each component is stored as the format stores it: an 8-bit one as
      # (component clamped to 0..1) * 255 + 0.5, cut to a whole number, a
      # float as it is; a missing alpha stores the format's largest value.
      # Raises TypeError, with LÖVE's message, for a color component that
      # is not a number, and RuntimeError outside the image or for a pixel
      # format the Lua does not write.
      #
      # === Examples
      #
      #   image_data.pixel = 0, 0, 1, 0, 0
      #   image_data.pixel = 0, 0, [1, 0, 0, 0.5]
      def pixel=(arguments)
        @native.set_pixel(arguments)
      end

      # Calls the block with each pixel's position and color in a
      # rectangle, and sets the pixel to the color it returns, matching
      # ImageData:mapPixel as LÖVE runs it, in its LuaJIT code
      # (src/modules/image/wrap_ImageData.lua), whose function becomes
      # the block (ADR 001, rule 12).
      #
      # [x] Float or Integer left column of the rectangle, 0 by default.
      # [y] Float or Integer top row, 0 by default.
      # [width] Float or Integer columns, every column by default.
      # [height] Float or Integer rows, every row by default.
      #
      # The block receives the column and the row, as Integers, and the
      # red, green, blue, and alpha, as #pixel reads them, row by row,
      # and returns the new color as an Array of red, green, blue, and
      # alpha, which are stored as #pixel= stores them. Raises
      # RuntimeError, with LÖVE's message, for a rectangle that is not
      # inside the image, which it checks before rounding it down, and for
      # a pixel format the Lua does not read.
      #
      # === Example
      #
      #   image_data.map_pixel { |_x, _y, r, g, b, a| [1 - r, 1 - g, 1 - b, a] }
      def map_pixel(x = nil, y = nil, width = nil, height = nil, &block)
        @native.map_pixel([block, x, y, width, height])
      end

      # The bytes of +data+, as a String: none for an empty Data, whose
      # string LÖVE would refuse, so that LÖVE's own message about the
      # size is the one raised.
      private def data_bytes(data)
        data.size.zero? ? "" : data.string
      end
    end
  end
end
