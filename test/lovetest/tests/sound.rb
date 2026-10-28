# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.sound tests (vendor/love/testing/tests/sound.lua),
# translated to Ruby by ADR 001's rules. They run in the test suite's own
# process (test/lovetest/sound_test.rb) and under lota run
# (test/lovetest/game), also from the installed precompiled gem.
class SoundTest < Lovetest::TestMethod
  TYPES = %w[Decoder SoundData].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.sound.Decoder
  # (vendor/love/testing/tests/sound.lua:12-39): newDecoder becomes
  # Decoder.new (rule 2), its getters drop get (rule 3), clone keeps its
  # name, as Ruby's clone makes LÖVE's copy (ADR 001, section 7), and Lövetest's
  # assertMatch, which looks for the value in a list, and assertRange,
  # which asks whether it lies in a range (classes/TestMethod.lua:126-163),
  # become Minitest's assert_includes of the list and of the Range.
  def test_decoder
    # create obj
    decoder = Lota::Sound::Decoder.new("resources/click.ogg")
    assert_object(decoder)

    # check bit depth
    assert_includes([8, 16], decoder.bit_depth, "check bit depth")

    # check channel count
    assert_includes([1, 2], decoder.channel_count, "check channel count")

    # check duration
    assert_includes(0.06..0.07, decoder.duration, "check duration")

    # check sample rate
    assert_equal(44100, decoder.sample_rate, "check sample rate")

    # check makes sound data (test in method below)
    assert_object(decoder.decode)

    # check cloning sound
    clone = decoder.clone
    assert_includes([8, 16], clone.bit_depth, "check cloned bit depth")
    assert_includes([1, 2], clone.channel_count, "check cloned channel count")
    assert_includes(0.06..0.07, clone.duration, "check cloned duration")
    assert_equal(44100, clone.sample_rate, "check cloned sample rate")
  end

  # Translated to Ruby from love.test.sound.SoundData (sound.lua:43-94):
  # newSoundData becomes SoundData.new (rule 2), getSample sample
  # (rule 3), setSample the writer sample=, which takes its several values
  # as an Array (rule 6), copyFrom copy_from (rule 13), and clone keeps
  # its name, as in love.test.sound.Decoder. Lua's
  # math.floor becomes Integer division, and assertNotEquals
  # (classes/TestMethod.lua:114-123) Minitest's refute_equal.
  def test_sound_data
    # create obj
    sdata = Lota::Sound::SoundData.new("resources/click.ogg")
    assert_object(sdata)

    # check data size + string
    assert_equal(11708, sdata.size, "check size")
    assert_not_nil(sdata.string)

    # check bit depth
    assert_includes([8, 16], sdata.bit_depth, "check bit depth")

    # check channel count
    assert_includes([1, 2], sdata.channel_count, "check channel count")

    # check duration
    assert_includes(0.06..0.07, sdata.duration, "check duration")

    # check samples
    assert_equal(44100, sdata.sample_rate, "check sample rate")
    assert_equal(2927, sdata.sample_count, "check sample count")

    # check cloning
    clone = sdata.clone
    assert_equal(11708, clone.size, "check clone size")
    assert_not_nil(clone.string)
    assert_includes([8, 16], clone.bit_depth, "check clone bit depth")
    assert_includes([1, 2], clone.channel_count, "check clone channel count")
    assert_includes(0.06..0.07, clone.duration, "check clone duration")
    assert_equal(44100, clone.sample_rate, "check clone sample rate")
    assert_equal(2927, clone.sample_count, "check clone sample count")

    # check sample setting
    assert_includes(-0.1..0, sdata.sample(0.001), "check sample 1")
    assert_includes(-0.1..0, sdata.sample(0.005), "check sample 1")
    sdata.sample = 0.002, 1
    assert_equal(1, sdata.sample(0.002), "check setting sample manually")

    # check copying from another sound
    copy1 = Lota::Sound::SoundData.new("resources/tone.ogg")
    copy2 = Lota::Sound::SoundData.new("resources/pop.ogg")
    before = copy2.sample(0.02)
    copy2.copy_from(copy1, 0.01, 1, 0.02)
    refute_equal(before, copy2.sample(0.02), "check changed")

    # check slicing
    count = copy1.sample_count / 2
    slice = copy1.slice(0, count)
    assert_equal(count, slice.sample_count, "check slice length")
  end

  # Translated to Ruby from love.test.sound.newDecoder (sound.lua:109-111).
  def test_new_decoder
    assert_object(Lota::Sound::Decoder.new("resources/click.ogg"))
  end

  # Translated to Ruby from love.test.sound.newSoundData
  # (sound.lua:116-119): Lua's math.floor becomes Float#floor.
  def test_new_sound_data
    assert_object(Lota::Sound::SoundData.new("resources/click.ogg"))
    assert_object(Lota::Sound::SoundData.new(((1.0 / 32) * 44100).floor, 44100, 16, 1))
  end
  # SPDX-SnippetEnd
end
