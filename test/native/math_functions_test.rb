# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Math's BezierCurve, RandomGenerator, and functions, beyond what
# Lövetest's tests for them check (test/lovetest/tests/math.rb): how they
# read their arguments and what they raise, as LÖVE's wrap files and the
# FFI code of wrap_Math.lua have them (vendor/love/src/modules/math).
class MathFunctionsTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # w_newBezierCurve reads a table, or else every argument
  # (wrap_Math.cpp:86-115), and an x without its y is not a number.
  def test_a_curve_takes_its_points_as_arguments_or_an_array
    listed = Lota::Math::BezierCurve.new(1, 2, 3, 4, 5, 6)
    array = Lota::Math::BezierCurve.new([1, 2, 3, 4, 5, 6])

    assert_equal [listed.control_point(2), listed.control_point(3)], [array.control_point(2), array.control_point(3)]
    assert_equal [3.0, 4.0], listed.control_point(2)
    assert_raises(TypeError) { Lota::Math::BezierCurve.new(1, 2, 3) }
  end

  # The wrap functions count from 1 and pass 0 and negative indices on,
  # which BezierCurve.cpp:111-165 counts back from the end.
  def test_control_points_count_from_one_and_back_from_the_last
    curve = Lota::Math::BezierCurve.new(0, 0, 10, 0, 20, 0)

    assert_equal [0.0, 0.0], curve.control_point(1)
    assert_equal [0.0, 0.0], curve.control_point(0)
    assert_equal [20.0, 0.0], curve.control_point(-1)
    assert_equal [0.0, 0.0], curve.control_point(4)
  end

  # insertControlPoint's default of -1 is the place before the last
  # (wrap_BezierCurve.cpp:83-95, BezierCurve.cpp:139-151).
  def test_a_point_inserted_by_default_goes_before_the_last
    curve = Lota::Math::BezierCurve.new(0, 0, 10, 0)
    curve.insert_control_point(5, 5)
    curve.insert_control_point(-1, -1, 1)

    assert_equal [[-1.0, -1.0], [0.0, 0.0], [5.0, 5.0], [10.0, 0.0]], (1..4).map { |i| curve.control_point(i) }
    assert_nil curve.remove_control_point(1)
    assert_equal 3, curve.control_point_count
  end

  def test_render_defaults_to_lovess_accuracy
    curve = Lota::Math::BezierCurve.new(0, 0, 50, 100, 100, 0)

    assert_equal curve.render(5), curve.render
    assert_equal curve.render_segment(0, 0.5, 5), curve.render_segment(0, 0.5)
    refute_equal curve.render(5), curve.render(3)
  end

  def test_the_curves_engine_errors_reach_ruby
    curve = Lota::Math::BezierCurve.new(0, 0, 10, 10)

    error = assert_raises(RuntimeError) { curve.evaluate(2) }
    assert_equal "Invalid evaluation parameter: must be between 0 and 1", error.message
    error = assert_raises(RuntimeError) { curve.segment(0.5, 0.25) }
    assert_equal "Invalid segment parameters: t1 must be smaller than t2", error.message
    error = assert_raises(RuntimeError) { Lota::Math::BezierCurve.new(1, 1).derivative }
    assert_equal "Cannot derive a curve of degree < 1.", error.message
  end

  # w_triangulate needs three vertices and returns one triangle of three
  # as it is (wrap_Math.cpp:181-190).
  def test_triangulate_needs_three_vertices
    error = assert_raises(RuntimeError) { Lota::Math.triangulate(0, 0, 1, 0) }
    assert_equal "Need at least 3 vertices to triangulate (got 2).", error.message
    assert_equal [[0.0, 0.0, 1.0, 0.0, 0.0, 1.0]], Lota::Math.triangulate(0, 0, 1, 0, 0, 1)
    assert_equal 2, Lota::Math.triangulate([0, 0, 4, 0, 4, 4, 0, 4]).size
  end

  def test_convex_takes_arguments_or_an_array
    assert Lota::Math.convex?(0, 0, 4, 0, 4, 4, 0, 4)
    refute Lota::Math.convex?([0, 0, 4, 0, 1, 1, 0, 4])
    refute Lota::Math.convex?(0, 0, 1, 1)
  end

  # colorToBytes and colorFromBytes clamp, round, and return the alpha
  # only when it is given (wrap_Math.lua:61-81).
  def test_colors_convert_between_bytes_and_fractions
    assert_equal [255, 0, 128], Lota::Math.color_to_bytes(1, 0, 0.5)
    assert_equal [255, 0, 128, 128], Lota::Math.color_to_bytes([2, -1, 0.5, 0.5])
    assert_equal [1.0, 0.0, 1.0], Lota::Math.color_from_bytes(255, -4, 300)
    assert_equal [0.2, 1.0, 0.0, 1.0], Lota::Math.color_from_bytes([51, 255, 0, 255])
    assert_raises(TypeError) { Lota::Math.color_to_bytes(1) }
  end

  # The FFI code of gammaToLinear and linearToGamma clamps red, green, and
  # blue, converts them, and passes alpha on (wrap_Math.lua:153-181);
  # MathModule.cpp:183-199 maps 0 and 1 to themselves.
  def test_gamma_converts_the_colors_and_passes_alpha_on
    assert_equal [0.0, 1.0, 1.0, 0.25], Lota::Math.gamma_to_linear(0, 1, 2, 0.25)
    assert_equal [0.0, 0.0, 0.0, 0.75], Lota::Math.linear_to_gamma([-1, 0, 0, 0.75])
    assert_equal [1.0], Lota::Math.gamma_to_linear(1)
    assert_operator Lota::Math.gamma_to_linear(0.5).first, :<, 0.5
    assert_operator Lota::Math.linear_to_gamma(0.5).first, :>, 0.5
  end

  # The FFI code chooses the dimensions by the last coordinate given
  # (wrap_Math.lua:129-151).
  def test_noise_takes_its_dimensions_from_the_last_coordinate
    assert_equal Lota::Math.simplex_noise(0.3, 0.7), Lota::Math.simplex_noise(0.3, 0.7, nil, nil)
    refute_equal Lota::Math.perlin_noise(0.3, 0.7), Lota::Math.simplex_noise(0.3, 0.7)
    refute_equal Lota::Math.perlin_noise(0.3, 0.7), Lota::Math.perlin_noise(0.3, 0.7, 0.2)
    assert_raises(TypeError) { Lota::Math.perlin_noise(0.3, nil, 0.2) }
  end

  # The deprecated noise prints LÖVE's notice the first time it is used,
  # and takes simplex noise for one and two dimensions and Perlin noise
  # for three and four (wrap_Math.lua:115-127). No other test calls it,
  # so the notice is this test's to see.
  def test_noise_is_deprecated_and_mixes_the_two_noises
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    out, = capture_io { Lota::Math.noise(1) }

    assert_match(/\ALota - Warning: .*math_functions_test\.rb:\d+: Using deprecated function Lota::Math\.noise \(replaced by Lota::Math\.perlin_noise or Lota::Math\.simplex_noise\)\n\z/, out)
    capture_io do
      assert_equal Lota::Math.simplex_noise(0.3), Lota::Math.noise(0.3)
      assert_equal Lota::Math.simplex_noise(0.3, 0.7), Lota::Math.noise(0.3, 0.7)
      assert_equal Lota::Math.perlin_noise(0.3, 0.7, 0.2), Lota::Math.noise(0.3, 0.7, 0.2)
      assert_equal Lota::Math.perlin_noise(0.3, 0.7, 0.2, 0.9), Lota::Math.noise(0.3, 0.7, 0.2, 0.9)
    end
  ensure
    capture_io { Lota::Deprecation.output = output }
  end

  # A generator of its own starts from the seed it is given, as
  # w_newRandomGenerator seeds it (wrap_Math.cpp:52-82), and its seed's
  # halves are Integers (rule 14).
  def test_a_generator_of_its_own_is_seeded_apart_from_the_modules
    Lota::Math.random_seed = 5
    generator = Lota::Math::RandomGenerator.new(5)

    assert_equal [5, 0], generator.seed
    assert_equal Array.new(4) { Lota::Math.random }, Array.new(4) { generator.random }
    assert_equal [0xCBBF7A44, 0x0139408D], Lota::Math::RandomGenerator.new.seed
    assert_equal [1, 2], Lota::Math::RandomGenerator.new(1, 2).seed
    assert_raises(ArgumentError) { Lota::Math::RandomGenerator.new(Float::NAN) }
    assert_raises(TypeError) { Lota::Math::RandomGenerator.new("5") }
  end

  def test_a_generators_state_restores_its_sequence
    generator = Lota::Math::RandomGenerator.new(77)
    generator.random
    state = generator.state
    expected = [generator.random(10), generator.random(3, 9), generator.random_normal(2, 1)]
    generator.state = state

    assert_equal expected, [generator.random(10), generator.random(3, 9), generator.random_normal(2, 1)]
    assert_match(/\A0x\h{16}\z/, Lota::Math.random_state)
    error = assert_raises(RuntimeError) { generator.state = "12" }
    assert_equal "Invalid random state: 12", error.message
    assert_raises(TypeError) { generator.random_normal("1") }
  end
end
