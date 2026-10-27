# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# Lota::Graphics::Font.new, font=, font, print, printf, default_filter=,
# and default_filter, beyond what Lövetest's tests for them check
# (test/lovetest/tests/graphics.rb): the arguments LÖVE takes, and the
# errors it raises.
class TextTest < Minitest::Test
  def setup
    EngineHelper.open_window
    Lovetest.load
    Lota::Graphics.font = Lovetest.font
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def teardown
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.default_filter = :nearest, :nearest, 1
  end

  # Draws the block into a new 32 by 32 canvas cleared to opaque black,
  # and reads it back.
  def drawn
    canvas = Lota::Graphics::Canvas.new(32, 32)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    yield
    Lota::Graphics.canvas = nil
    Lota::Graphics.readback_texture(canvas)
  end

  # Every pixel of +image+, as a String of its bytes.
  def pixels(image)
    LotaNativeTest.image_data_bytes(image.native)
  end

  def lit?(image)
    pixels(image).bytes.each_slice(4).any? { |r, g, b, _| r + g + b > 0 }
  end

  def test_text_is_drawn_in_the_current_color
    image = drawn do
      Lota::Graphics.color = 1, 0, 0, 1
      Lota::Graphics.print("love", 0, 3)
    end

    assert lit?(image)
    assert(pixels(image).bytes.each_slice(4).all? { |_, g, b, _| g == 0 && b == 0 })
  end

  # luax_checkcoloredstring (wrap_Font.cpp:33-76): each string in the
  # color before it, white before any, multiplied by the current color.
  def test_colored_text_draws_each_string_in_the_color_before_it
    plain = drawn { Lota::Graphics.print("love", 0, 3) }
    white = drawn { Lota::Graphics.print([[1, 1, 1, 1], "love"], 0, 3) }
    uncolored = drawn { Lota::Graphics.print(["love"], 0, 3) }
    red = drawn { Lota::Graphics.print([[1, 0, 0], "love"], 0, 3) }

    assert_equal pixels(plain), pixels(white)
    assert_equal pixels(plain), pixels(uncolored)
    refute_equal pixels(plain), pixels(red)
    assert(pixels(red).bytes.each_slice(4).all? { |_, g, b, _| g == 0 && b == 0 })
  end

  def test_print_places_text_where_it_is_told_and_at_the_origin_by_default
    origin = drawn { Lota::Graphics.print("love") }
    zero = drawn { Lota::Graphics.print("love", 0, 0, 0, 1, 1, 0, 0, 0, 0) }
    moved = drawn { Lota::Graphics.print("love", 8, 8) }
    scaled = drawn { Lota::Graphics.print("love", 0, 0, nil, 2) }

    assert_equal pixels(origin), pixels(zero)
    refute_equal pixels(origin), pixels(moved)
    refute_equal pixels(origin), pixels(scaled)
  end

  # w_printf's alignment (wrap_Graphics.cpp:3478-3480): left when left out
  # or nil, and a string works as it does in Lua.
  def test_printf_aligns_text_within_its_limit
    left = drawn { Lota::Graphics.printf("love", 0, 0, 32) }
    left_nil = drawn { Lota::Graphics.printf("love", 0, 0, 32, nil) }
    left_named = drawn { Lota::Graphics.printf("love", 0, 0, 32, "left") }
    right = drawn { Lota::Graphics.printf("love", 0, 0, 32, :right) }

    assert_equal pixels(left), pixels(left_nil)
    assert_equal pixels(left), pixels(left_named)
    refute_equal pixels(left), pixels(right)
  end

  def test_an_unknown_alignment_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Graphics.printf("love", 0, 0, 32, :middle) }

    assert_equal "Invalid alignment 'middle', expected one of: 'left', 'center', 'right', 'justify'", error.message
  end

  def test_printf_needs_a_position_and_a_limit
    assert_raises(TypeError) { Lota::Graphics.printf("love", nil, 0, 32) }
    assert_raises(TypeError) { Lota::Graphics.printf("love", 0, 0, nil) }
  end

  def test_text_must_be_a_string_or_colored_text
    assert_raises(TypeError) { Lota::Graphics.print(5, 0, 0) }
    assert_raises(TypeError) { Lota::Graphics.printf([[1, 0, 0], 5], 0, 0, 32) }
  end

  # Graphics::getFont (Graphics.cpp:1002-1006) makes LÖVE's default font
  # when none is set; a Font set is the one drawn with.
  def test_the_font_is_the_one_set
    big = Lota::Graphics::Font.new(24)
    Lota::Graphics.font = big
    with_big = drawn { Lota::Graphics.print("o", 0, 0) }
    with_default = drawn do
      Lota::Graphics.font = Lota::Graphics::Font.new
      Lota::Graphics.print("o", 0, 0)
    end

    assert_instance_of Lota::Graphics::Font, Lota::Graphics.font
    refute_equal pixels(with_big), pixels(with_default)
  end

  # w_print and w_printf draw in a Font given before the position
  # (wrap_Graphics.cpp:3415-3423 and 3443-3447, 3482-3483), as setting it
  # would, and leave the current font as it was.
  def test_print_and_printf_draw_in_a_font_given_first
    big = Lota::Graphics::Font.new(24)
    current = Lota::Graphics.font
    given = drawn { Lota::Graphics.print("o", big, 0, 0) }
    set = drawn do
      Lota::Graphics.font = big
      Lota::Graphics.print("o", 0, 0)
    end
    Lota::Graphics.font = current
    wrapped_given = drawn { Lota::Graphics.printf("o", big, 0, 0, 32, :right) }
    wrapped_set = drawn do
      Lota::Graphics.font = big
      Lota::Graphics.printf("o", 0, 0, 32, :right)
    end
    Lota::Graphics.font = current
    plain = drawn { Lota::Graphics.print("o", 0, 0) }

    assert_equal pixels(set), pixels(given)
    assert_equal pixels(wrapped_set), pixels(wrapped_given)
    refute_equal pixels(given), pixels(plain)
    assert_raises(ArgumentError) { Lota::Graphics.print("o", 0, 0, 0, 1, 1, 0, 0, 0, 0, 0) }
    assert_raises(TypeError) { Lota::Graphics.printf("o", big, 0, 0, nil) }
  end

  def test_the_font_must_be_a_font
    error = assert_raises(TypeError) { Lota::Graphics.font = nil }

    assert_equal "wrong argument type NilClass (expected Lota::Graphics::Font)", error.message
  end

  # luax_checktruetypesettings (wrap_Font.cpp:67-104): the hinting and DPI
  # scale after the size, or as a table, which Ruby takes as keywords. The
  # default font shows both; Lövetest's pixel font, drawn with the nearest
  # filter, shows neither.
  def test_a_font_takes_its_settings_after_the_size_or_as_keywords
    drawn_with = lambda do |font|
      Lota::Graphics.font = font
      pixels(drawn { Lota::Graphics.print("love", 0, 3) })
    end
    normal = drawn_with.(Lota::Graphics::Font.new(13, "normal"))

    assert_equal drawn_with.(Lota::Graphics::Font.new(13, :mono, 2)),
      drawn_with.(Lota::Graphics::Font.new(13, hinting: :mono, dpiscale: 2))
    assert_equal normal, drawn_with.(Lota::Graphics::Font.new(13))
    refute_equal normal, drawn_with.(Lota::Graphics::Font.new(13, :mono))
    refute_equal normal, drawn_with.(Lota::Graphics::Font.new(13, dpiscale: 2))
    refute_equal normal, drawn_with.(Lota::Graphics::Font.new(13, sdf: true))
    assert_raises(ArgumentError) { Lota::Graphics::Font.new(8, :mono, hinting: :mono) }
  end

  # w_newTrueTypeRasterizer (wrap_Font.cpp:110-111): LÖVE's default font is
  # 13 pixels tall unless told otherwise.
  def test_the_default_font_is_13_pixels_tall
    drawn_with = lambda do |font|
      Lota::Graphics.font = font
      pixels(drawn { Lota::Graphics.print("love", 0, 3) })
    end

    assert_equal drawn_with.(Lota::Graphics::Font.new(13)), drawn_with.(Lota::Graphics::Font.new)
    refute_equal drawn_with.(Lota::Graphics::Font.new(12)), drawn_with.(Lota::Graphics::Font.new)
  end

  def test_a_font_from_data_alone_takes_loves_default_size
    Lota::Graphics.font = Lota::Graphics::Font.new(Lovetest.resource("font.ttf"))
    alone = drawn { Lota::Graphics.print("love", 0, 0) }
    Lota::Graphics.font = Lota::Graphics::Font.new(Lovetest.resource("font.ttf"), 12)
    twelve = drawn { Lota::Graphics.print("love", 0, 0) }

    assert_equal pixels(twelve), pixels(alone)
  end

  def test_an_unknown_hinting_mode_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Graphics::Font.new(8, :sharp) }

    assert_equal "Invalid TrueType font hinting mode 'sharp', expected one of: 'normal', 'light', 'mono', 'none'",
      error.message
  end

  def test_data_that_holds_no_font_raises_loves_error
    data = Lota::Filesystem::FileData.new("not a font", "font.ttf")

    assert_raises(RuntimeError) { Lota::Graphics::Font.new(data, 8) }
  end

  # w_setDefaultFilter (wrap_Graphics.cpp:2751-2767): the magnification
  # filter follows the minification one, and the anisotropy is clamped.
  def test_the_default_filter_takes_one_filter_for_both
    Lota::Graphics.default_filter = :linear

    assert_equal [:linear, :linear, 1], Lota::Graphics.default_filter
  end

  def test_the_default_anisotropy_is_clamped
    Lota::Graphics.default_filter = :nearest, :linear, 1000

    assert_equal [:nearest, :linear, 255], Lota::Graphics.default_filter

    Lota::Graphics.default_filter = :nearest, :linear, 0

    assert_equal [:nearest, :linear, 1], Lota::Graphics.default_filter
  end

  def test_an_unknown_filter_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Graphics.default_filter = :cubic }

    assert_equal "Invalid filter mode 'cubic', expected one of: 'linear', 'nearest'", error.message
  end
end
