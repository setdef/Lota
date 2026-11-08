# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Font
    # Makes rasterizers from BMFonts, matching love.font.newBMFontRasterizer,
    # named by ADR 001, rule 2.
    #
    # A BMFont is a font drawn ahead of time: a text definition that says
    # where each glyph is in one or more images, its pages. LÖVE has no
    # BMFontRasterizer class that a game can see: a BMFont rasterizer is an
    # ordinary Lota::Font::Rasterizer.
    #
    # LÖVE's C++ makes a BMFont rasterizer of a class of its own, so
    # <tt>BMFontRasterizer === rasterizer</tt> is true only of a BMFont
    # rasterizer, as rule 2 of ADR 001 asks of a module's ===.
    #
    # Use it to rasterize a font made with a BMFont tool.
    #
    # === Example
    #
    #   rasterizer = Lota::Font::BMFontRasterizer.new("assets/hud.fnt", "assets/hud.png")
    module BMFontRasterizer
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Makes a BMFont Lota::Font::Rasterizer, matching
      # love.font.newBMFontRasterizer
      # (src/modules/font/wrap_Font.cpp:158-196).
      #
      # [definition] The BMFont's text definition: a String name of a file
      #   in the game's folder, a Lota::Filesystem::File, or a
      #   Lota::Filesystem::FileData.
      # [images] Its pages, in order: a Lota::Image::ImageData, or a file
      #   name, File, or FileData of an image, or an Array of them. A page
      #   left out is read from the definition's folder.
      # [dpiscale] Float or Integer DPI scale of the images; 1 by default.
      #
      # The images must be 32-bit RGBA. LÖVE's own conversion of the images
      # decides whether to decode each by the kind of the definition rather
      # than by the image's own kind, so it fails for an ImageData after a
      # file name and for a file name after a FileData; Lota decodes each
      # image by its own kind (doc/contributors/upstream/015.md).
      #
      # Raises TypeError for an argument of the wrong type, and
      # RuntimeError with LÖVE's message when a file cannot be read, an
      # image is not 32-bit RGBA, or the definition names a page LÖVE
      # cannot load.
      #
      # === Examples
      #
      #   Lota::Font::BMFontRasterizer.new("assets/hud.fnt")
      #   Lota::Font::BMFontRasterizer.new("assets/hud.fnt", ["hud_0.png", "hud_1.png"], 2)
      def self.new(definition, images = nil, dpiscale = nil)
        Rasterizer.__send__(:from_native, native([definition, images, dpiscale], false))
      end

      # The engine's Rasterizer for +arguments+, the definition, images, and
      # DPI scale. A BMFont has no TrueType settings, so given +settings+,
      # as Lota::Font::Rasterizer.new may be, it raises ArgumentError.
      # :nodoc:
      private_class_method def self.native(arguments, settings)
        raise ArgumentError, "a BMFont takes no hinting, dpiscale:, or sdf: settings" if settings
        raise ArgumentError, "wrong number of arguments (given #{arguments.size}, expected 1..3)" if arguments.size > 3

        definition, images, dpiscale = arguments
        data = Font.__send__(:file_data, definition)
        dpiscale = Font.__send__(:optional_number, dpiscale, "dpiscale")
        pages = images.is_a?(Array) ? images : [images].compact
        Native::Font.new_bmfont_rasterizer(data, pages.map { |image| Font.__send__(:image_data, image) }, dpiscale)
      end

      # SPDX-SnippetEnd

      # Whether +object+ is a BMFont Lota::Font::Rasterizer, as
      # BMFontRasterizer.new makes, by the C++ class LÖVE made it of.
      #
      # === Example
      #
      #   Lota::Font::BMFontRasterizer === Lota::Font::Rasterizer.new("assets/hud.fnt") # => true
      def self.===(object)
        object.is_a?(Rasterizer) && object.__send__(:native).bmfont?
      end
    end
  end
end
