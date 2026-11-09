# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Video::VideoStream and Lota::Graphics::Video beyond what
# Lövetest's tests for them check (test/lovetest/tests/video.rb and
# graphics.rb): a stream made from a File, the errors of a file that is
# missing or holds no Theora video, the three things a stream keeps time
# by (wrap_VideoStream.cpp:35-60), a Video's settings and Source
# (wrap_Graphics.lua:30-52 and wrap_Video.lua:28-31), and a Video drawn
# placed by a Transform.
class VideoPlaybackTest < Minitest::Test
  SAMPLE = "resources/sample.ogv"

  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def test_a_stream_reads_a_file_it_opens_for_reading
    file, = Lota::Filesystem.open_file(SAMPLE, :c)
    stream = Lota::Video::VideoStream.new(file)

    assert_equal SAMPLE, stream.filename
    assert_predicate file, :open?
    assert_equal :r, file.mode.first
  end

  def test_a_stream_needs_a_theora_file_by_name_or_a_file
    assert_match(%r{\ACould not open file resources/missing\.ogv},
      assert_raises(RuntimeError) { Lota::Video::VideoStream.new("resources/missing.ogv") }.message)
    assert_equal "Invalid video file, video is not theora",
      assert_raises(RuntimeError) { Lota::Video::VideoStream.new("resources/click.ogg") }.message
    assert_equal "wrong argument type Integer (expected String or Lota::Filesystem::File)",
      assert_raises(TypeError) { Lota::Video::VideoStream.new(3) }.message
  end

  def test_a_stream_keeps_time_by_a_source_another_stream_or_its_own_clock
    stream = Lota::Video::VideoStream.new(SAMPLE)
    source = Lota::Audio::Source.new(SAMPLE, :stream)
    stream.sync = source
    stream.seek(0.5)

    assert_in_delta 0.5, source.tell, 0.05
    assert_in_delta source.tell, stream.tell, 1e-9

    other = Lota::Video::VideoStream.new(SAMPLE)
    other.sync = stream
    assert_in_delta stream.tell, other.tell, 1e-9

    stream.sync = nil
    source.seek(0)
    assert_in_delta 0.5, stream.tell, 0.05
    refute_predicate stream, :playing?
    assert_equal "wrong argument type Integer (expected Lota::Audio::Source, Lota::Video::VideoStream, or nil)",
      assert_raises(TypeError) { stream.sync = 3 }.message
  end

  def test_a_video_plays_its_files_sound_unless_told_not_to
    assert_kind_of Lota::Audio::Source, Lota::Graphics::Video.new(SAMPLE).source
    assert_nil Lota::Graphics::Video.new(SAMPLE, audio: false).source
  end

  def test_a_video_is_its_frames_size_over_its_dpi_scale
    video = Lota::Graphics::Video.new(SAMPLE, audio: false, dpiscale: 2)

    assert_equal [248, 251], video.dimensions
    assert_equal [496, 502], video.pixel_dimensions
    assert_equal 496, video.pixel_width
    assert_equal 502, video.pixel_height
  end

  def test_a_video_draws_the_stream_it_is_given
    stream = Lota::Video::VideoStream.new(SAMPLE)
    video = Lota::Graphics::Video.new(stream, audio: false)

    assert_same stream, video.stream
    assert_same video.stream, video.stream
  end

  def test_a_video_without_its_source_keeps_time_on_its_own_clock
    video = Lota::Graphics::Video.new(SAMPLE)
    video.seek(0.5)
    video.source = nil

    assert_nil video.source
    assert_in_delta 0.5, video.tell, 0.05
    video.seek(1)
    assert_in_delta 1.0, video.tell, 1e-9
    assert_equal "wrong argument type Integer (expected Lota::Audio::Source)",
      assert_raises(TypeError) { video.source = 3 }.message
  end

  def test_a_video_drawn_by_a_transform_is_drawn_as_by_its_numbers
    video = Lota::Graphics::Video.new(SAMPLE, audio: false)
    by_numbers = drawn { Lota::Graphics.draw(video, 2, 3) }
    by_transform = drawn { Lota::Graphics.draw(video, Lota::Math::Transform.new(2, 3)) }

    [[0, 0], [2, 3], [100, 120], [40, 400]].each do |x, y|
      assert_equal by_numbers.pixel(x, y), by_transform.pixel(x, y), "#{x}, #{y}"
    end
    refute_equal [1.0, 0.0, 0.0, 1.0], by_numbers.pixel(100, 120)
  end

  # What +block+ draws on a red canvas the size of the sample, read back.
  def drawn
    canvas = Lota::Graphics::Canvas.new(500, 510)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(1, 0, 0, 1)
    yield
    Lota::Graphics.canvas = nil
    Lota::Graphics.readback_texture(canvas)
  end
end
