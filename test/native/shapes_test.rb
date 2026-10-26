# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics.rectangle, circle, color=, and color, beyond what
# Lövetest's tests for them check (test/lovetest/tests/graphics.rb): the
# arguments LÖVE takes, and the errors it raises.
class ShapesTest < Minitest::Test
  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def teardown
    Lota::Graphics.color = 1, 1, 1, 1
  end

  # Draws the block into a new canvas of +size+ cleared to opaque black,
  # and reads it back.
  def drawn(size = 8)
    canvas = Lota::Graphics::Canvas.new(size, size)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    yield
    Lota::Graphics.canvas = nil
    Lota::Graphics.readback_texture(canvas)
  end

  def test_a_filled_rectangle_covers_its_pixels_in_the_current_color
    image = drawn { Lota::Graphics.rectangle(:fill, 2, 2, 4, 4) }

    assert_equal [1.0, 1.0, 1.0, 1.0], image.pixel(2, 2)
    assert_equal [1.0, 1.0, 1.0, 1.0], image.pixel(5, 5)
    assert_equal [0.0, 0.0, 0.0, 1.0], image.pixel(1, 1)
    assert_equal [0.0, 0.0, 0.0, 1.0], image.pixel(6, 6)
  end

  def test_a_draw_mode_may_be_a_string_as_in_lua
    image = drawn { Lota::Graphics.rectangle("fill", 0, 0, 8, 8) }

    assert_equal [1.0, 1.0, 1.0, 1.0], image.pixel(4, 4)
  end

  def test_an_unknown_draw_mode_raises_loves_error
    rectangle = assert_raises(ArgumentError) { Lota::Graphics.rectangle(:outline, 0, 0, 1, 1) }
    circle = assert_raises(ArgumentError) { Lota::Graphics.circle(:outline, 0, 0, 1) }

    assert_equal "Invalid draw mode 'outline', expected one of: 'line', 'fill'", rectangle.message
    assert_equal "Invalid draw mode 'outline', expected one of: 'line', 'fill'", circle.message
  end

  def test_coordinates_must_be_numbers
    assert_raises(TypeError) { Lota::Graphics.rectangle(:fill, "0", 0, 1, 1) }
    assert_raises(TypeError) { Lota::Graphics.circle(:fill, 0, 0, nil) }
  end

  # A circle of four segments is a square standing on one corner, so the
  # pixels at its bounding box's corners stay empty, where a round circle
  # of the same radius, with LÖVE's own count of segments, fills more.
  def test_a_circle_takes_a_count_of_segments
    diamond = drawn(16) { Lota::Graphics.circle(:fill, 8, 8, 8, 4) }
    round = drawn(16) { Lota::Graphics.circle(:fill, 8, 8, 8) }

    assert_equal [1.0, 1.0, 1.0, 1.0], diamond.pixel(8, 8)
    assert_equal [0.0, 0.0, 0.0, 1.0], diamond.pixel(3, 3)
    assert_equal [1.0, 1.0, 1.0, 1.0], round.pixel(3, 3)
  end

  def test_a_count_of_segments_must_be_an_integer
    assert_raises(TypeError) { Lota::Graphics.circle(:fill, 8, 8, 8, "4") }
  end

  def test_the_color_is_white_until_set
    assert_equal [1.0, 1.0, 1.0, 1.0], Lota::Graphics.color
  end

  def test_the_color_is_set_from_three_or_four_components_or_an_array_of_them
    Lota::Graphics.color = 1, 0.5, 0.25, 0.75

    assert_equal [1.0, 0.5, 0.25, 0.75], Lota::Graphics.color

    Lota::Graphics.color = 0, 1, 0

    assert_equal [0.0, 1.0, 0.0, 1.0], Lota::Graphics.color

    Lota::Graphics.color = [0, 0, 1]

    assert_equal [0.0, 0.0, 1.0, 1.0], Lota::Graphics.color
  end

  # LÖVE stores the color as single-precision floats, and clamps each
  # component to 0 through 1 (metal/Graphics.mm, Graphics::setColor).
  def test_the_color_is_stored_as_floats_and_clamped
    Lota::Graphics.color = 0.1, 2, -1, 1

    red, green, blue, = Lota::Graphics.color

    assert_equal [0.1].pack("f").unpack1("f"), red
    assert_equal 1.0, green
    assert_equal 0.0, blue
  end

  def test_drawing_uses_the_color
    image = drawn do
      Lota::Graphics.color = 1, 0, 0
      Lota::Graphics.rectangle(:fill, 0, 0, 8, 8)
    end

    assert_equal [1.0, 0.0, 0.0, 1.0], image.pixel(4, 4)
  end

  def test_the_line_width_is_a_float
    Lota::Graphics.line_width = 0.1

    assert_equal [0.1].pack("f").unpack1("f"), Lota::Graphics.line_width
    assert_raises(TypeError) { Lota::Graphics.line_width = "2" }
  ensure
    Lota::Graphics.line_width = 1
  end

  def test_the_line_style_is_a_symbol_and_may_be_set_from_a_string
    before = Lota::Graphics.line_style
    Lota::Graphics.line_style = "smooth"

    assert_equal :smooth, Lota::Graphics.line_style
  ensure
    Lota::Graphics.line_style = before
  end

  def test_an_unknown_line_style_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Graphics.line_style = :wavy }

    assert_equal "Invalid line style 'wavy', expected one of: 'rough', 'smooth'", error.message
  end

  def test_a_color_needs_three_or_four_numbers
    two = assert_raises(ArgumentError) { Lota::Graphics.color = 1, 0 }
    five = assert_raises(ArgumentError) { Lota::Graphics.color = 1, 0, 0, 1, 1 }

    assert_equal "wrong number of arguments (given 2, expected 3 or 4)", two.message
    assert_equal "wrong number of arguments (given 5, expected 3 or 4)", five.message
    assert_raises(TypeError) { Lota::Graphics.color = 1, "0", 0 }
  end
end
