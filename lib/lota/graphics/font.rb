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
    end
  end
end
