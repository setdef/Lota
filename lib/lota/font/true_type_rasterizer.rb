# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Font
    # Makes rasterizers from TrueType and OpenType fonts, matching
    # love.font.newTrueTypeRasterizer, named by ADR 001, rule 2.
    #
    # LÖVE has no TrueTypeRasterizer class that a game can see: a TrueType
    # rasterizer is an ordinary Lota::Font::Rasterizer, which draws its
    # glyphs from the outlines in a font file at the size you ask for.
    # Without a file it uses LÖVE's default font, Noto Sans.
    #
    # LÖVE's C++ makes a TrueType rasterizer of a class of its own, so
    # <tt>TrueTypeRasterizer === rasterizer</tt> is true only of a TrueType
    # rasterizer, as rule 2 of ADR 001 asks of a module's ===.
    #
    # Use it to rasterize a font file, or LÖVE's default font, at a size
    # of your choosing.
    #
    # === Example
    #
    #   rasterizer = Lota::Font::TrueTypeRasterizer.new("assets/pixel.ttf", 16, hinting: :mono)
    module TrueTypeRasterizer
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Makes a TrueType Lota::Font::Rasterizer, matching
      # love.font.newTrueTypeRasterizer
      # (src/modules/font/wrap_Font.cpp:106-149), in one of two forms:
      #
      # - <tt>TrueTypeRasterizer.new(size = 13, hinting = nil, dpiscale =
      #   nil)</tt>: LÖVE's default font, Noto Sans, +size+ pixels tall.
      # - <tt>TrueTypeRasterizer.new(font, size = 12, hinting = nil,
      #   dpiscale = nil)</tt>: the font in +font+, a String name of a
      #   file in the game's folder, a Lota::Filesystem::File, or any
      #   Lota::Data, such as a Lota::Filesystem::FileData.
      #
      # [size] Integer height in pixels.
      # [hinting] +:normal+ (the default), +:light+, +:mono+, or +:none+:
      #   how far glyph outlines bend to fit the pixel grid.
      # [dpiscale] Float or Integer DPI scale the glyphs are rasterized at;
      #   the window's by default, or 1 without one.
      # [sdf] Whether the glyphs are signed distance fields, for shaders
      #   that draw sharp text at any size; +false+ by default. It can be
      #   given only as a keyword.
      #
      # The hinting and DPI scale come either after the size, as in LÖVE's
      # older form, or as keywords, which translate the table of settings
      # LÖVE 12 also takes (ADR 001, rule 10). After the size, LÖVE reads
      # the DPI scale only after a hinting mode, and so does Lota.
      #
      # Raises ArgumentError for an unknown hinting mode, settings given
      # both ways, or too many arguments, TypeError for an argument of the
      # wrong type, and RuntimeError with LÖVE's message when the file
      # cannot be read or holds no font FreeType reads.
      #
      # === Examples
      #
      #   Lota::Font::TrueTypeRasterizer.new                # Noto Sans at 13 pixels
      #   Lota::Font::TrueTypeRasterizer.new(12, :normal, 1)
      #   Lota::Font::TrueTypeRasterizer.new("assets/pixel.ttf", 8, :normal, 1)
      #   Lota::Font::TrueTypeRasterizer.new(32, sdf: true)
      def self.new(*arguments, hinting: nil, dpiscale: nil, sdf: false)
        Rasterizer.from_native(native(arguments, hinting, dpiscale, sdf))
      end

      # The engine's Rasterizer for +arguments+ and the settings, made as
      # w_newTrueTypeRasterizer chooses: LÖVE's default font when the
      # first is a number or there is none, and the font in the first
      # otherwise. :nodoc:
      def self.native(arguments, hinting, dpiscale, sdf)
        source = arguments.first unless arguments.empty? || arguments.first.is_a?(Numeric)
        rest = source.nil? ? arguments : arguments.drop(1)
        size, *legacy = rest
        if legacy.size > 2
          raise ArgumentError,
            "wrong number of arguments (given #{arguments.size}, expected #{source.nil? ? '0..3' : '1..4'})"
        end

        size = Font.optional_integer(size, "size")
        hinting, dpiscale = settings(legacy, hinting, dpiscale, sdf)
        return Native::Font.new_default_truetype_rasterizer(size, hinting, dpiscale, sdf) if source.nil?

        data = source.is_a?(Data) ? source.native : Font.file_data(source)
        Native::Font.new_truetype_rasterizer(data, size, hinting, dpiscale, sdf)
      end

      # The hinting mode's name and the DPI scale, from the hinting mode
      # and DPI scale +legacy+ holds after the size, or else from the
      # keywords, as luax_checktruetypesettings reads a string or a table
      # (src/modules/font/wrap_Font.cpp:67-104).
      private_class_method def self.settings(legacy, hinting, dpiscale, sdf)
        legacy_hinting, legacy_dpiscale = legacy
        case legacy_hinting
        when nil
          [name_of(hinting), Font.optional_number(dpiscale, "dpiscale")]
        when Symbol, String
          unless hinting.nil? && dpiscale.nil? && !sdf
            raise ArgumentError, "give the hinting and DPI scale after the size or as keywords, not both"
          end

          [EnumName.of(legacy_hinting), Font.optional_number(legacy_dpiscale, "dpiscale")]
        else raise TypeError, "wrong argument type #{legacy_hinting.class} for hinting (expected Symbol)"
        end
      end

      # The hinting mode's name, or +nil+ for LÖVE's default.
      private_class_method def self.name_of(hinting)
        case hinting
        when Symbol, String then EnumName.of(hinting)
        when nil then nil
        else raise TypeError, "wrong argument type #{hinting.class} for hinting (expected Symbol)"
        end
      end

      # SPDX-SnippetEnd

      # Whether +object+ is a TrueType Lota::Font::Rasterizer, as
      # TrueTypeRasterizer.new makes, by the C++ class LÖVE made it of.
      #
      # === Example
      #
      #   Lota::Font::TrueTypeRasterizer === Lota::Font::Rasterizer.new(12) # => true
      def self.===(object)
        object.is_a?(Rasterizer) && object.native.truetype?
      end
    end
  end
end
