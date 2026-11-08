# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Font
    # Makes rasterizers from a picture of their glyphs, matching
    # love.font.newImageRasterizer, named by ADR 001, rule 2.
    #
    # The image holds the glyphs side by side in a row, each separated
    # from the next by a column of pixels in the color of the image's
    # top-left pixel, as Lota::Graphics::ImageFont reads it. LÖVE has no
    # ImageRasterizer class that a game can see: an image rasterizer is an
    # ordinary Lota::Font::Rasterizer.
    #
    # LÖVE's C++ makes an image rasterizer of a class of its own, so
    # <tt>ImageRasterizer === rasterizer</tt> is true only of an image
    # rasterizer, as rule 2 of ADR 001 asks of a module's ===.
    #
    # Use it to rasterize a font drawn as pixel art.
    #
    # === Example
    #
    #   rasterizer = Lota::Font::ImageRasterizer.new("assets/font.png", " ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    module ImageRasterizer
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Makes an image Lota::Font::Rasterizer, matching
      # love.font.newImageRasterizer
      # (src/modules/font/wrap_Font.cpp:198-215).
      #
      # [image] A Lota::Image::ImageData, or a String name of an image file
      #   in the game's folder, a Lota::Filesystem::File, or a
      #   Lota::Filesystem::FileData holding one.
      # [glyphs] String of the characters in the image, in the order they
      #   are drawn in it.
      # [extraspacing] Integer pixels added between glyphs; 0 by default.
      # [dpiscale] Float or Integer DPI scale of the image; 1 by default.
      #
      # Raises TypeError for an argument of the wrong type, and
      # RuntimeError with LÖVE's message when the image cannot be read,
      # the glyphs are not UTF-8, or the image module is not open.
      #
      # === Examples
      #
      #   Lota::Font::ImageRasterizer.new("font.png", " ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      #   Lota::Font::ImageRasterizer.new(image_data, "ABC", 0, 1)
      def self.new(image, glyphs, extraspacing = nil, dpiscale = nil)
        data = Font.image_data(image)
        raise TypeError, "wrong argument type #{glyphs.class} for glyphs (expected String)" unless glyphs.is_a?(String)

        extraspacing = Font.optional_integer(extraspacing, "extraspacing")
        dpiscale = Font.optional_number(dpiscale, "dpiscale")
        Rasterizer.from_native(Native::Font.new_image_rasterizer(data, glyphs, extraspacing, dpiscale))
      end

      # SPDX-SnippetEnd

      # Whether +object+ is an image Lota::Font::Rasterizer, as
      # ImageRasterizer.new makes, by the C++ class LÖVE made it of.
      #
      # === Example
      #
      #   Lota::Font::ImageRasterizer === Lota::Font::ImageRasterizer.new("font.png", "AB") # => true
      def self.===(object)
        object.is_a?(Rasterizer) && object.native.image?
      end
    end
  end
end
