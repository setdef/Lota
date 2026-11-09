# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# Lota::Graphics::TextBatch, Lota::Graphics::ImageFont, a BMFont made by
# Lota::Graphics::Font.new, and print and printf placed by a Transform,
# beyond what Lövetest's tests for them check
# (test/lovetest/tests/graphics.rb): the forms LÖVE takes, and the errors
# it raises (src/modules/graphics/wrap_TextBatch.cpp,
# src/modules/graphics/wrap_Graphics.cpp, and
# src/modules/font/wrap_Font.cpp).
class TextBatchTest < Minitest::Test
  Font = Lota::Graphics::Font
  TextBatch = Lota::Graphics::TextBatch
  ImageFont = Lota::Graphics::ImageFont

  def setup
    EngineHelper.open_window
    Lovetest.load
    Lota::Graphics.font = Lovetest.font
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def teardown
    Lota::Graphics.color = 1, 1, 1, 1
  end

  # Draws the block into a new 32 by 32 canvas cleared to opaque black,
  # and reads its pixels back.
  def drawn
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    yield
    Lota::Graphics.canvas = nil
    LotaNativeTest.image_data_bytes(Lota::Graphics.readback_texture(canvas).__send__(:native))
  end

  def lit?(bytes)
    bytes.bytes.each_slice(4).any? { |r, g, b, _| r + g + b > 0 }
  end

  def batch(text = nil)
    TextBatch.new(Lovetest.font, text)
  end

  def font_file(path)
    Lota::Filesystem.new_file_data(File.binread(File.join(__dir__, "../lovetest/resources", path)), path).first
  end

  def test_a_batch_without_text_is_empty
    assert_equal [0.0, 0.0], batch.dimensions
    assert_equal 0.0, batch.width
    assert_equal 0.0, batch.height
  end

  def test_a_batch_is_made_with_a_font_only
    assert_raises(TypeError) { TextBatch.new("font") }
    assert_raises(TypeError) { TextBatch.new(nil, "text") }
    assert_raises(TypeError) { TextBatch.new(Lovetest.font, 5) }
    assert_raises(TypeError) { batch.font = nil }
  end

  # w_TextBatch_add returns the index of its text counting from 1, and
  # getWidth and getHeight take one.
  def test_add_returns_an_index_counting_from_1_that_width_and_height_take
    text = batch
    first = text.add("test")
    second = text.add("more text", 100, 0)

    assert_equal [1, 2], [first, second]
    assert_equal Lovetest.font.width("test"), text.width(first)
    assert_equal Lovetest.font.width("more text"), text.width(second)
    assert_equal [text.width(first), Lovetest.font.height], text.dimensions(first)
    assert_equal Lovetest.font.height, text.height(second)
    assert_equal [text.width(first), text.width(second)].max, text.width
  end

  def test_set_replaces_what_the_batch_holds
    text = batch("a long line of text")
    text.set("ab")

    assert_equal Lovetest.font.width("ab"), text.width
  end

  def test_setf_wraps_text_at_its_limit
    text = batch
    text.setf("a long line of text that wraps", 40, :left)

    assert_operator text.width, :<=, 40
    assert_operator text.height, :>, Lovetest.font.height
  end

  def test_addf_wraps_and_aligns_within_its_limit
    text = batch
    index = text.addf("ab", 32, :right)

    assert_equal 1, index
    assert_equal Lovetest.font.width("ab"), text.width
    left = drawn { Lota::Graphics.draw(batch.tap { |b| b.addf("ab", 32, :left) }) }
    right = drawn { Lota::Graphics.draw(text) }
    refute_equal left, right
  end

  def test_an_unknown_alignment_raises_loves_error
    message = "Invalid align mode 'middle', expected one of: 'left', 'center', 'right', 'justify'"

    assert_equal message, assert_raises(ArgumentError) { batch.setf("ab", 32, :middle) }.message
    assert_equal message, assert_raises(ArgumentError) { batch.addf("ab", 32, :middle) }.message
    assert_raises(TypeError) { batch.setf("ab", nil, :left) }
  end

  def test_colored_text_draws_in_its_colors
    red = drawn { Lota::Graphics.draw(batch([[1, 0, 0], "love"]), 0, 3) }
    plain = drawn { Lota::Graphics.draw(batch("love"), 0, 3) }

    assert lit?(red)
    assert(red.bytes.each_slice(4).all? { |_, g, b, _| g == 0 && b == 0 })
    refute_equal plain, red
  end

  def test_a_color_in_a_batch_text_with_fewer_than_three_elements_raises_loves_error
    text_batch = batch("a")
    created = assert_raises(TypeError) { TextBatch.new(Lovetest.font, [[1, 0], "a"]) }
    set = assert_raises(TypeError) { text_batch.set([[1, 0], "a"]) }
    added = assert_raises(TypeError) { text_batch.add([[1, 0], "a"]) }

    assert_equal "bad argument #-2 to 'Lota::Graphics::TextBatch.new' (number expected, got nil)", created.message
    assert_equal "bad argument #-2 to 'Lota::Graphics::TextBatch#set' (number expected, got nil)", set.message
    assert_equal "bad argument #-2 to 'Lota::Graphics::TextBatch#add' (number expected, got nil)", added.message
  end

  def test_text_is_drawn_where_the_draw_places_it
    origin = drawn { Lota::Graphics.draw(batch("love")) }
    moved = drawn { Lota::Graphics.draw(batch("love"), 8, 8) }

    assert lit?(origin)
    refute_equal origin, moved
  end

  # luax_checkstandardtransform reads a Transform in place of the numbers.
  def test_a_transform_places_text_as_its_numbers_do
    transform = Lota::Math::Transform.new(4, 6, 0.5, 1, 1)
    numbers = [4, 6, 0.5, 1, 1]

    assert_equal drawn { Lota::Graphics.draw(batch("ab"), *numbers) },
      drawn { Lota::Graphics.draw(batch("ab"), transform) }

    by_numbers = batch
    by_numbers.add("ab", *numbers)
    by_numbers.addf("cd", 20, :center, *numbers)
    by_transform = batch
    by_transform.add("ab", transform)
    by_transform.addf("cd", 20, :center, transform)

    assert_equal drawn { Lota::Graphics.draw(by_numbers) }, drawn { Lota::Graphics.draw(by_transform) }
  end

  def test_the_font_changes_the_layout
    text = batch("test")
    big = Font.new(File.join("resources", "font.ttf"), 16)
    text.font = big

    assert_equal big.width("test"), text.width
    assert_equal big.height, text.font.height
  end

  def test_clear_removes_the_text
    text = batch("test")
    text.clear

    assert_equal [0.0, 0.0], text.dimensions
    assert_equal 1, text.add("ab")
  end

  def test_only_a_drawable_text_batch_is_drawn_by_draw
    assert_raises(TypeError) { Lota::Graphics.draw(batch, "x") }
  end

  def test_print_placed_by_a_transform_is_print_placed_by_numbers
    transform = Lota::Math::Transform.new(4, 6, 0.5, 1, 1)
    numbers = [4, 6, 0.5, 1, 1]
    big = Font.new(File.join("resources", "font.ttf"), 16)

    assert_equal drawn { Lota::Graphics.print("ab", *numbers) }, drawn { Lota::Graphics.print("ab", transform) }
    assert_equal drawn { Lota::Graphics.print("ab", big, *numbers) },
      drawn { Lota::Graphics.print("ab", big, transform) }
    assert_equal drawn { Lota::Graphics.print([[1, 0, 0], "ab"], transform) },
      drawn { Lota::Graphics.print([[1, 0, 0], "ab"], *numbers) }
  end

  def test_printf_placed_by_a_transform_is_printf_placed_by_numbers
    transform = Lota::Math::Transform.new(2, 3, 0, 1, 1)
    big = Font.new(File.join("resources", "font.ttf"), 16)

    assert_equal drawn { Lota::Graphics.printf("ab", 2, 3, 24, :center) },
      drawn { Lota::Graphics.printf("ab", transform, 24, :center) }
    assert_equal drawn { Lota::Graphics.printf("ab", big, 2, 3, 24, :right) },
      drawn { Lota::Graphics.printf("ab", big, transform, 24, :right) }
    assert_equal drawn { Lota::Graphics.printf("ab", 2, 3, 24) }, drawn { Lota::Graphics.printf("ab", transform, 24) }
  end

  def test_printf_by_a_transform_raises_loves_errors
    transform = Lota::Math::Transform.new

    assert_raises(ArgumentError) { Lota::Graphics.printf("ab", transform, 24, :middle) }
    assert_raises(TypeError) { Lota::Graphics.printf("ab", transform, nil) }
  end

  # w_newImageRasterizer: the glyphs in the order they are drawn, spaced
  # by the extra spacing, from a file name, a FileData, or an ImageData.
  def test_an_image_font_draws_the_glyphs_of_its_image
    font = ImageFont.new("resources/font-letters-ab.png", "AB")

    assert_instance_of Font, font
    assert font.glyphs?("AB")
    refute font.glyphs?("C")
    assert_equal 1, font.dpi_scale
    assert_equal 10, font.height
  end

  def test_an_image_font_is_made_from_any_source_of_an_image
    named = ImageFont.new("resources/font-letters-ab.png", "AB")
    from_file_data = ImageFont.new(font_file("font-letters-ab.png"), "AB")
    from_image_data = ImageFont.new(Lota::Image::ImageData.new(font_file("font-letters-ab.png")), "AB")

    assert_equal named.width("AB"), from_file_data.width("AB")
    assert_equal named.width("AB"), from_image_data.width("AB")
  end

  def test_extra_spacing_widens_each_glyph
    plain = ImageFont.new("resources/font-letters-ab.png", "AB")
    spaced = ImageFont.new("resources/font-letters-ab.png", "AB", 3)

    assert_equal plain.width("AB") + 6, spaced.width("AB")
    assert_equal plain.width("AB"), ImageFont.new("resources/font-letters-ab.png", "AB", nil).width("AB")
  end

  # w_newImageRasterizer reads the extra spacing with luaL_optinteger
  # (wrap_Font.cpp:206), which LuaJIT cuts toward 0.
  def test_extra_spacing_is_cut_to_a_whole_number
    plain = ImageFont.new("resources/font-letters-ab.png", "AB")

    assert_equal plain.width("AB") + 6, ImageFont.new("resources/font-letters-ab.png", "AB", 3.7).width("AB")
    assert_equal plain.width("AB"), ImageFont.new("resources/font-letters-ab.png", "AB", 0.9).width("AB")
  end

  def test_the_dpi_scale_of_an_image_font_scales_its_glyphs
    font = ImageFont.new("resources/font-letters-ab.png", "AB", 0, 2)

    assert_equal 2, font.dpi_scale
  end

  def test_an_image_font_raises_loves_errors
    assert_raises(TypeError) { ImageFont.new("resources/font-letters-ab.png", nil) }
    assert_raises(TypeError) { ImageFont.new(:image, "AB") }
    assert_raises(TypeError) { ImageFont.new("resources/font-letters-ab.png", "AB", "1") }
    assert_raises(TypeError) { ImageFont.new("resources/font-letters-ab.png", "AB", 0, "1") }
    assert_raises(RuntimeError) { ImageFont.new("resources/missing.png", "AB") }
  end

  def test_an_image_font_draws_text
    font = ImageFont.new("resources/font-letters-ab.png", "AB")
    text = drawn { Lota::Graphics.print("AB", font, 0, 0) }

    assert lit?(text)
  end

  # Rule 2: the engine cannot tell an image font from another, so
  # ImageFont === is true of every Font, and of nothing else.
  def test_an_image_font_module_matches_every_font
    assert_operator ImageFont, :===, ImageFont.new("resources/font-letters-ab.png", "AB")
    assert_operator ImageFont, :===, Font.new(12)
    refute_operator ImageFont, :===, batch
    refute_operator ImageFont, :===, "font"
  end

  # w_newText marks itself deprecated, renamed to newTextBatch, then
  # makes a TextBatch; the notice names Lota's methods and where the game
  # called it, and prints once.
  def test_text_new_makes_a_text_batch_and_prints_loves_deprecation_notice
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    text = nil
    first, = capture_io { text = Lota::Graphics::Text.new(Lovetest.font, "test") }
    second, = capture_io { Lota::Graphics::Text.new(Lovetest.font) }

    assert_instance_of TextBatch, text
    assert_equal Lovetest.font.width("test"), text.width
    assert_match(/\ALota - Warning: .*text_batch_test\.rb:\d+: Using deprecated function Lota::Graphics::Text\.new \(renamed to Lota::Graphics::TextBatch\.new\)\n\z/, first)
    assert_empty second
  ensure
    capture_io { Lota::Deprecation.output = output }
  end

  def test_text_matches_every_text_batch
    assert_operator Lota::Graphics::Text, :===, batch
    refute_operator Lota::Graphics::Text, :===, Font.new(12)
  end

  BMFONT = <<~FNT
    info face="test" size=10 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0
    common lineHeight=10 base=8 scaleW=18 scaleH=10 pages=1 packed=0
    page id=0 file="font-letters-ab.png"
    chars count=1
    char id=65 x=0 y=0 width=8 height=10 xoffset=0 yoffset=0 xadvance=9 page=0 chnl=15
  FNT

  def bmfont_definition
    Lota::Filesystem.new_file_data(BMFONT, "font.fnt").first
  end

  # w_newBMFontRasterizer: the definition, then its images.
  def test_a_bmfont_is_made_from_its_definition_and_images
    image = Lota::Image::ImageData.new("resources/font-letters-ab.png")
    [image, [image], "resources/font-letters-ab.png", font_file("font-letters-ab.png")].each do |images|
      font = Font.new(bmfont_definition, images)

      assert font.glyphs?("A")
      refute font.glyphs?("B")
      assert_equal 9, font.width("A")
      assert_equal 10, font.height
    end
  end

  def test_a_bmfont_takes_a_dpi_scale
    font = Font.new(bmfont_definition, "resources/font-letters-ab.png", 2)

    assert_equal 2, font.dpi_scale
  end

  def test_a_bmfont_draws_text
    font = Font.new(bmfont_definition, "resources/font-letters-ab.png")

    assert lit?(drawn { Lota::Graphics.print("A", font, 0, 0) })
  end

  def test_a_bmfont_raises_loves_errors
    assert_raises(TypeError) { Font.new(bmfont_definition, :image) }
    assert_raises(TypeError) { Font.new(bmfont_definition, [nil]) }
    assert_raises(TypeError) { Font.new(bmfont_definition, "resources/font-letters-ab.png", "2") }
    assert_raises(ArgumentError) { Font.new(bmfont_definition, "resources/font-letters-ab.png", 1, 2) }
    assert_raises(ArgumentError) { Font.new(bmfont_definition, "resources/font-letters-ab.png", hinting: :mono) }
    outside = Lota::Filesystem.new_file_data(BMFONT.sub("x=0 y=0", "x=100 y=0"), "outside.fnt").first
    error = assert_raises(RuntimeError) { Font.new(outside, "resources/font-letters-ab.png") }

    assert_equal "Invalid coordinates for BMFont character 65.", error.message
  end
end
