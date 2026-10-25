# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# The memory rule (ADR 001, section 5; ext/lota/native/binding.hpp): a
# Ruby wrapper retains its engine object when created and releases it when
# Ruby's garbage collector frees the wrapper. LotaNativeTest::Counted is a
# love::Object that counts its own constructions and destructions.
class MemoryTest < Minitest::Test
  include NativeHelper

  Counted = LotaNativeTest::Counted

  # Each test counts only the Counted objects it makes.
  def setup
    Counted.begin_generation
  end

  def teardown
    LotaNativeTest.drop
  end

  def live
    Counted.constructions - Counted.destructions
  end

  def test_a_million_dropped_wrappers_free_a_million_objects
    on_a_finished_thread { 1_000_000.times { Counted.new } }
    collect_garbage

    assert_equal 1_000_000, Counted.constructions
    assert_equal 1_000_000, Counted.destructions
  end

  def test_a_constructed_wrapper_adopts_the_only_reference
    counted = Counted.new

    assert_equal 1, counted.reference_count
  end

  def test_an_object_lives_while_its_wrapper_does
    counted = Counted.new
    collect_garbage

    assert_equal 1, live
    assert_equal 1, counted.reference_count
  end

  # C++ holds a new Counted that no Ruby wrapper does.
  def hold_new_counted
    on_a_finished_thread { LotaNativeTest.hold(Counted.new) }
    collect_garbage
  end

  def test_wrapping_a_pointer_cpp_keeps_retains_it_until_collected
    hold_new_counted
    assert_equal 1, LotaNativeTest.held_reference_count

    on_a_finished_thread do
      wrappers = Array.new(1000) { LotaNativeTest.held }
      assert_equal 1001, LotaNativeTest.held_reference_count
      assert_equal 1001, wrappers.last.reference_count
    end
    collect_garbage
    assert_equal 1, LotaNativeTest.held_reference_count
  end

  def test_wrapping_a_reference_cpp_keeps_retains_it_until_collected
    hold_new_counted
    on_a_finished_thread do
      wrappers = Array.new(10) { LotaNativeTest.held_reference }
      assert_equal 11, LotaNativeTest.held_reference_count
      assert_equal 11, wrappers.last.reference_count
    end
    collect_garbage
    assert_equal 1, LotaNativeTest.held_reference_count
  end

  def test_cpp_can_outlive_the_wrapper_that_created_the_object
    hold_new_counted

    assert_equal 1, LotaNativeTest.held_reference_count
    assert_equal 1, live

    LotaNativeTest.drop
    assert_equal 0, live
  end

  def test_a_random_generator_is_retained_while_ruby_holds_it_and_released_after_gc
    on_a_finished_thread do
      generator = Lota::Native::RandomGenerator.new
      LotaNativeTest.hold_random_generator(generator)
      assert_equal 2, LotaNativeTest.held_reference_count
    end

    collect_garbage
    assert_equal 1, LotaNativeTest.held_reference_count
  end

  def test_holding_a_random_generator_needs_one
    error = assert_raises(ArgumentError) { LotaNativeTest.hold_random_generator(Object.new) }
    assert_equal "expected a Lota::Native::RandomGenerator", error.message
  end
end
