# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# ADR 001, section 5: Ruby's garbage collector frees a wrapper on whichever
# thread triggered the collection, but objects of love.graphics and
# love.window are released only on the main thread. A wrapper of one freed
# elsewhere hands its reference to a queue, which the main thread drains
# (ext/lota/native/binding.hpp, ReleaseQueue).
#
# LotaNativeTest::Confined is a love::Object released on the main thread,
# as a Texture is, in the test-only bundle with its own queue; it records
# which thread destroyed it.
class ReleaseQueueTest < Minitest::Test
  include NativeHelper

  Confined = LotaNativeTest::Confined
  Counted = LotaNativeTest::Counted

  # Garbage earlier tests left behind is freed here, on the main thread,
  # so each test's queue holds only what the test itself freed.
  def setup
    EngineHelper.open_window
    collect_garbage
    Confined.drain_release_queue
    Lota::Native.drain_release_queue
    @generation = Counted.begin_generation
  end

  def teardown
    LotaNativeTest.forget_observed
    LotaNativeTest.drop
  end

  def test_an_object_freed_off_the_main_thread_waits_for_the_main_thread
    collect_garbage_off_the_main_thread { on_a_finished_fiber { Confined.new } }

    assert_equal 1, Confined.queued_releases
    assert_equal 1, Counted.constructions
    assert_equal 0, Counted.destructions

    assert_equal 1, Confined.drain_release_queue
    assert_equal 1, Counted.destructions
    assert_equal 0, Confined.off_main_thread_destructions
    assert_equal 0, Confined.queued_releases
  end

  # A few wrappers can survive the collection (NativeHelper#live_wrappers);
  # every other one waits in the queue, and none is destroyed before the
  # main thread drains it.
  def test_ten_thousand_objects_freed_off_the_main_thread_are_all_released_on_it
    collect_garbage_off_the_main_thread { on_a_finished_fiber { 10_000.times { Confined.new } } }
    freed = 10_000 - live_wrappers(Confined, @generation)

    assert_operator freed, :>, 9_900
    assert_equal freed, Confined.queued_releases
    assert_equal 0, Counted.destructions

    assert_equal freed, Confined.drain_release_queue
    assert_equal freed, Counted.destructions
    assert_equal 0, Confined.off_main_thread_destructions
  end

  def test_an_object_freed_on_the_main_thread_is_released_at_once
    on_a_finished_fiber { Confined.new }
    collect_garbage

    assert_equal 0, Confined.queued_releases
    assert_equal 1, Counted.destructions
  end

  # Only main-thread modules wait: a Counted stands for love.math's
  # RandomGenerator, which LÖVE's threads may use.
  def test_other_objects_are_released_where_they_are_freed
    collect_garbage_off_the_main_thread { on_a_finished_fiber { Counted.new } }

    assert_equal 0, Confined.queued_releases
    assert_equal 1, Counted.destructions
  end

  def test_draining_an_empty_queue_releases_nothing
    assert_equal 0, Confined.drain_release_queue
  end

  def test_a_failed_drain_off_the_main_thread_keeps_the_queue
    collect_garbage_off_the_main_thread { on_a_finished_fiber { Confined.new } }
    drain = Thread.new do
      Thread.current.report_on_exception = false
      Confined.drain_release_queue
    end
    assert_raises(ThreadError) { drain.join }

    assert_equal 1, Confined.queued_releases
    assert_equal 0, Counted.destructions
  end

  # A real Texture, made by Canvas.new: LotaNativeTest observes the
  # engine's Texture, so its reference count shows when Lota::Native lets
  # go of it.
  def test_a_texture_freed_off_the_main_thread_is_released_on_the_main_thread
    collect_garbage_off_the_main_thread do
      on_a_finished_fiber { LotaNativeTest.observe_texture(Lota::Graphics::Canvas.new(16, 16).native) }
      assert_equal [2], LotaNativeTest.observed_reference_counts
    end

    assert_equal 1, Lota::Native.queued_releases
    assert_equal [2], LotaNativeTest.observed_reference_counts

    assert_equal 1, Lota::Native.drain_release_queue
    assert_equal [1], LotaNativeTest.observed_reference_counts
    assert_equal 0, Lota::Native.queued_releases
  end

  # love.image may run on any thread, so its objects need no queue.
  def test_an_image_data_freed_off_the_main_thread_is_released_at_once
    texture = Lota::Graphics::Canvas.new(16, 16)
    collect_garbage_off_the_main_thread do
      on_a_finished_fiber { LotaNativeTest.observe_image_data(Lota::Graphics.readback_texture(texture).native) }
    end

    assert_equal 0, Lota::Native.queued_releases
    assert_equal [1], LotaNativeTest.observed_reference_counts
  end
end
