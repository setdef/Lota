# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.math tests (vendor/love/testing/tests/math.lua),
# translated to Ruby by the rules of doc/contributors/design/translation.md,
# every one of them. Like the graphics tests, they run in the test suite's own
# process (test/lovetest/math_test.rb) and under lota run (test/lovetest/game).
class MathTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type (love.test.math.Transform).
  TYPES = %w[BezierCurve RandomGenerator Transform].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.math.random
  # (vendor/love/testing/tests/math.lua:336-342): setRandomSeed becomes the
  # writer random_seed= (rule 5), and random keeps its name (rule 13).
  # Lövetest's assertRange (classes/TestMethod.lua:126-140) asserts that a
  # value lies within a range, as Minitest's assert_includes does for a
  # Range.
  def test_random
    # check some random ranges
    Lota::Math.random_seed = 123
    assert_includes(0.37068322251462..0.37068322251464, Lota::Math.random, "check random algorithm")
    assert_equal(4, Lota::Math.random(10), "check single random param")
    assert_equal(92, Lota::Math.random(15, 100), "check two random params")
  end

  # Translated to Ruby from love.test.math.Transform
  # (vendor/love/testing/tests/math.lua:111-176): newTransform becomes Transform.new (rule 2), setTransformation and
  # setMatrix the writers transformation= and matrix=, taking their
  # values as one Array (doc/contributors/design/translation.md), getMatrix
  # matrix (rule 3), whose sixteen results are an Array (rule 4), and the rest
  # snake_case (rule 13). clone is Ruby's clone, which makes LÖVE's copy.
  # Lövetest's assertCoords (classes/TestMethod.lua:228-245) compares two pairs
  # of numbers, as assert_coords does. isAffine2DTransform becomes
  # affine2d_transform? (rules 8 and 13), its acronym and digit one word.
  def test_transform
    # create obj
    transform = Lota::Math::Transform.new(0, 0, 0, 1, 1, 0, 0, 0, 0)
    assert_object(transform)

    # set some values and check the matrix and transformPoint values
    transform.translate(10, 8)
    transform.scale(2, 3)
    transform.rotate(90 * (Math::PI / 180))
    transform.shear(1, 2)
    px, py = transform.transform_point(1, 1)
    assert_coords([4, 14], [px, py], "check transformation methods")
    transform.reset
    px, py = transform.transform_point(1, 1)
    assert_coords([1, 1], [px, py], "check reset")

    # apply a transform to another transform
    transform2 = Lota::Math::Transform.new
    transform2.translate(5, 3)
    transform.apply(transform2)
    px, py = transform.transform_point(1, 1)
    assert_coords([6, 4], [px, py], "check apply other transform")

    # check cloning a transform
    transform3 = transform.clone
    px, py = transform3.transform_point(1, 1)
    assert_coords([6, 4], [px, py], "check clone transform")

    # check inverse and inverseTransform
    transform.reset
    transform.translate(-14, 6)
    ipx, ipy = transform.inverse_transform_point(0, 0)
    transform.inverse
    px, py = transform.transform_point(0, 0)
    assert_coords([-px, -py], [ipx, ipy], "check inverse points transform")

    # check inverse and inverseOf produce same values
    transform.reset
    transform.transformation = 4, 4, Math::PI / 2, 2, 2
    inverse_clone = transform.inverse
    inverse_destination_transform = Lota::Math::Transform.new
    inverse_destination_transform.inverse_of(transform)
    opx1, opy1 = inverse_clone.transform_point(0, 0)
    opx2, opy2 = inverse_destination_transform.transform_point(0, 0)
    assert_coords([opx1, opy1], [opx2, opy2], "check inverse and inverseOf produce same values")

    # check matrix manipulation
    transform.transformation = 0, 0, 0, 1, 1, 0, 0, 0, 0
    transform.translate(4, 4)
    m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16 = transform.matrix
    assert_equal(4, m4, "check translate matrix x")
    assert_equal(4, m8, "check translate matrix y")
    transform.matrix = m1, m2, m3, 3, m5, m6, m7, 1, m9, m10, m11, m12, m13, m14, m15, m16
    px, py = transform.transform_point(1, 1)
    assert_coords([4, 2], [px, py], "check set matrix")

    # check affine vs non affine
    transform.reset
    assert_true(transform.affine2d_transform?, "check affine 1")
    transform.translate(4, 3)
    assert_true(transform.affine2d_transform?, "check affine 2")
    transform.matrix = 1, 3, 4, 5.5, 1, 4.5, 2, 1, 3.4, 5.1, 4.1, 13, 1, 1, 2, 3
    assert_false(transform.affine2d_transform?, "check not affine")
  end

  # Translated to Ruby from love.test.math.newTransform
  # (vendor/love/testing/tests/math.lua:299-301): newTransform becomes
  # Transform.new (rule 2).
  def test_new_transform
    assert_object(Lota::Math::Transform.new)
  end

  # Translated to Ruby from love.test.math.BezierCurve
  # (vendor/love/testing/tests/math.lua:12-76): newBezierCurve becomes
  # BezierCurve.new (rule 2), getControlPoint control_point,
  # getControlPointCount control_point_count, and getDegree degree (rule
  # 3), whose two results, as evaluate's, are an Array (rule 4);
  # getDerivative and getSegment become derivative and segment (rule 3),
  # setControlPoint the writer control_point= of its three values (rule
  # 6), and the rest snake_case (rule 13). Where Lua passes evaluate's
  # results on as one argument, it passes the first, the x, which .first
  # takes in Ruby, and Lua's # of a table is an Array's size. Lua's
  # math.pi is Ruby's Math::PI.
  def test_bezier_curve
    # create obj
    curve = Lota::Math::BezierCurve.new(1, 1, 2, 2, 3, 1)
    px, py = curve.control_point(2)
    assert_object(curve)

    # check initial properties
    assert_coords([2, 2], [px, py], "check point x/y")
    assert_equal(3, curve.control_point_count, "check 3 points")
    assert_equal(2, curve.degree, "check degree is points-1")

    # check some values on the curve
    assert_equal(1, curve.evaluate(0).first, "check curve evaluation 0")
    assert_includes(1.2..1.3, curve.evaluate(0.1).first, "check curve evaluation 0.1")
    assert_includes(1.4..1.5, curve.evaluate(0.2).first, "check curve evaluation 0.2")
    assert_includes(2..2.1, curve.evaluate(0.5).first, "check curve evaluation 0.5")
    assert_equal(3, curve.evaluate(1).first, "check curve evaluation 1")

    # check derivative
    deriv = curve.derivative
    assert_object(deriv)
    assert_equal(2, deriv.control_point_count, "check deriv points")
    assert_includes(2..2.1, deriv.evaluate(0.1).first, "check deriv evaluation 0.1")

    # check segment
    segment = curve.segment(0, 0.5)
    assert_object(segment)
    assert_equal(3, segment.control_point_count, "check segment points")
    assert_includes(1..1.1, segment.evaluate(0.1).first, "check segment evaluation 0.1")

    # mess with control points
    curve.remove_control_point(2)
    curve.insert_control_point(4, 1, -1)
    curve.insert_control_point(5, 3, -1)
    curve.insert_control_point(6, 2, -1)
    curve.control_point = 2, 3, 2
    assert_equal(5, curve.control_point_count, "check 3 points still")
    px1, py1 = curve.control_point(1)
    px2, py2 = curve.control_point(3)
    px3, py3 = curve.control_point(5)
    assert_coords([1, 1], [px1, py1], "check modified point 1")
    assert_coords([5, 3], [px2, py2], "check modified point 1")
    assert_coords([3, 1], [px3, py3], "check modified point 1")

    # check render lists
    coords1 = curve.render(5)
    coords2 = curve.render_segment(0, 0.1, 5)
    assert_equal(196, coords1.size, "check coords")
    assert_equal(20, coords2.size, "check segment coords")

    # check translation values
    px, py = curve.control_point(2)
    assert_coords([3, 2], [px, py], "check pretransform x/y")
    curve.rotate(90 * (Math::PI / 180), 0, 0)
    px, py = curve.control_point(2)
    assert_coords([-2, 3], [px, py], "check rotated x/y")
    curve.scale(2, 0, 0)
    px, py = curve.control_point(2)
    assert_coords([-4, 6], [px, py], "check scaled x/y")
    curve.translate(5, -5)
    px, py = curve.control_point(2)
    assert_coords([1, 1], [px, py], "check translated x/y")
  end

  # Translated to Ruby from love.test.math.RandomGenerator
  # (vendor/love/testing/tests/math.lua:82-107): newRandomGenerator
  # becomes RandomGenerator.new (rule 2), getSeed and getState seed and
  # state (rule 3), the seed's two halves an Array (rule 4), setSeed and
  # setState the writers seed= and state= (rule 5), and randomNormal
  # random_normal (rule 13). Lua's os.time, the seconds since the epoch, is
  # Ruby's Time.now.to_i.
  def test_random_generator
    # create object
    rng1 = Lota::Math::RandomGenerator.new(3_418_323_524, 20_529_293)
    assert_object(rng1)

    # check set properties
    low, high = rng1.seed
    assert_equal(3_418_323_524, low, "check seed low")
    assert_equal(20_529_293, high, "check seed high")

    # check states
    rng2 = Lota::Math::RandomGenerator.new(1_448_323_524, 10_329_293)
    refute_equal(rng1.random, rng2.random, "check not matching states")
    refute_equal(rng1.random_normal, rng2.random_normal, "check not matching states")

    # check setting state works
    rng2.state = rng1.state
    assert_equal(rng1.random, rng2.random, "check now matching")

    # check overwriting seed works, should change output
    rng1.seed = Time.now.to_i
    refute_equal(rng1.random, rng2.random, "check not matching states")
    refute_equal(rng1.random_normal, rng2.random_normal, "check not matching states")
  end

  # Translated to Ruby from love.test.math.colorFromBytes
  # (vendor/love/testing/tests/math.lua:188-207): colorFromBytes becomes
  # color_from_bytes (rule 13), whose four results are an Array (rule 4).
  def test_color_from_bytes
    # check random value
    r1, g1, b1, a1 = Lota::Math.color_from_bytes(51, 51, 51, 51)
    assert_equal(r1, 0.2, "check r from bytes")
    assert_equal(g1, 0.2, "check g from bytes")
    assert_equal(b1, 0.2, "check b from bytes")
    assert_equal(a1, 0.2, "check a from bytes")
    # check "max" value
    r2, g2, b2, a2 = Lota::Math.color_from_bytes(255, 255, 255, 255)
    assert_equal(r2, 1, "check r from bytes")
    assert_equal(g2, 1, "check g from bytes")
    assert_equal(b2, 1, "check b from bytes")
    assert_equal(a2, 1, "check a from bytes")
    # check "min" value
    r3, g3, b3, a3 = Lota::Math.color_from_bytes(0, 0, 0, 0)
    assert_equal(r3, 0, "check r from bytes")
    assert_equal(g3, 0, "check g from bytes")
    assert_equal(b3, 0, "check b from bytes")
    assert_equal(a3, 0, "check a from bytes")
  end

  # Translated to Ruby from love.test.math.colorToBytes
  # (vendor/love/testing/tests/math.lua:211-230): colorToBytes becomes
  # color_to_bytes (rule 13), whose four results are an Array (rule 4).
  def test_color_to_bytes
    # check random value
    r1, g1, b1, a1 = Lota::Math.color_to_bytes(0.2, 0.2, 0.2, 0.2)
    assert_equal(r1, 51, "check bytes from r")
    assert_equal(g1, 51, "check bytes from g")
    assert_equal(b1, 51, "check bytes from b")
    assert_equal(a1, 51, "check bytes from a")
    # check "max" value
    r2, g2, b2, a2 = Lota::Math.color_to_bytes(1, 1, 1, 1)
    assert_equal(r2, 255, "check bytes from r")
    assert_equal(g2, 255, "check bytes from g")
    assert_equal(b2, 255, "check bytes from b")
    assert_equal(a2, 255, "check bytes from a")
    # check "min" value
    r3, g3, b3, a3 = Lota::Math.color_to_bytes(0, 0, 0, 0)
    assert_equal(r3, 0, "check bytes from r")
    assert_equal(g3, 0, "check bytes from g")
    assert_equal(b3, 0, "check bytes from b")
    assert_equal(a3, 0, "check bytes from a")
  end

  # Translated to Ruby from love.test.math.gammaToLinear
  # (vendor/love/testing/tests/math.lua:236-243): gammaToLinear becomes
  # gamma_to_linear (rule 13), whose results are an Array (rule 4), and
  # assertGreaterEqual(0, n), which checks that n is at least 0,
  # assert_operator(n, :>=, 0), as tests/joystick.rb has it.
  def test_gamma_to_linear
    lr, lg, lb = Lota::Math.gamma_to_linear(1, 0.8, 0.02)
    # local eg = ((0.8 + 0.055) / 1.055)^2.4
    # local eb = 0.02 / 12.92
    assert_operator(lr, :>=, 0, "check gamma r to linear")
    assert_operator(lg, :>=, 0, "check gamma g to linear")
    assert_operator(lb, :>=, 0, "check gamma b to linear")
  end

  # Translated to Ruby from love.test.math.getRandomSeed
  # (vendor/love/testing/tests/math.lua:248-252): getRandomSeed becomes
  # random_seed (rule 3), whose two results are an Array (rule 4).
  def test_get_random_seed
    low, high = Lota::Math.random_seed
    assert_operator(low, :>=, 0, "check random seed low")
    assert_operator(high, :>=, 0, "check random seed high")
  end

  # Translated to Ruby from love.test.math.getRandomState
  # (vendor/love/testing/tests/math.lua:256-258): getRandomState becomes
  # random_state (rule 3).
  def test_get_random_state
    assert_not_nil(Lota::Math.random_state)
  end

  # Translated to Ruby from love.test.math.isConvex
  # (vendor/love/testing/tests/math.lua:262-267): isConvex becomes convex?
  # (rule 8), and its table an Array.
  def test_is_convex
    isconvex = Lota::Math.convex?([0, 0, 1, 0, 1, 1, 1, 0, 0, 0]) # square
    notconvex = Lota::Math.convex?([1, 2, 2, 4, 3, 4, 2, 1, 3, 1]) # weird shape
    assert_true(isconvex, "check polygon convex")
    assert_false(notconvex, "check polygon not convex")
  end

  # Translated to Ruby from love.test.math.linearToGamma
  # (vendor/love/testing/tests/math.lua:273-280): linearToGamma becomes
  # linear_to_gamma (rule 13), as test_gamma_to_linear translates its
  # inverse.
  def test_linear_to_gamma
    gr, gg, gb = Lota::Math.linear_to_gamma(1, 0.8, 0.001)
    # local eg = 1.055 * (0.8^1/2.4) - 0.055
    # local eb = 0.001 * 12.92
    assert_operator(gr, :>=, 0, "check linear r to gamme")
    assert_operator(gg, :>=, 0, "check linear g to gamme")
    assert_operator(gb, :>=, 0, "check linear b to gamme")
  end

  # Translated to Ruby from love.test.math.newBezierCurve
  # (vendor/love/testing/tests/math.lua:285-287): newBezierCurve becomes
  # BezierCurve.new (rule 2), and its table an Array.
  def test_new_bezier_curve
    assert_object(Lota::Math::BezierCurve.new([0, 0, 0, 1, 1, 1, 2, 1]))
  end

  # Translated to Ruby from love.test.math.newRandomGenerator
  # (vendor/love/testing/tests/math.lua:292-294): newRandomGenerator
  # becomes RandomGenerator.new (rule 2).
  def test_new_random_generator
    assert_object(Lota::Math::RandomGenerator.new)
  end

  # Translated to Ruby from love.test.math.perlinNoise
  # (vendor/love/testing/tests/math.lua:305-316): perlinNoise becomes
  # perlin_noise (rule 13).
  def test_perlin_noise
    # check some noise values
    # output should be consistent if given the same input
    noise1 = Lota::Math.perlin_noise(100)
    noise2 = Lota::Math.perlin_noise(1, 10)
    noise3 = Lota::Math.perlin_noise(1043, 31.123, 999)
    noise4 = Lota::Math.perlin_noise(99.222, 10_067, 8, 1843)
    assert_includes(0.5..0.51, noise1, "check noise 1 dimension")
    assert_includes(0.5..0.51, noise2, "check noise 2 dimensions")
    assert_includes(0.56..0.57, noise3, "check noise 3 dimensions")
    assert_includes(0.52..0.53, noise4, "check noise 4 dimensions")
  end

  # Translated to Ruby from love.test.math.simplexNoise
  # (vendor/love/testing/tests/math.lua:320-332): simplexNoise becomes
  # simplex_noise (rule 13).
  def test_simplex_noise
    # check some noise values
    # output should be consistent if given the same input
    noise1 = Lota::Math.simplex_noise(100)
    noise2 = Lota::Math.simplex_noise(1, 10)
    noise3 = Lota::Math.simplex_noise(1043, 31.123, 999)
    noise4 = Lota::Math.simplex_noise(99.222, 10_067, 8, 1843)
    # rounded to avoid floating point issues
    assert_includes(0.5..0.51, noise1, "check noise 1 dimension")
    assert_includes(0.47..0.48, noise2, "check noise 2 dimensions")
    assert_includes(0.26..0.27, noise3, "check noise 3 dimensions")
    assert_includes(0.53..0.54, noise4, "check noise 4 dimensions")
  end

  # Translated to Ruby from love.test.math.randomNormal
  # (vendor/love/testing/tests/math.lua:346-349): setRandomSeed becomes
  # the writer random_seed= (rule 5), and randomNormal random_normal (rule
  # 13).
  def test_random_normal
    Lota::Math.random_seed = 1234
    assert_includes(1.0813614997253..1.0813614997255, Lota::Math.random_normal(1, 2),
      "check randomNormal two params")
  end

  # Translated to Ruby from love.test.math.setRandomSeed
  # (vendor/love/testing/tests/math.lua:354-359): setRandomSeed becomes
  # the writer random_seed= (rule 5), and getRandomSeed random_seed (rule
  # 3), whose two results are an Array (rule 4).
  def test_set_random_seed
    Lota::Math.random_seed = 9001
    low, high = Lota::Math.random_seed
    assert_equal(9001, low, "check seed low set")
    assert_equal(0, high, "check seed high set")
  end

  # Translated to Ruby from love.test.math.setRandomState
  # (vendor/love/testing/tests/math.lua:363-369): getRandomState becomes
  # random_state (rule 3), and setRandomState the writer random_state=
  # (rule 5).
  def test_set_random_state
    # check setting state matches value returned
    rs1 = Lota::Math.random_state
    Lota::Math.random_state = rs1
    rs2 = Lota::Math.random_state
    assert_equal(rs1, rs2, "check random state set")
  end

  # Translated to Ruby from love.test.math.triangulate
  # (vendor/love/testing/tests/math.lua:373-378): its table is an Array,
  # as is the table of triangles it returns, whose # is the Array's size.
  def test_triangulate
    triangles1 = Lota::Math.triangulate([0, 0, 1, 0, 1, 1, 1, 0, 0, 0]) # square
    triangles2 = Lota::Math.triangulate([1, 2, 2, 4, 3, 4, 2, 1, 3, 1]) # weird shape
    assert_equal(3, triangles1.size, "check polygon triangles")
    assert_equal(3, triangles2.size, "check polygon triangles")
  end
  # SPDX-SnippetEnd
end
