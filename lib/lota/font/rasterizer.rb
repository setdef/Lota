# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Font
    # A typeface at one size that turns characters into glyphs, matching
    # LÖVE's Rasterizer class (src/modules/font/Rasterizer.h).
    #
    # A Lota::Graphics::Font draws text, but it is a Rasterizer that knows
    # what each glyph looks like: how wide, how far above and below the
    # baseline, and which pixels it covers. The Rasterizer reads that from
    # a TrueType font, the images of a BMFont, or an image font, and makes
    # each glyph's GlyphData when asked.
    #
    # Lota::Graphics::Font.new takes a Rasterizer, so one made here can
    # draw.
    #
    # Use it to measure glyphs, or read their pixels, without a window.
    #
    # === Examples
    #
    #   rasterizer = Lota::Font::Rasterizer.new("assets/pixel.ttf", 8)
    #   rasterizer.glyphs?("Score") # => true
    #   rasterizer.line_height
    #
    #   Lota::Graphics.font = Lota::Graphics::Font.new(rasterizer)
    class Rasterizer
      include Object

      # The engine's Rasterizer, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Rasterizer the engine made. :nodoc:
      def self.from_native(native)
        rasterizer = allocate
        rasterizer.instance_variable_set(:@native, native)
        rasterizer
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Makes a rasterizer, matching love.font.newRasterizer
      # (src/modules/font/wrap_Font.cpp:38-65), which chooses its kind by
      # its arguments, as Lota does:
      #
      # - Nothing, or a number first or second: a TrueType rasterizer, as
      #   TrueTypeRasterizer.new makes with the same arguments, including
      #   the +hinting+, +dpiscale+, and +sdf+ keywords.
      # - One font file alone: a TrueType rasterizer at 12 pixels, or a
      #   BMFont rasterizer, as the file holds. The keywords are ignored,
      #   as LÖVE ignores settings it is not given a size for.
      # - A file and anything but a number: a BMFont rasterizer, as
      #   BMFontRasterizer.new makes with the same arguments.
      #
      # A font file is a String name of a file in the game's folder, a
      # Lota::Filesystem::File, or a Lota::Filesystem::FileData.
      #
      # Raises RuntimeError with LÖVE's message for a file that holds no
      # font LÖVE reads ("Invalid font file: ..."), and what
      # TrueTypeRasterizer.new and BMFontRasterizer.new raise.
      #
      # === Examples
      #
      #   Lota::Font::Rasterizer.new                       # Noto Sans at 13 pixels
      #   Lota::Font::Rasterizer.new("assets/pixel.ttf")   # at 12 pixels
      #   Lota::Font::Rasterizer.new("assets/pixel.ttf", 8, :mono)
      #   Lota::Font::Rasterizer.new("assets/hud.fnt", "assets/hud.png")
      def initialize(*arguments, hinting: nil, dpiscale: nil, sdf: false)
        first, second = arguments
        @native = if arguments.empty? || first.is_a?(Numeric) || second.is_a?(Numeric)
          TrueTypeRasterizer.native(arguments, hinting, dpiscale, sdf)
        elsif second.nil?
          Native::Font.new_rasterizer(Font.file_data(first))
        else
          BMFontRasterizer.native(arguments, !hinting.nil? || !dpiscale.nil? || sdf)
        end
      end

      # SPDX-SnippetEnd

      # The height of its tallest glyph, as an Integer, matching
      # Rasterizer:getHeight (src/modules/font/wrap_Rasterizer.cpp:35-40).
      #
      # === Example
      #
      #   rasterizer.height # => 12
      def height
        @native.height
      end

      # The advance of its widest glyph, as an Integer, matching
      # Rasterizer:getAdvance (src/modules/font/wrap_Rasterizer.cpp:42-47):
      # how far the pen moves after drawing it.
      #
      # === Example
      #
      #   rasterizer.advance # => 9
      def advance
        @native.advance
      end

      # How far its glyphs reach above the baseline, as an Integer,
      # matching Rasterizer:getAscent
      # (src/modules/font/wrap_Rasterizer.cpp:49-54).
      #
      # === Example
      #
      #   rasterizer.ascent # => 9
      def ascent
        @native.ascent
      end

      # How far its glyphs reach below the baseline, as a negative Integer,
      # matching Rasterizer:getDescent
      # (src/modules/font/wrap_Rasterizer.cpp:56-61).
      #
      # === Example
      #
      #   rasterizer.descent # => -3
      def descent
        @native.descent
      end

      # The distance from one line of text to the next, as an Integer,
      # matching Rasterizer:getLineHeight
      # (src/modules/font/wrap_Rasterizer.cpp:63-68).
      #
      # === Example
      #
      #   rasterizer.line_height # => 15
      def line_height
        @native.line_height
      end

      # The glyph of +glyph+, matching Rasterizer:getGlyphData
      # (src/modules/font/wrap_Rasterizer.cpp:70-92).
      #
      # [glyph] String whose first character is the glyph, or the glyph's
      #   Integer code point.
      #
      # Returns a Lota::Font::GlyphData. Raises RuntimeError with LÖVE's
      # message for a String that is not UTF-8, and TypeError for anything
      # but a String or a number.
      #
      # === Example
      #
      #   rasterizer.glyph_data("a").advance # => 9
      def glyph_data(glyph)
        GlyphData.from_native(
          case glyph
          when String then @native.glyph_data_of_text(glyph)
          when Integer, Float then @native.glyph_data(glyph)
          else raise TypeError, "wrong argument type #{glyph.class} (expected String or Integer)"
          end
        )
      end

      # How many glyphs it has, as an Integer, matching
      # Rasterizer:getGlyphCount
      # (src/modules/font/wrap_Rasterizer.cpp:94-99).
      #
      # === Example
      #
      #   rasterizer.glyph_count # => 77
      def glyph_count
        @native.glyph_count
      end

      # Whether it has every glyph of each String, and the glyph of each
      # Integer code point, matching Rasterizer:hasGlyphs
      # (src/modules/font/wrap_Rasterizer.cpp:101-125), which stops at the
      # first it lacks.
      #
      # Raises ArgumentError given nothing, RuntimeError with LÖVE's message
      # for a String that is not UTF-8, and TypeError for anything but a
      # String or a number.
      #
      # === Example
      #
      #   rasterizer.glyphs?("L", "O", "V", "E") # => true
      def glyphs?(*glyphs)
        raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if glyphs.empty?

        glyphs.all? do |glyph|
          case glyph
          when String then @native.text_glyphs?(glyph)
          when Integer, Float then @native.glyph?(glyph)
          else raise TypeError, "wrong argument type #{glyph.class} (expected String or Integer)"
          end
        end
      end
    end
  end
end
