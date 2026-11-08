# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Font's rasterizers and glyph data, beyond what Lövetest's tests for
# them check (test/lovetest/tests/font.rb): the forms love.font's wrap
# functions choose among, the settings they read, and the errors they
# raise (vendor/love/src/modules/font/wrap_Font.cpp, wrap_Rasterizer.cpp,
# and wrap_GlyphData.cpp). The class is FontModuleFunctionsTest, since
# FontTest is Lota::Graphics::Font's.
class FontModuleFunctionsTest < Minitest::Test
  Rasterizer = Lota::Font::Rasterizer
  TrueTypeRasterizer = Lota::Font::TrueTypeRasterizer
  BMFontRasterizer = Lota::Font::BMFontRasterizer
  ImageRasterizer = Lota::Font::ImageRasterizer
  GlyphData = Lota::Font::GlyphData
  RESOURCES = File.expand_path("../lovetest/resources", __dir__)

  # A BMFont of one glyph, A, on the page font-letters-ab.png.
  BMFONT = <<~FNT
    info face="test" size=10 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0
    common lineHeight=10 base=8 scaleW=18 scaleH=10 pages=1 packed=0
    page id=0 file="font-letters-ab.png"
    chars count=1
    char id=65 x=0 y=0 width=8 height=10 xoffset=0 yoffset=0 xadvance=9 page=0 chnl=15
  FNT

  def setup
    EngineHelper.open_window
  end

  def file_data(name, contents = File.binread(File.join(RESOURCES, name)))
    Lota::Filesystem::FileData.new(contents, name)
  end

  def font_data
    file_data("font.ttf")
  end

  # The BMFont's definition, named in the folder that holds its page, so
  # that a page left out is read from there.
  def bmfont_definition
    file_data("resources/font.fnt", BMFONT)
  end

  # w_newRasterizer chooses w_newTrueTypeRasterizer given nothing or a
  # number first or second, Font::newRasterizer given a file alone, and
  # w_newBMFontRasterizer otherwise (wrap_Font.cpp:38-65).
  def test_a_rasterizer_is_made_as_new_rasterizer_chooses
    assert_equal TrueTypeRasterizer.new(13).height, Rasterizer.new.height
    refute_equal TrueTypeRasterizer.new(30).height, Rasterizer.new.height
    assert_equal TrueTypeRasterizer.new(30).height, Rasterizer.new(30).height
    assert_equal TrueTypeRasterizer.new(font_data, 12).line_height, Rasterizer.new(font_data).line_height
    assert_equal TrueTypeRasterizer.new(font_data, 20).line_height, Rasterizer.new(font_data, 20).line_height
    refute_equal Rasterizer.new(font_data).line_height, Rasterizer.new(font_data, 20).line_height
    assert_equal 15, Rasterizer.new("resources/font.ttf").line_height

    bmfont = Rasterizer.new(bmfont_definition, Lota::Image::ImageData.new("resources/font-letters-ab.png"))
    assert_equal [10, 2], [bmfont.line_height, bmfont.glyph_count]
    assert_equal 10, Rasterizer.new(bmfont_definition).line_height
  end

  # Font::newRasterizer reads a TrueType font or a BMFont, and nothing else
  # (font/freetype/Font.cpp:49-57).
  def test_a_file_that_holds_no_font_raises_loves_error
    error = assert_raises(RuntimeError) { Rasterizer.new(file_data("junk.txt", "not a font")) }

    assert_equal "Invalid font file: junk.txt", error.message
    assert_raises(TypeError) { Rasterizer.new(:font) }
    assert_raises(ArgumentError) { Rasterizer.new(bmfont_definition, "resources/font-letters-ab.png", hinting: :mono) }
  end

  # luax_checktruetypesettings reads a hinting mode and a DPI scale after
  # the size, or a table of settings, which become keywords (rule 10).
  def test_the_settings_come_after_the_size_or_as_keywords
    one = TrueTypeRasterizer.new(12, :normal, 1).glyph_data("A")
    three = TrueTypeRasterizer.new(12, :normal, 3).glyph_data("A")

    assert_operator three.width, :>, one.width
    assert_equal three.dimensions, TrueTypeRasterizer.new(12, dpiscale: 3).glyph_data("A").dimensions
    assert_equal TrueTypeRasterizer.new(font_data, 12, "normal", 3).glyph_data("A").dimensions,
      TrueTypeRasterizer.new(font_data, 12, dpiscale: 3).glyph_data("A").dimensions
    refute_equal TrueTypeRasterizer.new(font_data, 12).glyph_data("A").dimensions,
      TrueTypeRasterizer.new(font_data, 12, dpiscale: 3).glyph_data("A").dimensions
    assert_equal TrueTypeRasterizer.new(12).glyph_data("A").dimensions,
      TrueTypeRasterizer.new(12, nil, 3).glyph_data("A").dimensions
    refute_equal TrueTypeRasterizer.new(32).glyph_data("A").dimensions,
      TrueTypeRasterizer.new(32, sdf: true).glyph_data("A").dimensions
    refute_equal TrueTypeRasterizer.new(32).glyph_data("A").string,
      TrueTypeRasterizer.new(32, :mono).glyph_data("A").string
    assert_equal TrueTypeRasterizer.new(32, :mono).glyph_data("A").string,
      TrueTypeRasterizer.new(32, hinting: :mono).glyph_data("A").string
  end

  # A TrueType font comes from a file name, a FileData, or any Data
  # (wrap_Font.cpp:122-145).
  def test_a_truetype_font_comes_from_a_file_or_any_data
    expected = TrueTypeRasterizer.new(font_data, 8).line_height
    bytes = Lota::Data::ByteData.new(File.binread(File.join(RESOURCES, "font.ttf")))

    assert_equal expected, TrueTypeRasterizer.new("resources/font.ttf", 8).line_height
    assert_equal expected, TrueTypeRasterizer.new(bytes, 8).line_height
    file = Lota::Filesystem.open_file("resources/font.ttf", :r).first
    assert_equal expected, TrueTypeRasterizer.new(file, 8).line_height
  ensure
    file&.close
  end

  def test_a_truetype_rasterizer_raises_loves_errors
    error = assert_raises(ArgumentError) { TrueTypeRasterizer.new(12, :sharp) }
    assert_equal "Invalid TrueType font hinting mode 'sharp', expected one of: 'normal', 'light', 'mono', 'none'",
      error.message
    assert_raises(ArgumentError) { TrueTypeRasterizer.new(12, hinting: :sharp) }
    assert_raises(ArgumentError) { TrueTypeRasterizer.new(12, :mono, hinting: :mono) }
    assert_raises(ArgumentError) { TrueTypeRasterizer.new(12, :mono, 1, 2) }
    assert_raises(TypeError) { TrueTypeRasterizer.new(12, 1) }
    assert_raises(TypeError) { TrueTypeRasterizer.new(12, :mono, "2") }
    assert_raises(TypeError) { TrueTypeRasterizer.new(font_data, "12") }
    assert_raises(TypeError) { TrueTypeRasterizer.new(:font, 12) }
    error = assert_raises(RuntimeError) { TrueTypeRasterizer.new(file_data("junk.ttf", "not a font"), 12) }
    assert_match(/\ATrueType Font loading error: FT_New_Face failed: 0x\h+ \(problem with font file\?\)\z/,
      error.message)
    error = assert_raises(RuntimeError) { TrueTypeRasterizer.new(0) }
    assert_equal "Invalid TrueType font size: 0", error.message
  end

  # w_newBMFontRasterizer reads the definition, then its images, one or a
  # table of them, each an ImageData or what love.image.newImageData
  # decodes, then the DPI scale (wrap_Font.cpp:158-196). Lota decodes
  # each image by its own kind (doc/contributors/upstream/015.md).
  def test_a_bmfont_rasterizer_takes_its_images_in_every_form
    image = Lota::Image::ImageData.new("resources/font-letters-ab.png")
    file = Lota::Filesystem.open_file("resources/font-letters-ab.png", :r).first
    [image, [image], "resources/font-letters-ab.png", file_data("font-letters-ab.png"), file, nil].each do |images|
      file.seek(0)
      rasterizer = BMFontRasterizer.new(bmfont_definition, images)

      assert rasterizer.glyphs?("A")
      refute rasterizer.glyphs?("B")
      assert_equal 9, rasterizer.advance
    end
    two = BMFontRasterizer.new(bmfont_definition, image, 2)

    assert_equal 2, Lota::Graphics::Font.new(two).dpi_scale
    assert_equal 10, BMFontRasterizer.new(bmfont_definition).line_height
  ensure
    file&.close
  end

  def test_a_bmfont_rasterizer_raises_loves_errors
    assert_raises(TypeError) { BMFontRasterizer.new(bmfont_definition, :image) }
    assert_raises(TypeError) { BMFontRasterizer.new(bmfont_definition, [nil]) }
    assert_raises(TypeError) { BMFontRasterizer.new(bmfont_definition, nil, "2") }
    assert_raises(TypeError) { BMFontRasterizer.new(:definition) }
    gray = Lota::Image::ImageData.new(18, 10, :r8)
    error = assert_raises(RuntimeError) { BMFontRasterizer.new(bmfont_definition, gray) }

    assert_equal "Only 32-bit RGBA images are supported in BMFonts.", error.message
    unpaged = file_data("unpaged.fnt", "info size=10 unicode=1\nchar id=65 x=0 y=0 width=8 height=10 page=0\n")
    error = assert_raises(RuntimeError) { BMFontRasterizer.new(unpaged) }

    assert_equal "Invalid BMFont character page id: 0", error.message
  end

  # w_newImageRasterizer decodes its image as love.image.newImageData does
  # (wrap_Font.cpp:198-215); the glyphs are in the order the image draws
  # them, and each answers its own code point.
  def test_an_image_rasterizer_reads_its_glyphs_from_an_image
    image = Lota::Image::ImageData.new("resources/font-letters-ab.png")
    [image, "resources/font-letters-ab.png", file_data("font-letters-ab.png")].each do |source|
      rasterizer = ImageRasterizer.new(source, "AB")

      assert rasterizer.glyphs?("AB", 65)
      refute rasterizer.glyphs?("C")
    end
    rasterizer = ImageRasterizer.new(image, "AB")
    spaced = ImageRasterizer.new(image, "AB", 2)
    glyph = rasterizer.glyph_data("B")

    assert_equal rasterizer.glyph_data("A").advance + 2, spaced.glyph_data("A").advance
    assert_equal [66, "B", :rgba8], [glyph.glyph, glyph.glyph_string, glyph.format]
  end

  def test_an_image_rasterizer_raises_loves_errors
    image = Lota::Image::ImageData.new("resources/font-letters-ab.png")

    assert_raises(TypeError) { ImageRasterizer.new(image, :AB) }
    assert_raises(TypeError) { ImageRasterizer.new(image, "AB", "2") }
    assert_raises(TypeError) { ImageRasterizer.new(image, "AB", 0, "1") }
    assert_raises(TypeError) { ImageRasterizer.new(:image, "AB") }
    error = assert_raises(RuntimeError) { ImageRasterizer.new(image, "A\xFF") }
    assert_match(/\AUTF-8 decoding error: /, error.message)
    error = assert_raises(RuntimeError) { ImageRasterizer.new(Lota::Image::ImageData.new(4, 4, :r8), "A") }
    assert_equal "Only 32-bit RGBA images are supported in Image Fonts!", error.message
  end

  # w_newGlyphData and w_Rasterizer_getGlyphData read a glyph as a
  # character or a code point.
  def test_glyph_data_is_of_a_character_or_a_code_point
    rasterizer = Rasterizer.new(font_data, 12)
    by_text = GlyphData.new(rasterizer, "a")
    by_code = GlyphData.new(rasterizer, 97)

    assert_equal by_text.string, by_code.string
    assert_equal by_text.string, rasterizer.glyph_data(97).string
    assert_equal by_text.string, rasterizer.glyph_data("abc").string
    refute_equal by_text.string, rasterizer.glyph_data("b").string
    assert_raises(TypeError) { GlyphData.new(:rasterizer, "a") }
    assert_raises(TypeError) { GlyphData.new(rasterizer, nil) }
    assert_raises(TypeError) { rasterizer.glyph_data(:a) }
    assert_match(/\AUTF-8 decoding error: /, assert_raises(RuntimeError) { GlyphData.new(rasterizer, "\xFF") }.message)
    assert_match(/\AUTF-8 decoding error: /, assert_raises(RuntimeError) { rasterizer.glyph_data("\xFF") }.message)
  end

  # GlyphData's metrics (wrap_GlyphData.cpp): a TrueType glyph answers the
  # code point 0 (TrueTypeRasterizer.cpp:155), and its bounding box is its
  # least x and y and its size.
  def test_glyph_data_answers_its_metrics
    glyph = Rasterizer.new(font_data, 12).glyph_data("a")
    x, y, width, height = glyph.bounding_box

    assert_equal [0, "\u0000"], [glyph.glyph, glyph.glyph_string]
    assert_equal [glyph.width, glyph.height], glyph.dimensions
    assert_equal [0, 11], glyph.bearing
    assert_equal [0, -3, 8, 14], [x, y, width, height]
    assert_equal glyph.width * glyph.height * 2, glyph.size
    assert_equal "GlyphData", glyph.object_type
    assert glyph.type_of?("Data")
    assert_kind_of Lota::Data, glyph
  end

  # GlyphData:clone copies the pixels and the metrics.
  def test_a_cloned_glyph_is_a_copy_of_its_own
    glyph = Rasterizer.new(font_data, 12).glyph_data("a")
    copy = glyph.clone

    assert_equal [glyph.string, glyph.advance, glyph.bearing], [copy.string, copy.advance, copy.bearing]
    refute_same glyph.__send__(:native), copy.__send__(:native)
  end

  # w_Rasterizer_hasGlyphs answers for every argument, and needs one.
  def test_glyphs_asks_of_every_argument
    rasterizer = Rasterizer.new(font_data, 12)

    assert rasterizer.glyphs?("AB", 67)
    refute rasterizer.glyphs?("A", "Ö")
    refute rasterizer.glyphs?(0xE9)
    assert Rasterizer.new.glyphs?("Ö", 0xE9)
    assert_raises(ArgumentError) { rasterizer.glyphs? }
    assert_raises(TypeError) { rasterizer.glyphs?(:a) }
  end

  # Rule 2: each kind's module matches what its factory makes, which
  # LÖVE's engine makes of a C++ class of its own: Font::newRasterizer
  # makes a TrueType or a BMFont rasterizer as the file holds
  # (font/freetype/Font.cpp:49-57), and newImageRasterizer an image one.
  def test_each_kind_matches_only_what_its_factory_makes
    image = Lota::Image::ImageData.new("resources/font-letters-ab.png")
    kinds = {
      TrueTypeRasterizer => [TrueTypeRasterizer.new, Rasterizer.new(font_data), Rasterizer.new(12)],
      BMFontRasterizer => [BMFontRasterizer.new(bmfont_definition), Rasterizer.new(bmfont_definition)],
      ImageRasterizer => [ImageRasterizer.new(image, "AB")],
    }

    kinds.each do |kind, made|
      made.each { |rasterizer| assert_operator kind, :===, rasterizer }
      (kinds.values.flatten - made).each { |rasterizer| refute_operator kind, :===, rasterizer }
      refute_operator kind, :===, Lota::Graphics::Font.new(12)
      refute_operator kind, :===, nil
    end
    assert_equal "Rasterizer", kinds.values.flatten.map(&:object_type).uniq.join
    assert_instance_of Rasterizer, TrueTypeRasterizer.new
  end

  # w_newFont and w_newImageFont take a Rasterizer as it is
  # (wrap_Graphics.cpp:1382-1435).
  def test_a_graphics_font_is_made_from_a_rasterizer
    rasterizer = TrueTypeRasterizer.new(font_data, 20)
    image = ImageRasterizer.new("resources/font-letters-ab.png", "AB")

    assert_equal Lota::Graphics::Font.new(font_data, 20).height, Lota::Graphics::Font.new(rasterizer).height
    refute_equal Lota::Graphics::Font.new(font_data, 12).height, Lota::Graphics::Font.new(rasterizer).height
    assert Lota::Graphics::ImageFont.new(image).glyphs?("AB")
    refute Lota::Graphics::ImageFont.new(image).glyphs?("C")
  end
end
