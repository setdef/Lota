# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.math tests (vendor/love/testing/tests/math.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/math_test.rb) and under lota run (test/lovetest/game).
# setRandomSeed's test reads the seed back with getRandomSeed, which Lota
# does not bind yet, so it waits for it.
class MathTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type (love.test.math.Transform).
  TYPES = %w[Transform].freeze

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
  # values as one Array (ADR 001, section 7), getMatrix matrix (rule 3),
  # whose sixteen results are an Array (rule 4), and the rest snake_case
  # (rule 13). clone is Ruby's clone, which makes LÖVE's copy. Lövetest's
  # assertCoords (classes/TestMethod.lua:228-245) compares two pairs of
  # numbers, as assert_coords does. isAffine2DTransform becomes
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
  # SPDX-SnippetEnd
end
