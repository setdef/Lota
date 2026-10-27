# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# Lota::Sound::SoundData and Lota::Sound::Decoder, beyond what Lövetest's
# tests for them check (test/lovetest/tests/sound.rb): the samples LÖVE
# stores and reads, as its LuaJIT code reads and writes them
# (src/modules/sound/wrap_SoundData.lua), the forms of newSoundData and
# newDecoder (wrap_Sound.cpp), and the errors LÖVE raises. The test
# process boots test/lovetest, whose resources/ links to Lövetest's.
class SoundDataTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def silence(bit_depth, channels = 1, samples = 2)
    Lota::Sound::SoundData.new(samples, 44_100, bit_depth, channels)
  end

  # SoundData::load fills new samples with silence: 0 when signed, 128
  # when unsigned 8-bit (SoundData.cpp).
  def test_silence_is_zero_or_the_middle_of_an_unsigned_byte
    assert_equal "\0\0\0\0".b, silence(16).string.b
    assert_equal "\x80\x80".b, silence(8).string.b
    assert_equal [0.0, 0.0], [silence(16).sample(1), silence(8).sample(1)]
  end

  # LÖVE's LuaJIT code multiplies and divides in double precision, where
  # its C++ SoundData::getSample divides in a float: 0.5 is stored as
  # 16383, which reads back as 16383 / 32767.0, not as the float nearest.
  def test_a_sample_is_stored_and_read_as_luajit_does
    sound = silence(16)
    sound.sample = 0, 0.5
    sound.sample = 1, -0.5

    assert_equal [16_383, -16_383], sound.string.unpack("s<2")
    assert_equal 16_383 / 32_767.0, sound.sample(0)
    refute_equal [16_383 / 32_767.0].pack("e").unpack1("e"), sound.sample(0)
    assert_equal(-16_383 / 32_767.0, sound.sample(1))
  end

  # An 8-bit sample is 127 times the value, plus 128, made a float and
  # then a byte, and reads back as the byte less 128, over 127.
  def test_an_eight_bit_sample_is_stored_and_read_as_luajit_does
    sound = silence(8)
    sound.sample = 0, 0.5

    assert_equal 191, sound.string.getbyte(0)
    assert_equal 63 / 127.0, sound.sample(0)
  end

  # LuaJIT keeps the low 16 bits of a sample too large for them.
  def test_a_sample_out_of_range_wraps_as_luajit_stores_it
    sound = silence(16)
    sound.sample = 0, 2

    assert_equal(-2, sound.string.unpack1("s<"))
  end

  # With a channel, a position is a sample frame's, and the channel picks
  # its sample; without, it counts every channel's samples in turn.
  def test_a_channel_picks_a_sample_of_the_frame
    sound = silence(16, 2)
    sound.sample = 1, 2, 1.0

    assert_equal [0, 0, 0, 32_767], sound.string.unpack("s<4")
    assert_equal 1.0, sound.sample(1, 2)
    assert_equal 1.0, sound.sample(3)
    assert_equal 1.0, sound.sample(1.9, 2)
  end

  def test_a_sample_outside_the_sound_or_its_channels_is_an_error
    sound = silence(16, 2)

    assert_equal "Attempt to get out-of-range sample!", assert_raises(RuntimeError) { sound.sample(4) }.message
    assert_equal "Attempt to get out-of-range sample!", assert_raises(RuntimeError) { sound.sample(-1) }.message
    assert_equal "Attempt to set out-of-range sample!", assert_raises(RuntimeError) { sound.sample = 4, 0 }.message
    assert_equal "Attempt to get sample from out-of-range channel!",
      assert_raises(RuntimeError) { sound.sample(0, 3) }.message
    assert_equal "Attempt to set sample from out-of-range channel!",
      assert_raises(RuntimeError) { sound.sample = 0, 0, 1 }.message
    assert_raises(ArgumentError) { sound.sample = [0] }
  end

  def test_a_bad_format_is_an_error
    assert_equal "Invalid bit depth: 24", assert_raises(RuntimeError) { silence(24) }.message
    assert_equal "Invalid sample count: 0", assert_raises(RuntimeError) { silence(16, 1, 0) }.message
  end

  # w_newDecoder reads a filename's file as it decodes, or all of it first
  # with "memory", and a FileData from memory; each decodes the same
  # samples, and decode gives nil once there are no more.
  def test_a_decoder_decodes_a_file_or_its_bytes_alike
    from_file = Lota::Sound::Decoder.new("resources/click.ogg")
    from_memory = Lota::Sound::Decoder.new("resources/click.ogg", 16_384, :memory)
    from_data = Lota::Sound::Decoder.new(Lovetest.resource("click.ogg"))
    samples = [from_file, from_memory, from_data].map do |decoder|
      pieces = []
      while (piece = decoder.decode)
        pieces << piece.string.b
      end
      pieces.join
    end

    assert_equal 1, samples.uniq.size
    assert_equal Lota::Sound::SoundData.new("resources/click.ogg").string.b, samples.first
    assert_nil from_file.decode
  end

  # w_newSoundData with a Decoder decodes what it has left.
  def test_sound_data_from_a_decoder_takes_what_is_left
    decoder = Lota::Sound::Decoder.new("resources/tone.ogg", 4096)
    first = decoder.decode
    rest = Lota::Sound::SoundData.new(decoder)

    assert_equal Lota::Sound::SoundData.new("resources/tone.ogg").sample_count, first.sample_count + rest.sample_count
  end

  def test_an_unknown_stream_type_is_an_error_with_lovees_message
    error = assert_raises(ArgumentError) { Lota::Sound::Decoder.new("resources/click.ogg", 16_384, :disk) }

    assert_equal "Invalid stream type 'disk', expected one of: 'memory', 'file'", error.message
  end

  def test_a_file_no_decoder_reads_is_an_error
    error = assert_raises(RuntimeError) { Lota::Sound::SoundData.new(Lovetest.resource("love.png")) }

    assert_match(/\ANo suitable audio decoders found\./, error.message)
  end

  # Data:getString takes an offset and a size, and refuses bytes outside.
  def test_string_takes_part_of_the_samples
    sound = silence(16, 1, 4)
    sound.sample = 1, 1

    assert_equal "\xFF\x7F".b, sound.string(2, 2).b
    assert_equal 6, sound.string(2).bytesize
    assert_equal "The given offset and size parameters don't fit within the Data's size.",
      assert_raises(RuntimeError) { sound.string(6, 4) }.message
  end

  # SoundData:copyFrom copies sample frames between SoundData of one
  # channel count, converting their bit depth, and slice copies some out.
  def test_samples_copy_between_sound_data_and_slice_out
    loud = silence(16, 1, 4)
    loud.sample = 2, 1
    quiet = silence(8, 1, 4)
    quiet.copy_from(loud, 2, 1, 0)

    assert_equal 255, quiet.string.getbyte(0)
    assert_equal [32_767, 0], loud.slice(2).string.unpack("s<2")
    assert_equal "Channel count mismatch!",
      assert_raises(RuntimeError) { silence(16, 2).copy_from(loud, 0, 1) }.message
  end

  def test_both_are_lovees_types
    sound = silence(16)

    assert_equal "SoundData", sound.type
    assert sound.type_of?("Data")
    assert_equal "Decoder", Lota::Sound::Decoder.new("resources/click.ogg").type
  end
end
