# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # LÖVE's font module, translated from love.font.
  #
  # Before a font can draw, its glyphs have to be rasterized: turned from
  # the outlines in a TrueType file, or the pictures in an image font, into
  # pixels. LÖVE's font module does that work, and its graphics module
  # draws with what it makes.
  #
  # Lota opens it, unless <tt>t.modules.font = false</tt>, before the
  # window, as boot.lua opens love.font, and Lota::Graphics::Font.new
  # rasterizes every font through it, as LÖVE's newFont does.
  #
  # Its own classes are a Rasterizer, which holds a typeface at one size
  # and makes its glyphs, and GlyphData, the pixels and metrics of one
  # glyph. Lota::Font::Rasterizer.new makes a rasterizer as
  # love.font.newRasterizer does, and the modules TrueTypeRasterizer,
  # BMFontRasterizer, and ImageRasterizer make one of each kind, as LÖVE's
  # newTrueTypeRasterizer, newBMFontRasterizer, and newImageRasterizer do
  # (rule 25 of doc/contributors/design/translation.md). This module is love.font
  # and Lota::Graphics::Font is love.graphics' Font, as rule 1 names them, so
  # inside <tt>module Lota</tt> a bare +Font+ means this module.
  #
  # Use <tt>lota.font</tt> to ask whether the module is open, as a LÖVE
  # game asks <tt>if love.font then</tt>; draw text with
  # Lota::Graphics::Font, which can also be made from a Rasterizer.
  #
  # === Examples
  #
  #   lota.font # => Lota::Font, or nil when the settings turn it off
  #
  #   rasterizer = Lota::Font::Rasterizer.new("assets/pixel.ttf", 8)
  #   rasterizer.glyph_data("a").advance
  module Font
    # The ImageData of +image+, which LÖVE converts as convimagedata does
    # (src/modules/font/wrap_Font.cpp:152-156), through
    # love.image.newImageData: a file name, a Lota::Filesystem::File, or a
    # Lota::Filesystem::FileData is decoded, and an ImageData is used as
    # it is. :nodoc:
    private_class_method def self.image_data(image)
      case image
      when Image::ImageData then image.__send__(:native)
      when String, Filesystem::File, Filesystem::FileData then Image::ImageData.new(image).__send__(:native)
      else raise TypeError, "wrong argument type #{image.class} (expected Lota::Image::ImageData)"
      end
    end

    # A number LÖVE reads with luaL_optnumber, for +name+, or +nil+ to
    # leave it to LÖVE's default. :nodoc:
    private_class_method def self.optional_number(value, name)
      case value
      when Float, Integer, nil then value
      else raise TypeError, "wrong argument type #{value.class} for #{name} (expected Float)"
      end
    end

    # An integer LÖVE reads with luaL_optinteger, which LuaJIT cuts to the
    # whole number toward 0, for +name+, or +nil+ to leave it to LÖVE's
    # default. :nodoc:
    private_class_method def self.optional_integer(value, name)
      case value
      when Integer, nil then value
      when Float then value.truncate
      else raise TypeError, "wrong argument type #{value.class} for #{name} (expected Integer)"
      end
    end
  end
end

require_relative "font/rasterizer"
require_relative "font/glyph_data"
require_relative "font/true_type_rasterizer"
require_relative "font/bm_font_rasterizer"
require_relative "font/image_rasterizer"
