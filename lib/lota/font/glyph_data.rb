# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Font
    # The pixels and metrics of one glyph, matching LÖVE's GlyphData class
    # (src/modules/font/GlyphData.h).
    #
    # A Lota::Font::Rasterizer makes one for each glyph it is asked for:
    # the glyph's pixels, in the pixel format the rasterizer draws in, and
    # where they go relative to the pen: the bearing from the pen to the
    # top-left pixel, the bounding box, and the advance to the next glyph.
    # It is a Data, so it inherits from Lota::Data, whose #size and
    # #string give its pixels' bytes.
    #
    # Use it to inspect a glyph, or to draw its pixels yourself.
    #
    # === Example
    #
    #   glyph = Lota::Font::GlyphData.new(rasterizer, "a")
    #   glyph.dimensions # => [8, 8]
    #   glyph.format     # => :la8
    class GlyphData < Data
      # Its +new+, the constructor love.font.newGlyphData becomes
      # (rule 2 of doc/contributors/design/translation.md), which Lota::Object
      # leaves private.
      public_class_method :new

      # Wraps a GlyphData the engine made. :nodoc:
      private_class_method def self.from_native(native)
        glyph_data = allocate
        glyph_data.instance_variable_set(:@native, native)
        glyph_data
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Makes the glyph of +glyph+ in +rasterizer+, matching
      # love.font.newGlyphData (src/modules/font/wrap_Font.cpp:217-237),
      # as Lota::Font::Rasterizer#glyph_data does.
      #
      # [rasterizer] The Lota::Font::Rasterizer to draw it with.
      # [glyph] String whose first character is the glyph, or the glyph's
      #   Integer code point.
      #
      # Raises TypeError for a +rasterizer+ that is not one, or a +glyph+
      # that is neither a String nor a number, and RuntimeError with LÖVE's
      # message for a String that is not UTF-8.
      #
      # === Examples
      #
      #   Lota::Font::GlyphData.new(rasterizer, "a")
      #   Lota::Font::GlyphData.new(rasterizer, 97)
      def initialize(rasterizer, glyph)
        unless rasterizer.is_a?(Rasterizer)
          raise TypeError, "wrong argument type #{rasterizer.class} (expected Lota::Font::Rasterizer)"
        end

        @native = case glyph
        when String then Native::Font.new_glyph_data_of_text(rasterizer.native, glyph)
        when Integer, Float then Native::Font.new_glyph_data(rasterizer.native, glyph)
        else raise TypeError, "wrong argument type #{glyph.class} (expected String or Integer)"
        end
      end

      # SPDX-SnippetEnd

      # Makes this GlyphData, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching GlyphData:clone
      # (src/modules/font/wrap_GlyphData.cpp:33-40): a new GlyphData with
      # a copy of the pixels and the same metrics
      # (doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   glyph.clone.advance # => 9
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # The width of its pixels, as an Integer, matching GlyphData:getWidth
      # (src/modules/font/wrap_GlyphData.cpp:42-47).
      #
      # === Example
      #
      #   glyph.width # => 8
      def width
        @native.width
      end

      # The height of its pixels, as an Integer, matching
      # GlyphData:getHeight (src/modules/font/wrap_GlyphData.cpp:49-54).
      #
      # === Example
      #
      #   glyph.height # => 8
      def height
        @native.height
      end

      # The width and height of its pixels, as an Array of two Integers
      # (rule 4 of doc/contributors/design/translation.md), matching
      # GlyphData:getDimensions (src/modules/font/wrap_GlyphData.cpp:56-62).
      #
      # === Example
      #
      #   width, height = glyph.dimensions
      def dimensions
        @native.dimensions
      end

      # The code point of the glyph, as an Integer, matching
      # GlyphData:getGlyph (src/modules/font/wrap_GlyphData.cpp:64-70).
      #
      # A TrueType rasterizer makes each glyph from the font's own index
      # of it, not from a character, so its glyphs answer 0, as they do in
      # LÖVE (src/modules/font/freetype/TrueTypeRasterizer.cpp:155).
      #
      # === Example
      #
      #   glyph.glyph # => 0
      def glyph
        @native.glyph
      end

      # The glyph's character, as a String, matching
      # GlyphData:getGlyphString
      # (src/modules/font/wrap_GlyphData.cpp:72-78): for a glyph whose code
      # point is 0, as #glyph says a TrueType glyph's is, the one character
      # NUL, as in LÖVE.
      #
      # === Example
      #
      #   glyph.glyph_string # => "\u0000"
      def glyph_string
        @native.glyph_string
      end

      # How far the pen moves after drawing the glyph, as an Integer,
      # matching GlyphData:getAdvance
      # (src/modules/font/wrap_GlyphData.cpp:80-85).
      #
      # === Example
      #
      #   glyph.advance # => 9
      def advance
        @native.advance
      end

      # How far its top-left pixel is right of the pen and up from the
      # baseline, as an Array of two Integers (rule 4 of
      # doc/contributors/design/translation.md), matching GlyphData:getBearing
      # (src/modules/font/wrap_GlyphData.cpp:87-93).
      #
      # === Example
      #
      #   x, y = glyph.bearing # => [0, 11]
      def bearing
        @native.bearing
      end

      # The box its outline fits in, as an Array of four Integers, its x,
      # y, width, and height (rule 4 of doc/contributors/design/translation.md),
      # matching GlyphData:getBoundingBox
      # (src/modules/font/wrap_GlyphData.cpp:95-113).
      #
      # === Example
      #
      #   x, y, width, height = glyph.bounding_box
      def bounding_box
        @native.bounding_box
      end

      # The pixel format of its pixels, as a Symbol (rule 9 of
      # doc/contributors/design/translation.md), such as +:la8+ for a TrueType
      # glyph, matching GlyphData:getFormat
      # (src/modules/font/wrap_GlyphData.cpp:115-125).
      #
      # === Example
      #
      #   glyph.format # => :la8
      def format
        @native.format.to_sym
      end
    end
  end
end
