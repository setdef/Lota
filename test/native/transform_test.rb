# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The forms of Lota::Math::Transform and Lota::Graphics's transformation
# calls that Lövetest's tests do not reach: push with a Transform
# (wrap_Graphics.cpp, w_push), apply_transform with numbers
# (luax_checkstandardtransform, wrap_SpriteBatch.h:33-64), and
# luax_checkmatrix's layouts and tables (wrap_Transform.cpp:33-124), each
# read back through the engine's own transformPoint.
class TransformTest < Minitest::Test
  include NativeHelper

  Transform = Lota::Math::Transform
  Graphics = Lota::Graphics

  # The identity, column by column, then a translation by 4 and 2 in the
  # last column.
  COLUMNS = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [4, 2, 0, 1]].freeze

  def setup
    EngineHelper.open_window
    Graphics.origin
  end

  def teardown
    Graphics.origin
  end

  def test_push_applies_a_transform_after_it_saves_the_state
    Graphics.push(:transform, Transform.new(3, 4)) do
      assert_equal [4.0, 5.0], Graphics.transform_point(1, 1)
    end

    assert_equal [1.0, 1.0], Graphics.transform_point(1, 1)
  end

  # LÖVE applies only a Transform (luax_istype), so anything else after the
  # stack type is ignored.
  def test_push_ignores_what_is_not_a_transform
    Graphics.push(:transform, 7)

    assert_equal [1.0, 1.0], Graphics.transform_point(1, 1)
  ensure
    Graphics.pop
  end

  def test_apply_transform_takes_a_placement_with_luas_defaults
    Graphics.apply_transform(10, nil, nil, 2)

    assert_equal [12.0, 2.0], Graphics.transform_point(1, 1)
  end

  def test_replace_transform_takes_a_placement
    Graphics.translate(50, 50)
    Graphics.replace_transform(1, 2)

    assert_equal [1.0, 2.0], Graphics.transform_point(0, 0)
  end

  def test_apply_transform_refuses_more_than_nine_numbers
    assert_raises(ArgumentError) { Graphics.apply_transform(*Array.new(10, 0)) }
  end

  def test_a_row_major_matrix_reads_row_by_row
    transform = Transform.new
    transform.matrix = 1, 0, 0, 4, 0, 1, 0, 2, 0, 0, 1, 0, 0, 0, 0, 1

    assert_equal [5.0, 3.0], transform.transform_point(1, 1)
    assert_equal [1.0, 0.0, 0.0, 4.0], transform.matrix.first(4)
  end

  def test_a_column_major_matrix_reads_column_by_column_from_a_table_of_tables
    transform = Transform.new
    transform.matrix = :column, COLUMNS

    assert_equal [5.0, 3.0], transform.transform_point(1, 1)
  end

  def test_a_matrix_refuses_an_unknown_layout_and_a_wrong_count
    transform = Transform.new

    error = assert_raises(ArgumentError) { transform.matrix = :diagonal, *COLUMNS.flatten }
    assert_match(/Invalid matrix layout 'diagonal'/, error.message)
    assert_raises(ArgumentError) { transform.matrix = [1, 2, 3] }
  end

  # The identity as the projection maps only -1 to 1 onto the canvas, so a
  # pixel drawn at (2, 2) falls outside it, as in Lövetest's
  # resetProjection test.
  def test_the_projection_takes_a_transform
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Graphics.canvas = canvas
    Graphics.clear(0, 0, 0, 1)
    Graphics.color = 1, 1, 1, 1
    Graphics.projection = Transform.new
    Graphics.rectangle(:fill, 2, 2, 1, 1)
    Graphics.reset_projection
    Graphics.canvas = nil

    assert_equal [0.0, 0.0, 0.0, 1.0], Graphics.readback_texture(canvas).pixel(2, 2)
    assert_raises(ArgumentError) { Graphics.projection = :row, 1, 2 }
  ensure
    Graphics.canvas = nil
    Graphics.reset_projection
  end

  def test_the_methods_that_change_a_transform_return_it
    transform = Transform.new

    assert_same transform, transform.translate(1, 2).rotate(0).scale(1).shear(0, 0).reset
    assert_same transform, transform.apply(Transform.new).inverse_of(Transform.new)
  end

  def test_an_object_argument_must_be_a_transform
    assert_raises(TypeError) { Transform.new.apply(Graphics) }
    assert_raises(TypeError) { Transform.new * nil }
  end

  # Transform's __mul (wrap_Transform.cpp:296-304) is Ruby's *, which
  # makes a new Transform that does the right one first, and changes
  # neither.
  def test_multiplying_makes_a_new_transform_that_does_the_right_one_first
    left = Transform.new.scale(2)
    right = Transform.new.translate(3, 4)
    product = left * right

    assert_instance_of Transform, product
    assert_equal [8.0, 10.0], product.transform_point(1, 1)
    assert_equal [2.0, 2.0], left.transform_point(1, 1)
    assert_equal [4.0, 5.0], right.transform_point(1, 1)
  end

  def test_transformation_takes_lovees_defaults_for_nil
    transform = Transform.new
    transform.transformation = 1, 2, nil, 3

    assert_equal [4.0, 5.0], transform.transform_point(1, 1)
  end
end
