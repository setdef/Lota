# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics.capture_screenshot, and the native call beneath it, which
# the parity harness reads each frame with (test/parity/probe.rb): the
# next present hands the frame it shows to the callable, or saves it to
# the file, as love.graphics.captureScreenshot's function and string forms
# do. Lövetest's own captureScreenshot test compares the frame with what
# its love.draw shows, so it waits for a port of that screen.
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

  # Lota::Graphics.capture_screenshot takes what LÖVE keeps to call once
  # the frame is presented as a block or any object that answers call
  # (ADR 001, rule 12), and hands it a Lota::Image::ImageData.
  def test_a_block_receives_the_frame_as_image_data
    frames = []
    Lota::Graphics.capture_screenshot { |image_data| frames << image_data }
    Lota::Graphics.clear(0, 1, 0)
    Lota::Graphics.present

    assert_instance_of Lota::Image::ImageData, frames.fetch(0)
    assert_equal [0.0, 1.0, 0.0, 1.0], frames.fetch(0).pixel(0, 0)
  end

  # Anything that answers call, as Signal.trap takes, not only a Proc.
  class Recorder
    attr_reader :frames

    def initialize
      @frames = []
    end

    def call(image_data)
      @frames << image_data
    end
  end

  def test_any_object_that_answers_call_receives_the_frame
    recorder = Recorder.new
    Lota::Graphics.capture_screenshot(recorder)
    Lota::Graphics.present

    assert_instance_of Lota::Image::ImageData, recorder.frames.fetch(0)
  end

  # w_captureScreenshot's string form (wrap_Graphics.cpp:519-540): the
  # frame is saved in the save directory, in the format the extension
  # names, once it is presented.
  def test_a_file_name_saves_the_frame_in_the_save_directory_once_presented
    in_identity("lota-screenshot-test") do
      Lota::Graphics.capture_screenshot("shot.PNG")
      assert_nil Lota::Filesystem.info("shot.PNG")
      Lota::Graphics.present

      contents, = Lota::Filesystem.read("shot.PNG")
      assert_equal "\x89PNG".b, contents.byteslice(0, 4).b
      Lota::Filesystem.remove("shot.PNG")
    end
  end

  def test_an_extension_the_engine_cannot_encode_is_refused_before_the_frame
    error = assert_raises(ArgumentError) { Lota::Graphics.capture_screenshot("shot.jpg") }

    assert_match(/\AInvalid encoded image format 'jpg', expected one of: /, error.message)
  end

  def test_a_target_and_a_block_together_or_neither_are_refused
    assert_raises(ArgumentError) { Lota::Graphics.capture_screenshot("shot.png") { nil } }
    assert_raises(TypeError) { Lota::Graphics.capture_screenshot(3) }
    assert_raises(TypeError) { Lota::Graphics.capture_screenshot }
  end

  private def in_identity(identity)
    previous = Lota::Filesystem.identity
    Lota::Filesystem.identity = identity
    yield
  ensure
    Lota::Filesystem.identity = previous
  end
end
