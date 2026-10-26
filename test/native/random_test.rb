# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Math, beyond what Lövetest's tests for it check
# (test/lovetest/tests/math.rb): random draws from the math module's own
# generator, as love.math.random does (src/modules/math/wrap_Math.lua:
# 37-47), with getrandom's ranges (wrap_RandomGenerator.lua:33-44), and
# random_seed= seeds it as RandomGenerator:setSeed does
# (wrap_RandomGenerator.cpp:49-62 and 88-93).
class RandomTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def test_the_math_module_is_open_once_lota_boots
    assert_equal Lota::Math, Lota.math
  end

  # The module's generator is the one random draws from: seeding it
  # directly starts the sequence random continues.
  def test_random_draws_from_the_math_modules_generator
    Lota::Math.random_seed = 42
    expected = Array.new(3) { Lota::Math.random }

    Lota::Native::Math.random_generator.set_seed(42)
    assert_equal expected, Array.new(3) { Lota::Native::Math.random_generator.random }
  end

  def test_the_same_seed_gives_the_same_numbers
    Lota::Math.random_seed = 7
    first = Array.new(10) { Lota::Math.random(1, 6) }
    Lota::Math.random_seed = 7

    assert_equal first, Array.new(10) { Lota::Math.random(1, 6) }
  end

  # getrandom computes a whole number from the generator's Float with
  # floor (wrap_RandomGenerator.lua:33-44), which in Ruby is an Integer,
  # and each lies within its bounds; random alone is the Float itself.
  def test_random_with_whole_bounds_returns_integers_within_them
    Lota::Math.random_seed = 1
    unit = Array.new(200) { Lota::Math.random }
    single = Array.new(200) { Lota::Math.random(6) }
    double = Array.new(200) { Lota::Math.random(-20, 20) }

    assert(unit.all? { |r| r.is_a?(Float) && r >= 0 && r < 1 })
    assert(single.all? { |r| r.is_a?(Integer) && r.between?(1, 6) })
    assert(double.all? { |r| r.is_a?(Integer) && r.between?(-20, 20) })
    assert_equal (1..6).to_a, single.uniq.sort
  end

  # getrandom adds the lower bound to floor(r * (max - min + 1)), so a
  # bound that is not whole moves every number by its fraction, and the
  # sum is a Float.
  def test_a_lower_bound_that_is_not_whole_is_added_as_it_is
    Lota::Math.random_seed = 3
    r = Lota::Native::Math.random_generator.random
    Lota::Math.random_seed = 3
    number = Lota::Math.random(1.5, 3.5)

    assert_instance_of Float, number
    assert_equal (r * (3.5 - 1.5 + 1)).floor + 1.5, number
  end

  def test_a_bound_must_be_a_number
    assert_raises(TypeError) { Lota::Math.random("6") }
    assert_raises(TypeError) { Lota::Math.random(nil, 6) }
  end

  # luax_checkrandomseed takes two numbers as the low and high halves of
  # the 64-bit seed, and one number as the whole seed, so a seed below
  # 2**32 is the same seed as its low half with a high half of 0.
  def test_a_seed_may_be_given_as_its_two_halves
    Lota::Math.random_seed = 9001
    whole = Array.new(3) { Lota::Math.random }
    Lota::Math.random_seed = 9001, 0
    halves = Array.new(3) { Lota::Math.random }
    Lota::Math.random_seed = 9001, 1

    assert_equal whole, halves
    refute_equal whole, Array.new(3) { Lota::Math.random }
  end

  # LÖVE casts a seed to an integer, so its fraction is dropped.
  def test_a_seed_is_truncated_to_a_whole_number
    Lota::Math.random_seed = 5
    whole = Lota::Math.random
    Lota::Math.random_seed = 5.75

    assert_equal whole, Lota::Math.random
  end

  def test_an_infinite_or_nan_seed_raises_loves_error
    infinite = assert_raises(ArgumentError) { Lota::Math.random_seed = Float::INFINITY }
    nan = assert_raises(ArgumentError) { Lota::Math.random_seed = [1, Float::NAN] }

    assert_equal "invalid random seed", infinite.message
    assert_equal "invalid random seed", nan.message
  end

  def test_a_seed_must_be_a_number
    assert_raises(TypeError) { Lota::Math.random_seed = "1" }
    assert_raises(TypeError) { Lota::Math.random_seed = [] }
  end
end
