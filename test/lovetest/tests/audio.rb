# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.audio tests (vendor/love/testing/tests/audio.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds.
# They run in the test suite's own process (test/lovetest/audio_test.rb),
# whose OpenAL Soft plays into a wave file, as Lövetest's does on LÖVE's CI
# (test/alsoft.conf), and under lota run (test/lovetest/game), also from
# the installed precompiled gem, which carries OpenAL Soft
# (ext/lota/licenses.rb). The rest call functions Lota does not bind yet,
# such as love.audio.pause.
class AudioTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.audio.getVolume and
  # love.test.audio.setVolume (vendor/love/testing/tests/audio.lua:347-351
  # and 520-524): setVolume becomes the writer volume= (rule 5), and
  # getVolume volume (rule 3).
  def test_get_volume
    # check getting values matches what was set
    Lota::Audio.volume = 0.5
    assert_equal(0.5, Lota::Audio.volume, "check matches set")
  end

  def test_set_volume
    # check setting volume works
    Lota::Audio.volume = 0.5
    assert_equal(0.5, Lota::Audio.volume, "check set to 0.5")
  end

  # Translated to Ruby from love.test.audio.newSource (audio.lua:369-372):
  # newSource becomes Source.new (rule 2), and the source type a symbol
  # (rule 9).
  def test_new_source
    assert_object(Lota::Audio::Source.new("resources/click.ogg", :static))
    assert_object(Lota::Audio::Source.new("resources/click.ogg", :stream))
  end

  # Translated to Ruby from love.test.audio.play and love.test.audio.stop
  # (audio.lua:390-396 and 528-536): isPlaying becomes playing? (rule 8).
  def test_play
    # check playing source is detected
    source = Lota::Audio::Source.new("resources/click.ogg", :static)
    Lota::Audio.play(source)
    assert_true(source.playing?, "check something playing")
    Lota::Audio.stop
  end

  def test_stop
    # check source is playing first
    source = Lota::Audio::Source.new("resources/click.ogg", :static)
    Lota::Audio.play(source)
    assert_true(source.playing?, "check is playing")
    # check source is then stopped
    Lota::Audio.stop
    assert_false(source.playing?, "check stopped playing")
  end
  # SPDX-SnippetEnd
end
