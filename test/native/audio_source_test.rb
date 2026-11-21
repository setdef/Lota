# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    Lota::Filesystem.new_file_data(File.binread(File.join(Lovetest::RESOURCES, "clickmono.ogg")), "clickmono.ogg").first
  end

  def test_a_sound_data_plays_as_a_static_source_with_its_samples
    data = Lota::Sound::SoundData.new(4410, 44_100, 16, 1)
    source = Source.new(data)

    assert_equal [:static, 1, 4410.0], [source.get_type, source.channel_count, source.duration(:samples)]
  end

  # OpenAL Soft here plays into the wave file writer (test/alsoft.conf),
  # which cannot record. LÖVE lists one device named "" that cannot start
  # (openal/Audio.cpp:573-593); its own comment says the list is empty
  # then, and Lota's is (doc/contributors/upstream/009.md).
  def test_a_computer_that_cannot_record_lists_no_recording_device
    assert_equal [], Lota::Audio.recording_devices
  end

  # w_RecordingDevice_start (wrap_RecordingDevice.cpp:44-50) reads
  # samples with luaL_checkinteger once it is given any argument, so an
  # explicit nil raises where no arguments at all record as before. No
  # machine here can record, so the device has no engine object behind it:
  # start must refuse before it asks the engine for anything.
  def test_recording_needs_its_samples_once_any_setting_is_given
    device = Lota::Audio::RecordingDevice.__send__(:from_native, nil)

    error = assert_raises(TypeError) { device.start(nil, 44_100) }
    assert_equal "wrong argument type NilClass for samples (expected Integer)", error.message
    assert_raises(TypeError) { device.start(nil) }
    assert_raises(TypeError) { device.start("all", 44_100) }
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

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib

  # w_newSource makes a Decoder of anything luax_cangetdata takes, a File
  # and any Data among them (src/modules/audio/wrap_Audio.cpp:63-79).
  def test_a_file_or_any_data_makes_a_source_of_either_type
    file, = Lota::Filesystem.open_file("resources/clickmono.ogg", :c)
    bytes = Lota::Data::ByteData.new(click_data.string)

    assert_equal [:static, 2927.0], [Source.new(file, :static).get_type, Source.new(bytes, :static).duration(:samples)]
    assert_equal :stream, Source.new(bytes, :stream).get_type
  end

  # SPDX-SnippetEnd

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

  # A looping Source stays playing for as long as a test looks at it.
  def looping_sources(count)
    Array.new(count) do
      Source.new(Lota::Sound::SoundData.new(44_100, 44_100, 16, 1), :static).tap { |source| source.looping = true }
    end
  end

  # w_play, w_stop, and w_pause take one Source, several, or a table of them
  # (wrap_Audio.cpp:119-208).
  def test_several_sources_play_stop_and_pause_together
    first, second = looping_sources(2)

    assert Lota::Audio.play(first, second)
    assert_predicate first, :playing?
    assert_predicate second, :playing?
    assert_nil Lota::Audio.pause(first, second)
    refute_predicate first, :playing?
    refute_predicate second, :playing?
    assert Lota::Audio.play(first, second)
    assert_nil Lota::Audio.stop(first, second)
    refute_predicate first, :playing?
    refute_predicate second, :playing?
  end

  def test_an_array_of_sources_plays_stops_and_pauses_as_a_table_does
    first, second = looping_sources(2)

    assert Lota::Audio.play([first, second])
    assert_predicate second, :playing?
    assert_nil Lota::Audio.pause([first, second])
    refute_predicate first, :playing?
    assert Lota::Audio.play([first, second])
    assert_nil Lota::Audio.stop([first, second])
    refute_predicate second, :playing?
  end

  def test_a_list_of_sources_holds_only_sources
    first, = looping_sources(1)

    assert_equal "wrong argument type Symbol (expected Lota::Audio::Source)",
      assert_raises(TypeError) { Lota::Audio.play(first, :second) }.message
    assert_raises(TypeError) { Lota::Audio.play([first, :second]) }
    assert_raises(TypeError) { Lota::Audio.stop(first, 1) }
    assert_raises(TypeError) { Lota::Audio.pause([first, nil]) }
    assert_raises(TypeError) { Lota::Audio.play(:first) }
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

  # w_Source_setRelative reads its flag with luax_checkboolean
  # (wrap_Source.cpp:236-241, src/common/runtime.cpp:259-263), which
  # raises for anything but true or false, nil included.
  def test_relative_takes_only_true_or_false
    mono = Source.new("resources/clickmono.ogg", :static)
    mono.relative = true

    [nil, 0, "no"].each do |enable|
      error = assert_raises(TypeError) { mono.relative = enable }

      assert_equal "wrong argument type #{enable.class} (expected true or false)", error.message
    end
    assert_predicate mono, :relative?
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

  # w_Source_setEffect (wrap_Source.cpp:470-492) takes a boolean at
  # argument 3 as on or off, and anything else but nil only as a filter's
  # table, which setFilterReadFilter checks with luaL_checktype
  # (lines 356-361); Lota's table is keywords (rule 10).
  def test_set_effect_takes_true_false_or_a_filters_keywords
    mono = Source.new("resources/clickmono.ogg", :static)

    [5, "on", { type: :lowpass }].each do |enabled|
      error = assert_raises(TypeError) { mono.set_effect("echo", enabled) }
      assert_equal "wrong argument type #{enabled.class} (expected true or false)", error.message
    end
    assert_empty mono.active_effects
  end

  # w_Source_queue (wrap_Source.cpp:540-585) reads the length, or the
  # offset and length, with luaL_checknumber when given them, so nil
  # raises, and refuses anything but a SoundData with luax_typerror.
  def test_queue_takes_a_sound_data_and_numbers_for_its_region
    synth = Lota::Audio::QueueableSource.new(44_100, 16, 1)
    data = Lota::Sound::SoundData.new(1024, 44_100, 16, 1)

    error = assert_raises(TypeError) { synth.queue("samples") }
    assert_equal "wrong argument type String (expected Lota::Sound::SoundData)", error.message
    error = assert_raises(TypeError) { synth.queue(data, nil) }
    assert_equal "wrong argument type NilClass (expected Float or Integer)", error.message
    assert_raises(TypeError) { synth.queue(data, 0, nil) }
    assert_raises(TypeError) { synth.queue(data, "0", 16) }
    assert synth.queue(data, 16)
  end

  def test_orientation_needs_six_numbers
    assert_raises(TypeError) { Lota::Audio.orientation = 1, 2, 3 }
  end
end
