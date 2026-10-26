# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Native::Graphics.capture_screenshot, which the parity harness reads
# each frame with (test/parity/probe.rb): the next present hands the frame
# it shows to the callable, as love.graphics.captureScreenshot's function
# form does.
class CaptureScreenshotTest < Minitest::Test
  include NativeHelper

  def setup
    EngineHelper.open_window
  end

  def test_the_next_present_hands_its_frame_to_the_callable
    frames = []
    Lota::Native::Graphics.capture_screenshot(-> (image) { frames << image })
    Lota::Graphics.clear(1, 0, 0)
    Lota::Graphics.present
    image = Lota::Image::ImageData.from_native(frames.fetch(0))

    assert_equal 1, frames.size
    assert_instance_of Lota::Native::ImageData, frames.first
    assert_equal [1.0, 0.0, 0.0, 1.0], image.pixel(0, 0)
    assert_equal [1.0, 0.0, 0.0, 1.0], image.pixel(image.width - 1, image.height - 1)
  end

  def test_only_the_next_present_captures
    count = 0
    Lota::Native::Graphics.capture_screenshot(-> (_image) { count += 1 })
    Lota::Graphics.present
    Lota::Graphics.present

    assert_equal 1, count
  end

  # The engine holds the callable until the frame, though Ruby does not.
  def test_the_callable_outlives_every_reference_ruby_had_to_it
    captured = []
    on_a_finished_fiber { Lota::Native::Graphics.capture_screenshot(-> (image) { captured << image.width }) }
    collect_garbage
    Lota::Graphics.present

    assert_equal 1, captured.size
  end

  # LÖVE releases the frame once the callback returns; the wrapper Ruby
  # holds keeps its own reference.
  def test_the_frame_outlives_the_present
    frames = []
    Lota::Native::Graphics.capture_screenshot(-> (image) { frames << image })
    Lota::Graphics.clear(0, 0, 1)
    Lota::Graphics.present
    collect_garbage

    assert_equal [0.0, 0.0, 1.0, 1.0], Lota::Image::ImageData.from_native(frames.fetch(0)).pixel(1, 1)
  end

  def test_an_error_in_the_callable_is_raised_by_present_once_the_frame_is_shown
    later = []
    Lota::Native::Graphics.capture_screenshot(-> (_image) { raise "broken capture" })
    Lota::Native::Graphics.capture_screenshot(-> (image) { later << image })

    error = assert_raises(RuntimeError) { Lota::Graphics.present }
    assert_equal "broken capture", error.message
    assert_equal 1, later.size
    Lota::Graphics.present
  end
end
