# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# Lota::Native::RandomGenerator binds love::math::RandomGenerator
# (vendor/love/src/modules/math/RandomGenerator.h) as its C++ defines it.
class RandomGeneratorTest < Minitest::Test
  RandomGenerator = Lota::Native::RandomGenerator

  def test_it_binds_the_engine_class
    assert_equal "love::math::RandomGenerator", RandomGenerator.cpp_class
  end

  def test_random_is_in_the_unit_interval
    generator = RandomGenerator.new
    values = Array.new(1000) { generator.random }

    assert(values.all? { |value| value.is_a?(Float) && value >= 0.0 && value < 1.0 })
    assert_operator values.uniq.size, :>, 990
  end

  # LÖVE seeds every new generator with the same constant
  # (RandomGenerator.cpp, the constructor).
  def test_new_generators_start_from_the_same_seed
    first = RandomGenerator.new
    second = RandomGenerator.new

    assert_equal Array.new(5) { first.random }, Array.new(5) { second.random }
  end

  def test_state_restores_the_sequence
    generator = RandomGenerator.new
    generator.random
    state = generator.state
    expected = Array.new(5) { generator.random }

    generator.state = state
    assert_equal state, generator.state
    assert_equal expected, Array.new(5) { generator.random }
  end

  def test_state_is_a_hex_string
    generator = RandomGenerator.new
    generator.state = "0x10"

    assert_equal "0x0000000000000010", generator.state
  end

  def test_an_invalid_state_raises_the_engine_error
    error = assert_raises(RuntimeError) { RandomGenerator.new.state = "bad" }
    assert_equal "Invalid random state: bad", error.message
  end

  def test_random_normal_scales_by_its_standard_deviation
    generator = RandomGenerator.new
    generator.state = "0x1234"
    unit = generator.random_normal(1.0)
    generator.state = "0x1234"

    assert_equal unit * 2.0, generator.random_normal(2.0)
  end
end
