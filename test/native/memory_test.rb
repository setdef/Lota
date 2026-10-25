# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The memory rule (ADR 001, section 5; ext/lota/native/binding.hpp): a
# Ruby wrapper retains its engine object when created and releases it when
# Ruby's garbage collector frees the wrapper. LotaNativeTest::Counted is a
# love::Object that counts its own constructions and destructions.
class MemoryTest < Minitest::Test
  include NativeHelper

  Counted = LotaNativeTest::Counted

  # Each test counts only the Counted objects it makes.
  def setup
    @generation = Counted.begin_generation
  end

  def teardown
    LotaNativeTest.drop
    LotaNativeTest.forget_observed
  end

  def live
    Counted.constructions - Counted.destructions
  end

  # Every object the collector freed the wrapper of is destroyed, and every
  # object not destroyed still has its wrapper (NativeHelper#live_wrappers):
  # a leak would leave objects with no wrapper, and a double release would
  # destroy objects whose wrappers live. Each survivor needs a stale word of
  # its own on some thread's stack, so there are only ever a few.
  def test_a_million_dropped_wrappers_free_a_million_objects
    on_a_finished_thread { 1_000_000.times { Counted.new } }
    collect_garbage
    survivors = live_wrappers(Counted, @generation)

    assert_equal 1_000_000, Counted.constructions
    assert_equal 1_000_000 - survivors, Counted.destructions
    assert_operator survivors, :<, 100
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

  PNG = File.binread(File.join(ROOT, "vendor/love/testing/output/expected/love.test.graphics.clear-1.png"))

  # LotaNativeTest observes each object; once Ruby frees the wrappers, the
  # observer's reference is the only one left.
  def assert_released_once_collected(count)
    yield
    assert_equal [2] * count, LotaNativeTest.observed_reference_counts
    collect_garbage

    assert_equal [1] * count, LotaNativeTest.observed_reference_counts
  end

  def test_a_thousand_dropped_canvases_release_their_textures
    EngineHelper.open_window
    assert_released_once_collected(1000) do
      on_a_finished_fiber { 1000.times { LotaNativeTest.observe_texture(Lota::Graphics::Canvas.new(4, 4).native) } }
    end
  end

  def test_the_active_canvas_is_also_held_by_the_engine
    EngineHelper.open_window
    on_a_finished_fiber do
      canvas = Lota::Graphics::Canvas.new(4, 4)
      LotaNativeTest.observe_texture(canvas.native)
      Lota::Graphics.canvas = canvas
    end
    collect_garbage
    assert_equal [2], LotaNativeTest.observed_reference_counts

    Lota::Graphics.canvas = nil
    assert_equal [1], LotaNativeTest.observed_reference_counts
  end

  def test_dropped_image_data_read_back_from_a_canvas_is_released
    EngineHelper.open_window
    canvas = Lota::Graphics::Canvas.new(4, 4)
    assert_released_once_collected(100) do
      on_a_finished_fiber do
        100.times { LotaNativeTest.observe_image_data(Lota::Graphics.readback_texture(canvas).native) }
      end
    end
  end

  def test_dropped_decoded_image_data_and_file_data_are_released
    Lota::Native::Image.open
    assert_released_once_collected(200) do
      on_a_finished_thread do
        100.times do
          file_data = Lota::Filesystem::FileData.new(PNG, "clear-1.png")
          LotaNativeTest.observe_file_data(file_data.native)
          LotaNativeTest.observe_image_data(Lota::Image::ImageData.new(file_data).native)
        end
      end
    end
  end

  def test_observing_needs_the_named_class
    error = assert_raises(ArgumentError) { LotaNativeTest.observe_texture(Lota::Native::RandomGenerator.new) }
    assert_equal "expected a Lota::Native::Texture", error.message
  end
end
