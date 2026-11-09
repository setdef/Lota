# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Image
    # An image in a compressed format the graphics card decodes itself,
    # such as DXT1, ETC, or ASTC, with its mipmaps, matching LÖVE's
    # CompressedImageData class (src/modules/image/CompressedImageData.h).
    #
    # A PNG takes little space on disk, but decoded it takes four bytes a
    # pixel on the graphics card. A compressed format such as DXT1 takes
    # half a byte a pixel there too, and loads without being decoded, so
    # a game with many large textures fits in less memory.
    #
    # A CompressedImageData holds such an image, read from a DDS, KTX, PVR,
    # PKM, or ASTC file by Lota::Image::CompressedData.new, which LÖVE
    # calls love.image.newCompressedData. Its pixels cannot be read one at
    # a time, as an ImageData's can; make a texture of it with
    # Lota::Graphics::Image.new and draw that. It is a Data, so it
    # inherits from Lota::Data, whose #size and #string give its bytes,
    # those of every mipmap.
    #
    # === Example
    #
    #   compressed = Lota::Image::CompressedData.new("assets/ship.dds")
    #   compressed.format       # => :DXT1
    #   compressed.mipmap_count # => 7
    #   ship = Lota::Graphics::Image.new(compressed)
    class CompressedImageData < Data
      # Wraps a CompressedImageData the engine made. :nodoc:
      private_class_method def self.from_native(native)
        data = allocate
        data.instance_variable_set(:@native, native)
        data
      end

      # Makes this CompressedImageData, a copy of +source+ by Ruby's
      # +clone+ or +dup+, LÖVE's copy, matching CompressedImageData:clone
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_clone): a new one with a copy of the bytes of
      # every mipmap, so setting one linear leaves the other as it was
      # (ADR 001, section 7).
      #
      # === Example
      #
      #   copy = compressed.clone
      #   copy.linear = true
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # The width in pixels of +mipmap+, as an Integer, matching
      # CompressedImageData:getWidth
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_getWidth).
      #
      # [mipmap] Integer mipmap, counting from 1; the first, the full-size
      #   image, when +nil+ or left out.
      #
      # Raises RuntimeError with LÖVE's message ("Mipmap level 8 does not
      # exist") for a mipmap the image does not have.
      #
      # === Example
      #
      #   compressed.width    # => 64
      #   compressed.width(2) # => 32
      def width(mipmap = nil)
        @native.width(Integer(mipmap || 1))
      end

      # The height in pixels of +mipmap+, as #width measures its width,
      # matching CompressedImageData:getHeight
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_getHeight).
      #
      # === Example
      #
      #   compressed.height(3) # => 16
      def height(mipmap = nil)
        @native.height(Integer(mipmap || 1))
      end

      # The width and height in pixels of +mipmap+, as #width measures
      # them, as an Array of two Integers (ADR 001, rule 4), matching
      # CompressedImageData:getDimensions
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_getDimensions).
      #
      # === Example
      #
      #   width, height = compressed.dimensions
      def dimensions(mipmap = nil)
        @native.dimensions(Integer(mipmap || 1))
      end

      # How many mipmaps the image holds, the full-size image among them,
      # as an Integer, matching CompressedImageData:getMipmapCount
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_getMipmapCount).
      #
      # === Example
      #
      #   compressed.mipmap_count # => 7
      def mipmap_count
        @native.mipmap_count
      end

      # The compressed pixel format, as a Symbol (ADR 001, rule 9), such
      # as +:DXT1+, +:ETC2rgb+, or +:ASTC4x4+, or +:unknown+ for one LÖVE
      # has no name for, matching CompressedImageData:getFormat
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_getFormat). LÖVE reads every format as
      # linear when it loads it, so the format never ends in +srgb+.
      #
      # === Example
      #
      #   compressed.format # => :DXT1
      def format
        @native.format.to_sym
      end

      # Sets whether the pixels hold linear rather than sRGB color, which a
      # texture made from it then follows, matching
      # CompressedImageData:setLinear
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_setLinear). It must be +true+ or +false+.
      #
      # === Example
      #
      #   compressed.linear = true
      def linear=(linear)
        raise TypeError, "wrong argument type #{linear.class} (expected true or false)" unless [true, false].include?(linear)

        @native.set_linear(linear == true)
      end

      # Whether the pixels hold linear rather than sRGB color, matching
      # CompressedImageData:isLinear
      # (src/modules/image/wrap_CompressedImageData.cpp,
      # w_CompressedImageData_isLinear).
      #
      # === Example
      #
      #   compressed.linear? # => false
      def linear?
        @native.linear?
      end
    end
  end
end
