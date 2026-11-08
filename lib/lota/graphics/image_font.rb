# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes fonts from a picture of their glyphs, matching
    # love.graphics.newImageFont, named by ADR 001, rule 2.
    #
    # LÖVE has no ImageFont class: an image font is an ordinary
    # Lota::Graphics::Font, whose glyphs come from one image. The image
    # holds the glyphs side by side in a row, each separated from the next
    # by a column of pixels in the color of the image's top-left pixel.
    # That keeps pixel-art lettering exactly as drawn.
    #
    # The engine cannot tell an image font from another font, so
    # <tt>ImageFont === font</tt> is true of every Font, as
    # <tt>Image === texture</tt> is of every Texture (ADR 001, rule 2).
    #
    # Use it to draw text in a font drawn as pixel art.
    #
    # === Example
    #
    #   font = Lota::Graphics::ImageFont.new("hud_font.png", " abcdefghijklmnopqrstuvwxyz0123456789")
    #   Lota::Graphics.font = font
    module ImageFont
      # Makes a Lota::Graphics::Font from the image of its glyphs,
      # matching love.graphics.newImageFont
      # (src/modules/graphics/wrap_Graphics.cpp, w_newImageFont), which
      # makes its glyphs with love.font.newImageRasterizer
      # (src/modules/font/wrap_Font.cpp, w_newImageRasterizer).
      #
      # [image] String name of an image file in the game's folder, a
      #   Lota::Filesystem::FileData holding an image file, or a
      #   Lota::Image::ImageData; or a Lota::Font::Rasterizer, such as
      #   Lota::Font::ImageRasterizer.new makes, whose glyphs the font
      #   draws, in which case the other arguments are ignored, as LÖVE
      #   ignores them.
      # [glyphs] String of the characters in the image, in the order they
      #   are drawn in it.
      # [extraspacing] Integer pixels added between glyphs; 0 by default.
      # [dpiscale] Float or Integer DPI scale of the image; 1 by default.
      #
      # Raises TypeError for an image or number of the wrong type,
      # RuntimeError with LÖVE's message when the image cannot be read,
      # the glyphs do not match the image, the window is not open, or the
      # image module is not, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::ImageFont.new("font.png", " ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      #   Lota::Graphics::ImageFont.new(image_data, "ABCD", 1)
      def self.new(image, glyphs = nil, extraspacing = nil, dpiscale = nil)
        return Font.from_native(Native::Graphics.new_font_of_rasterizer(image.native)) if image.is_a?(Lota::Font::Rasterizer)

        raise TypeError, "wrong argument type #{glyphs.class} (expected String)" unless glyphs.is_a?(String)

        extraspacing = case extraspacing
        when Integer, nil then extraspacing
        else raise TypeError, "wrong argument type #{extraspacing.class} (expected Integer)"
        end
        dpiscale = case dpiscale
        when Float, Integer, nil then dpiscale
        else raise TypeError, "wrong argument type #{dpiscale.class} (expected Float)"
        end
        data = Font.image_data(image)
        Font.from_native(Native::Graphics.new_image_font(data.native, glyphs, extraspacing, dpiscale))
      end

      # Whether +object+ is a Lota::Graphics::Font, which every font
      # ImageFont.new makes is. The engine cannot tell an image font from
      # another, so this is true of every Font.
      #
      # === Example
      #
      #   Lota::Graphics::ImageFont === Lota::Graphics::Font.new # => true
      def self.===(object)
        object.is_a?(Font)
      end
    end
  end
end
