# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics.rectangle, circle, ellipse, arc, line, draw, color=, and
# color, and Lota::Graphics::Canvas.new's antialiasing, beyond what
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
  def drawn(size = 8, &)
    canvas = Lota::Graphics::Canvas.new(size, size)
    draw_into(canvas, &)
    Lota::Graphics.readback_texture(canvas)
  end

  # Draws the block into +canvas+, cleared to opaque black.
  def draw_into(canvas)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    yield
    Lota::Graphics.canvas = nil
  end

  # How many pixels of +image+, of +size+ by +size+, are neither black nor
  # white, as only an antialiased edge is.
  def blended(image, size)
    (0...size).to_a.product((0...size).to_a).count do |x, y|
      red = image.pixel(x, y).first
      red > 0 && red < 1
    end
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

  # w_rectangle rounds the corners when given a radius, with the vertical
  # radius the horizontal one unless given.
  def test_a_rectangle_rounds_its_corners_with_radii
    round = drawn { Lota::Graphics.rectangle(:fill, 0, 0, 8, 8, 4) }
    flat = drawn { Lota::Graphics.rectangle(:fill, 0, 0, 8, 8, 4, 0) }

    assert_equal [0.0, 0.0, 0.0, 1.0], round.pixel(0, 0)
    assert_equal [1.0, 1.0, 1.0, 1.0], round.pixel(4, 4)
    assert_equal [1.0, 1.0, 1.0, 1.0], round.pixel(0, 4)
    assert_equal [1.0, 1.0, 1.0, 1.0], flat.pixel(0, 0)
  end

  def test_a_rectangles_corners_take_a_count_of_segments
    assert_raises(TypeError) { Lota::Graphics.rectangle(:fill, 0, 0, 8, 8, 4, 4, "2") }
  end

  # w_ellipse takes two radii, the second the first unless given, and an
  # optional count of segments, as circle does.
  def test_an_ellipse_has_two_radii
    wide = drawn(16) { Lota::Graphics.ellipse(:fill, 8, 8, 8, 2) }
    round = drawn(16) { Lota::Graphics.ellipse(:fill, 8, 8, 8) }
    diamond = drawn(16) { Lota::Graphics.ellipse(:fill, 8, 8, 8, 8, 4) }

    assert_equal [1.0, 1.0, 1.0, 1.0], wide.pixel(2, 8)
    assert_equal [0.0, 0.0, 0.0, 1.0], wide.pixel(8, 4)
    assert_equal [1.0, 1.0, 1.0, 1.0], round.pixel(8, 3)
    assert_equal [0.0, 0.0, 0.0, 1.0], diamond.pixel(3, 3)
    assert_equal [1.0, 1.0, 1.0, 1.0], diamond.pixel(8, 8)
  end

  def test_an_ellipse_raises_loves_errors
    error = assert_raises(ArgumentError) { Lota::Graphics.ellipse(:outline, 0, 0, 1) }

    assert_equal "Invalid draw mode 'outline', expected one of: 'line', 'fill'", error.message
    assert_raises(TypeError) { Lota::Graphics.ellipse(:fill, 0, 0, "1") }
  end

  # Angles run clockwise from the right, since y points down, so a pie
  # from 0 to a quarter turn fills the lower right, out from the center,
  # where an open arc fills only what its ends' chord cuts off.
  def test_an_arc_is_a_pie_unless_told_otherwise
    quarter = drawn(16) { Lota::Graphics.arc(:fill, 8, 8, 8, 0, Math::PI / 2) }
    pie = drawn(16) { Lota::Graphics.arc(:fill, :pie, 8, 8, 8, 0, Math::PI / 2) }
    open = drawn(16) { Lota::Graphics.arc(:fill, "open", 8, 8, 8, 0, Math::PI / 2) }

    assert_equal [1.0, 1.0, 1.0, 1.0], quarter.pixel(12, 12)
    assert_equal [0.0, 0.0, 0.0, 1.0], quarter.pixel(4, 4)
    assert_equal [0.0, 0.0, 0.0, 1.0], quarter.pixel(12, 4)
    assert_equal [1.0, 1.0, 1.0, 1.0], pie.pixel(9, 9)
    assert_equal [0.0, 0.0, 0.0, 1.0], open.pixel(9, 9)
  end

  def test_an_arc_takes_a_count_of_segments
    few = drawn(16) { Lota::Graphics.arc(:fill, 8, 8, 8, 0, Math::PI / 2, 1) }
    many = drawn(16) { Lota::Graphics.arc(:fill, 8, 8, 8, 0, Math::PI / 2, 16) }

    refute_equal few.pixel(13, 13), many.pixel(13, 13)
  end

  def test_an_arc_raises_loves_errors
    draw = assert_raises(ArgumentError) { Lota::Graphics.arc(:outline, 8, 8, 8, 0, 1) }
    arc = assert_raises(ArgumentError) { Lota::Graphics.arc(:fill, :wedge, 8, 8, 8, 0, 1) }

    assert_equal "Invalid draw mode 'outline', expected one of: 'line', 'fill'", draw.message
    assert_equal "Invalid arc mode 'wedge', expected one of: 'open', 'closed', 'pie'", arc.message
    assert_raises(ArgumentError) { Lota::Graphics.arc(:fill, 8, 8, 8, 0) }
    assert_raises(TypeError) { Lota::Graphics.arc(:fill, 8, 8, "8", 0, 1) }
  end

  # w_line takes its coordinates as numbers or in one table, which Lota
  # takes as an Array.
  def test_a_line_joins_its_points_given_as_numbers_or_an_array
    numbers = drawn { Lota::Graphics.line(0, 4.5, 8, 4.5) }
    array = drawn { Lota::Graphics.line([0, 4.5, 8, 4.5]) }

    assert_equal [1.0, 1.0, 1.0, 1.0], numbers.pixel(3, 4)
    assert_equal [0.0, 0.0, 0.0, 1.0], numbers.pixel(3, 0)
    assert_equal (0..7).map { |y| numbers.pixel(3, y) }, (0..7).map { |y| array.pixel(3, y) }
  end

  def test_a_line_raises_loves_errors
    odd = assert_raises(RuntimeError) { Lota::Graphics.line(0, 0, 8) }
    one = assert_raises(RuntimeError) { Lota::Graphics.line([0, 0]) }

    assert_equal "Number of vertex components must be a multiple of two.", odd.message
    assert_equal "Need at least two vertices to draw a line.", one.message
    assert_raises(TypeError) { Lota::Graphics.line("0", 0, 8, 8) }
    assert_raises(TypeError) { Lota::Graphics.line(0, 0, 8, "8") }
  end

  # w_draw places a drawable by luax_checkstandardtransform's numbers: a
  # canvas drawn at an offset, or scaled, lands there.
  def test_a_canvas_draws_at_its_position_and_scale
    square = Lota::Graphics::Canvas.new(8, 8)
    draw_into(square) { Lota::Graphics.rectangle(:fill, 0, 0, 8, 8) }
    moved = drawn(16) { Lota::Graphics.draw(square, 8, 8) }
    halved = drawn(16) { Lota::Graphics.draw(square, 0, 0, 0, 0.5) }

    assert_equal [0.0, 0.0, 0.0, 1.0], moved.pixel(4, 4)
    assert_equal [1.0, 1.0, 1.0, 1.0], moved.pixel(12, 12)
    assert_equal [1.0, 1.0, 1.0, 1.0], halved.pixel(2, 2)
    assert_equal [0.0, 0.0, 0.0, 1.0], halved.pixel(6, 6)
  end

  def test_only_a_texture_can_be_drawn
    error = assert_raises(TypeError) { Lota::Graphics.draw(:canvas) }

    assert_equal "wrong argument type Symbol (expected Lota::Graphics::Texture)", error.message
  end

  # A canvas made with several antialiasing samples blends the edges of
  # what is drawn into it, where one made with LÖVE's default of one
  # sample draws a filled shape's pixels fully in or out.
  def test_a_canvas_with_msaa_smooths_edges
    smooth = Lota::Graphics::Canvas.new(16, 16, msaa: 4)
    draw_into(smooth) { Lota::Graphics.ellipse(:fill, 8, 8, 6, 6) }
    resolved = drawn(16) { Lota::Graphics.draw(smooth) }
    sharp = drawn(16) { Lota::Graphics.ellipse(:fill, 8, 8, 6, 6) }

    assert_operator blended(resolved, 16), :>, 0
    assert_equal 0, blended(sharp, 16)
  end

  # luax_intflag reads msaa only when it is a number, so anything else
  # leaves LÖVE's one sample.
  def test_an_msaa_that_is_not_a_number_is_ignored
    canvas = Lota::Graphics::Canvas.new(16, 16, msaa: "4")
    draw_into(canvas) { Lota::Graphics.ellipse(:fill, 8, 8, 6, 6) }

    assert_equal 0, blended(drawn(16) { Lota::Graphics.draw(canvas) }, 16)
  end
end
