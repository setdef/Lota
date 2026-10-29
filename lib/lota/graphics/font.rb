# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A typeface at one size, ready to draw text with, matching LÖVE's
    # Font class (src/modules/graphics/Font.h).
    #
    # Drawing text means turning each character into a picture of it, a
    # glyph, and putting the glyphs side by side. Doing that from the font
    # file for every frame would be slow, so a Font rasterizes each glyph
    # once, the first time it is drawn, and keeps it on the graphics card.
    #
    # Lota::Graphics draws text in LÖVE's default font, Noto Sans at 13
    # pixels, until you choose another with Lota::Graphics.font=.
    #
    # Use it to draw text in a typeface or size of your own.
    #
    # === Examples
    #
    #   big = Lota::Graphics::Font.new(32)
    #   Lota::Graphics.font = big
    #   Lota::Graphics.print("Game Over", 300, 250)
    #
    #   data = Lota::Filesystem::FileData.new(File.binread("pixel.ttf"), "pixel.ttf")
    #   Lota::Graphics.font = Lota::Graphics::Font.new(data, 8, :mono)
    class Font
      include Object

      # The engine's Font, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Font the engine made, such as the default font
      # Lota::Graphics.font returns. :nodoc:
      def self.from_native(native)
        font = allocate
        font.instance_variable_set(:@native, native)
        font
      end

      # Makes a font, matching love.graphics.newFont
      # (src/modules/graphics/wrap_Graphics.cpp, w_newFont), which makes
      # its glyphs with love.font.newRasterizer
      # (src/modules/font/wrap_Font.cpp, w_newRasterizer and
      # w_newTrueTypeRasterizer).
      #
      # [data] String name of a font file in the game's folder, or a
      #   Lota::Filesystem::FileData, holding a TrueType or OpenType font,
      #   or a BMFont definition when +size+ is left out; leave it out for
      #   LÖVE's default font.
      # [size] Integer height in pixels: 13 by default for LÖVE's default
      #   font, and 12 for a TrueType font in +data+.
      # [hinting] +:normal+ (the default), +:light+, +:mono+, or +:none+:
      #   how far glyph outlines bend to fit the pixel grid.
      # [dpiscale] Float or Integer DPI scale the glyphs are rasterized at;
      #   the screen's by default.
      # [sdf] Whether the glyphs are signed distance fields, for shaders
      #   that draw sharp text at any size; +false+ by default. Like the
      #   rest of the settings, it can be given only as a keyword.
      #
      # The hinting and DPI scale come either after the size, as in LÖVE's
      # older form, or as keywords, which translate the table of settings
      # LÖVE 12 also takes (ADR 001, rule 10). Given +data+ and no size,
      # LÖVE reads the font at its own default size and ignores the
      # settings, and so does Lota. A file name is a path in the game's
      # folder, as LÖVE's filesystem reads it (Lota::Boot makes the folder
      # its source, as boot.lua does), with forward slashes and no "..".
      # LÖVE also reads a BMFont with its images; Lota binds that form
      # later.
      #
      # Raises ArgumentError for an unknown hinting mode or for settings
      # given both ways, RuntimeError with LÖVE's message when the file
      # cannot be read, the data holds no font, the window is not open, or
      # the filesystem is not, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::Font.new                    # Noto Sans at 13 pixels
      #   Lota::Graphics::Font.new(24)                # Noto Sans at 24 pixels
      #   Lota::Graphics::Font.new(data, 8, :normal)  # the font in data, at 8 pixels
      #   Lota::Graphics::Font.new("assets/pixel.ttf", 16) # a font file in the game's folder
      #   Lota::Graphics::Font.new(data, 8, hinting: :mono, dpiscale: 1)
      def initialize(*arguments, hinting: nil, dpiscale: nil, sdf: false)
        first = arguments.first
        data = first if first.is_a?(Filesystem::FileData) || first.is_a?(String)
        size, legacy_hinting, legacy_dpiscale = data ? arguments.drop(1) : arguments
        unless legacy_hinting.nil? && legacy_dpiscale.nil?
          if hinting || dpiscale
            raise ArgumentError, "give the hinting and DPI scale after the size or as keywords, not both"
          end

          hinting = legacy_hinting
          dpiscale = legacy_dpiscale
        end
        @native = native_font(data, size, hinting, dpiscale, sdf)
      end

      # The engine's Font, made as w_newRasterizer chooses: LÖVE's default
      # font without data, the font in +data+ at LÖVE's default size
      # without a size, and a TrueType font otherwise. A file name is read
      # as luax_getfiledata reads one (wrap_Filesystem.cpp:308-379).
      private def native_font(data, size, hinting, dpiscale, sdf)
        size = case size
        when Integer, nil then size
        else raise TypeError, "wrong argument type #{size.class} for size (expected Integer)"
        end
        hinting = case hinting
        when Symbol, String, nil then hinting&.to_s
        else raise TypeError, "wrong argument type #{hinting.class} for hinting (expected Symbol)"
        end
        dpiscale = case dpiscale
        when Float, Integer, nil then dpiscale
        else raise TypeError, "wrong argument type #{dpiscale.class} for dpiscale (expected Float)"
        end
        return Native::Graphics.new_default_font(size, hinting, dpiscale, sdf) if data.nil?

        native = data.is_a?(String) ? Native::Filesystem.file_data(data) : data.native
        if size.nil?
          Native::Graphics.new_font_from_file(native)
        else
          Native::Graphics.new_truetype_font(native, size, hinting, dpiscale, sdf)
        end
      end

      # The height of a line of text, without the line height's spacing,
      # matching Font:getHeight (src/modules/graphics/wrap_Font.cpp,
      # w_Font_getHeight).
      #
      # === Example
      #
      #   Lota::Graphics::Font.new(16).height # => 19.0
      def height
        @native.height
      end

      # The width of +text+'s widest line, or of one glyph given by its
      # Integer code point, matching Font:getWidth
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getWidth).
      #
      # Raises RuntimeError for text that is not valid UTF-8, as LÖVE does,
      # and TypeError for anything but a String or a number.
      #
      # === Example
      #
      #   font.width("Score: 100")
      def width(text)
        case text
        when String then @native.text_width(text)
        when Integer, Float then @native.glyph_width(text)
        else raise TypeError, "wrong argument type #{text.class} (expected String or Integer)"
        end
      end

      # The width of the widest line and the lines of +text+ wrapped at
      # +wraplimit+, as an Array (ADR 001, rule 4), matching Font:getWrap
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getWrap).
      #
      # [text] A String, or colored text as Lota::Graphics.print takes it.
      # [wraplimit] The width a line may take before it wraps.
      #
      # === Example
      #
      #   width, lines = font.wrap("A long line of text", 50)
      def wrap(text, wraplimit)
        @native.wrap(Graphics.colored_text(text), wraplimit)
      end

      # Sets the line height, a factor of #height between the tops of
      # lines, matching Font:setLineHeight
      # (src/modules/graphics/wrap_Font.cpp, w_Font_setLineHeight).
      #
      # === Example
      #
      #   font.line_height = 1.5
      def line_height=(height)
        @native.set_line_height(height)
      end

      # The line height, 1.0 until set, matching Font:getLineHeight
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getLineHeight).
      #
      # === Example
      #
      #   font.line_height # => 1.0
      def line_height
        @native.line_height
      end

      # Sets how the font's glyphs are filtered when scaled, matching
      # Font:setFilter (src/modules/graphics/wrap_Font.cpp,
      # w_Font_setFilter), as Lota::Graphics.default_filter= takes it: the
      # filter when scaled down, as a Symbol, or an Array of it, the filter
      # when scaled up (the first by default), and the Integer anisotropy
      # (1 by default).
      #
      # Raises ArgumentError for a filter other than +:linear+ or
      # +:nearest+.
      #
      # === Example
      #
      #   font.filter = :nearest
      #   font.filter = :linear, :nearest, 4
      def filter=(filter)
        min, mag, anisotropy = filter.is_a?(Array) ? filter : [filter]
        anisotropy = case anisotropy
        when Integer, Float then anisotropy
        when nil then 1
        else raise TypeError, "wrong argument type #{anisotropy.class} for anisotropy (expected Integer)"
        end
        @native.set_filter(EnumName.of(min), mag && EnumName.of(mag), anisotropy)
      end

      # The filters when scaled down and up, as Symbols, and the Integer
      # anisotropy, as an Array (ADR 001, rule 4), matching Font:getFilter
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getFilter).
      #
      # === Example
      #
      #   font.filter # => [:linear, :linear, 1]
      def filter
        min, mag, anisotropy = @native.filter
        [min.to_sym, mag.to_sym, anisotropy]
      end

      # The Integer height above the baseline of the tallest glyph,
      # matching Font:getAscent (src/modules/graphics/wrap_Font.cpp,
      # w_Font_getAscent).
      #
      # === Example
      #
      #   font.ascent # => 6
      def ascent
        @native.ascent
      end

      # The Integer depth below the baseline of the deepest glyph, a
      # negative number, matching Font:getDescent
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getDescent).
      #
      # === Example
      #
      #   font.descent # => -2
      def descent
        @native.descent
      end

      # Where the baseline is, from the top of a line, matching
      # Font:getBaseline (src/modules/graphics/wrap_Font.cpp,
      # w_Font_getBaseline).
      #
      # === Example
      #
      #   font.baseline # => 6.0
      def baseline
        @native.baseline
      end

      # Whether the font has every glyph of each String, and the glyph of
      # each Integer code point, matching Font:hasGlyphs
      # (src/modules/graphics/wrap_Font.cpp, w_Font_hasGlyphs), which stops
      # at the first it lacks.
      #
      # Raises ArgumentError given nothing, and TypeError for anything but a
      # String or a number.
      #
      # === Example
      #
      #   font.glyphs?("Score", 0x2665)
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

      # The kerning between two characters, given as Strings, or two
      # glyphs, given as Integer code points, matching Font:getKerning
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getKerning).
      #
      # Raises TypeError for a String and a number together.
      #
      # === Example
      #
      #   font.kerning("A", "V")
      def kerning(left, right)
        return @native.text_kerning(left, right) if left.is_a?(String) && right.is_a?(String)
        return @native.glyph_kerning(left, right) if !left.is_a?(String) && !right.is_a?(String)

        raise TypeError, "wrong argument types #{left.class} and #{right.class} (expected two Strings or two Integers)"
      end

      # Sets the fonts whose glyphs stand in, in order, for those this one
      # lacks, matching Font:setFallbacks
      # (src/modules/graphics/wrap_Font.cpp, w_Font_setFallbacks), which
      # takes them as an Array (ADR 001, rule 6). An empty Array clears
      # them. LÖVE has no getter for them.
      #
      # Raises TypeError for anything but a Font.
      #
      # === Example
      #
      #   font.fallbacks = emoji_font, symbol_font
      def fallbacks=(fonts)
        natives = Array(fonts).map do |font|
          raise TypeError, "wrong argument type #{font.class} (expected Lota::Graphics::Font)" unless font.is_a?(Font)

          font.native
        end
        @native.set_fallbacks(natives)
      end

      # The DPI scale the font was made at, matching Font:getDPIScale
      # (src/modules/graphics/wrap_Font.cpp, w_Font_getDPIScale), named by
      # ADR 001, rule 13.
      #
      # === Example
      #
      #   font.dpi_scale # => 1.0
      def dpi_scale
        @native.dpi_scale
      end
    end
  end
end
