# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# The forms of love.audio.newSource (src/modules/audio/wrap_Audio.cpp:
# 47-102), Source's positional methods and seek (wrap_Source.cpp), and the
# listener's, beyond what Lövetest's tests for them check
# (test/lovetest/tests/audio.rb): sources from memory, LÖVE's type rules,
# and the errors LÖVE raises.
class AudioSourceTest < Minitest::Test
  Source = Lota::Audio::Source

  def setup
    EngineHelper.open_window
  end

  def click_data
    Lota::Filesystem::FileData.new(File.binread(File.join(Lovetest::RESOURCES, "clickmono.ogg")), "clickmono.ogg")
  end

  def test_a_sound_data_plays_as_a_static_source_with_its_samples
    data = Lota::Sound::SoundData.new(4410, 44_100, 16, 1)
    source = Source.new(data)

    assert_equal [:static, 1, 4410.0], [source.get_type, source.channel_count, source.duration(:samples)]
  end

  def test_a_decoder_streams_whatever_type_is_given
    decoder = Lota::Sound::Decoder.new("resources/clickmono.ogg")

    assert_equal :stream, Source.new(decoder).get_type
    assert_equal :stream, Source.new(Lota::Sound::Decoder.new("resources/clickmono.ogg"), :static).get_type
  end

  def test_file_data_makes_a_source_of_either_type
    static = Source.new(click_data, :static)
    stream = Source.new(click_data, :stream)

    assert_equal [:static, 2927.0], [static.get_type, static.duration(:samples)]
    assert_equal [:stream, 1], [stream.get_type, stream.channel_count]
  end

  def test_a_stream_reads_its_file_as_its_stream_type_says
    assert_equal :stream, Source.new("resources/clickmono.ogg", :stream, :memory).get_type
    assert_raises(ArgumentError) { Source.new("resources/clickmono.ogg", :stream, :tape) }
  end

  def test_a_file_needs_a_type_that_love_knows
    assert_raises(TypeError) { Source.new("resources/clickmono.ogg") }
    unknown = assert_raises(ArgumentError) { Source.new("resources/clickmono.ogg", :loud) }
    queue = assert_raises(RuntimeError) { Source.new("resources/clickmono.ogg", :queue) }

    assert_equal "Invalid source type 'loud', expected one of: 'static', 'stream', 'queue'", unknown.message
    assert_match(/\ACannot create queueable sources using Lota::Audio::Source\.new/, queue.message)
  end

  def test_anything_else_is_not_a_source
    error = assert_raises(TypeError) { Source.new(42, :static) }

    assert_equal "wrong argument type Integer (expected Lota::Sound::Decoder or Lota::Sound::SoundData)", error.message
  end

  def test_seek_and_tell_in_samples
    source = Source.new("resources/clickmono.ogg", :static)
    source.seek(441, :samples)

    assert_equal 441.0, source.tell(:samples)
    assert_in_delta 0.01, source.tell, 1e-6
  end

  def test_seek_refuses_a_negative_position_and_unknown_units
    source = Source.new("resources/clickmono.ogg", :static)
    negative = assert_raises(ArgumentError) { source.seek(-1) }

    assert_equal "can't seek to a negative position", negative.message
    assert_raises(ArgumentError) { source.seek(1, :beats) }
    assert_raises(ArgumentError) { source.tell(:beats) }
    assert_raises(ArgumentError) { source.duration(:beats) }
  end

  # LÖVE places only a mono Source in space (audio/openal/Source.cpp).
  def test_a_stereo_source_has_no_place_in_space
    stereo = Source.new("resources/click.ogg", :static)

    assert_raises(RuntimeError) { stereo.position = 1, 2, 3 }
    assert_raises(RuntimeError) { stereo.relative = true }
  end

  def test_a_position_left_without_z_is_at_zero
    mono = Source.new("resources/clickmono.ogg", :static)
    mono.position = 4, 5
    Lota::Audio.position = 1, 2

    assert_equal [4.0, 5.0, 0.0], mono.position
    assert_equal [1.0, 2.0, 0.0], Lota::Audio.position
    assert_raises(TypeError) { mono.position = 4 }
  end

  def test_attenuation_distances_and_rolloff_refuse_negatives
    mono = Source.new("resources/clickmono.ogg", :static)
    mono.attenuation_distances = 10, 100

    assert_equal [10.0, 100.0], mono.attenuation_distances
    assert_raises(RuntimeError) { mono.attenuation_distances = -1, 100 }
    assert_raises(RuntimeError) { mono.rolloff = -1 }
    assert_raises(RuntimeError) { mono.volume_limits = 2, 3 }
  end

  def test_an_unknown_distance_model_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Audio.distance_model = :far }

    assert_match(/\AInvalid distance model 'far', expected one of: /, error.message)
  ensure
    Lota::Audio.distance_model = :inverseclamped
  end

  def test_orientation_needs_six_numbers
    assert_raises(TypeError) { Lota::Audio.orientation = 1, 2, 3 }
  end
end
