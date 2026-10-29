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
  # The types whose tests Lövetest names by the type (love.test.audio.Source).
  TYPES = %w[Source].freeze

  # Lövetest runs a module's tests in the order of their names
  # (classes/TestModule.lua:68-71), so getDistanceModel, which checks the
  # default model, runs before setDistanceModel, which leaves the last
  # model set. Minitest runs them in random order, so each test here starts
  # with the default model, as its Lua does.
  def setup
    super
    Lota::Audio.distance_model = :inverseclamped if Lota.audio
  end

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

  # Translated to Ruby from love.test.audio.Source
  # (vendor/love/testing/tests/audio.lua:58-200), all but its queueable
  # source, filter, and effect (lines 153-193), whose newQueueableSource,
  # setFilter, and setEffect wait for the rest of story 4: newSource
  # becomes Source.new (rule 2) with its type a symbol (rule 9), as are
  # its units; the getters drop get (rule 3), and isPlaying, isLooping,
  # and isRelative become playing?, looping?, and relative? (rule 8);
  # setters of one value become writers (rule 5) and of several writers of
  # an Array (rule 6), whose getters return Arrays (rule 4); and
  # love.audio.stop with a Source Lota::Audio.stop. Lua's math.pi and
  # math.floor are Ruby's Math::PI and floor; assertRange becomes
  # assert_includes of a Range, as test_random in tests/math.rb has it.
  def test_source
    # create stereo source
    stereo = Lota::Audio::Source.new("resources/click.ogg", :static)
    assert_object(stereo)

    # check stereo props
    assert_equal(2, stereo.channel_count, "check stereo src")
    assert_includes(0..0.1, stereo.duration(:seconds), "check stereo seconds")
    assert_not_nil(stereo.free_buffer_count)
    assert_equal(:static, stereo.get_type, "check stereo type")

    # check cloning a stereo
    clone = stereo.clone
    assert_equal(2, clone.channel_count, "check clone stereo src")
    assert_includes(0..0.1, clone.duration(:seconds), "check clone stereo seconds")
    assert_not_nil(clone.free_buffer_count)
    assert_equal(:static, clone.get_type, "check cloned stereo type")

    # mess with stereo playing
    assert_false(stereo.playing?, "check not playing")
    stereo.looping = true
    stereo.play
    assert_true(stereo.playing?, "check now playing")
    assert_true(stereo.looping?, "check now playing")
    stereo.pause
    stereo.seek(0.01, :seconds)
    assert_equal(0.01, stereo.tell(:seconds), "check seek/tell")
    stereo.stop
    assert_false(stereo.playing?, "check stopped playing")

    # check volume limits
    stereo.volume_limits = 0.1, 5.5
    min, max = stereo.volume_limits
    assert_includes(0.1..0.2, min, "check min limit")
    assert_includes(5.5..5.6, max, "check max limit")

    # check setting volume
    stereo.volume = 1
    assert_equal(1, stereo.volume, "check set volume")
    stereo.volume = 0
    assert_equal(0, stereo.volume, "check set volume")

    # change some get/set props that can apply to stereo
    stereo.pitch = 2
    assert_equal(2, stereo.pitch, "check pitch change")

    # create mono source
    mono = Lota::Audio::Source.new("resources/clickmono.ogg", :stream)
    assert_object(mono)
    assert_equal(1, mono.channel_count, "check mono src")
    assert_equal(2927, mono.duration(:samples), "check mono seconds")
    assert_equal(:stream, mono.get_type, "check mono type")

    # air absorption
    assert_equal(0, mono.air_absorption, "get air absorption")
    mono.air_absorption = 1
    assert_equal(1, mono.air_absorption, "set air absorption")

    # cone
    mono.cone = 0, 90 * (Math::PI / 180), 1
    ia, oa, ov = mono.cone
    assert_equal(0, ia, "check cone ia")
    assert_equal((9000 * (Math::PI / 180)).floor, (oa * 100).floor, "check cone oa")
    assert_equal(1, ov, "check cone ov")

    # direction
    mono.direction = 3, 1, -1
    x, y, z = mono.direction
    assert_equal(3, x, "check direction x")
    assert_equal(1, y, "check direction y")
    assert_equal(-1, z, "check direction z")

    # relative
    mono.relative = true
    assert_true(mono.relative?, "check set relative")

    # position
    mono.position = 1, 2, 3
    x, y, z = mono.position
    assert_equal(x, 1, "check pos x")
    assert_equal(y, 2, "check pos y")
    assert_equal(z, 3, "check pos z")

    # velocity
    mono.velocity = 1, 3, 4
    x, y, z = mono.velocity
    assert_equal(x, 1, "check velocity x")
    assert_equal(y, 3, "check velocity x")
    assert_equal(z, 4, "check velocity x")

    # rolloff
    mono.rolloff = 1
    assert_equal(1, mono.rolloff, "check rolloff set")

    Lota::Audio.stop(stereo)
    Lota::Audio.stop(mono)
  end

  # Translated to Ruby from love.test.audio.getDistanceModel
  # (vendor/love/testing/tests/audio.lua:235-243): getDistanceModel
  # becomes distance_model (rule 3) and setDistanceModel the writer
  # distance_model= (rule 5), each model a symbol (rule 9).
  def test_get_distance_model
    # check we get a value
    assert_not_nil(Lota::Audio.distance_model)
    # check default value from documentation
    assert_equal(:inverseclamped, Lota::Audio.distance_model, "check default value")
    # check get correct value after setting
    Lota::Audio.distance_model = :inverse
    assert_equal(:inverse, Lota::Audio.distance_model, "check setting model")
  end

  # Translated to Ruby from love.test.audio.getDopplerScale and
  # love.test.audio.setDopplerScale (audio.lua:247-254 and 415-421):
  # getDopplerScale becomes doppler_scale (rule 3), and setDopplerScale
  # the writer doppler_scale= (rule 5).
  def test_get_doppler_scale
    # check default value
    assert_equal(1, Lota::Audio.doppler_scale, "check default 1")
    # check correct value after setting to 0
    Lota::Audio.doppler_scale = 0
    assert_equal(0, Lota::Audio.doppler_scale, "check setting to 0")
    Lota::Audio.doppler_scale = 1
  end

  def test_set_doppler_scale
    # check setting value is returned properly
    Lota::Audio.doppler_scale = 0
    assert_equal(0, Lota::Audio.doppler_scale, "check set to 0")
    Lota::Audio.doppler_scale = 1
    assert_equal(1, Lota::Audio.doppler_scale, "check set to 1")
  end

  # Translated to Ruby from love.test.audio.getOrientation and
  # love.test.audio.setOrientation (audio.lua:289-299 and 446-456):
  # setOrientation becomes the writer orientation= of six values (rule 6),
  # and getOrientation orientation (rule 3), whose six values come back as
  # an Array (rule 4).
  def test_get_orientation
    # checking getting values matches what was set
    Lota::Audio.orientation = 1, 2, 3, 4, 5, 6
    fx, fy, fz, ux, uy, uz = Lota::Audio.orientation
    assert_equal(1, fx, "check fx orientation")
    assert_equal(2, fy, "check fy orientation")
    assert_equal(3, fz, "check fz orientation")
    assert_equal(4, ux, "check ux orientation")
    assert_equal(5, uy, "check uy orientation")
    assert_equal(6, uz, "check uz orientation")
  end

  def test_set_orientation
    # check setting orientation vals are returned
    Lota::Audio.orientation = 1, 2, 3, 4, 5, 6
    fx, fy, fz, ux, uy, uz = Lota::Audio.orientation
    assert_equal(1, fx, "check fx orientation")
    assert_equal(2, fy, "check fy orientation")
    assert_equal(3, fz, "check fz orientation")
    assert_equal(4, ux, "check ux orientation")
    assert_equal(5, uy, "check uy orientation")
    assert_equal(6, uz, "check uz orientation")
  end

  # Translated to Ruby from love.test.audio.getPosition and
  # love.test.audio.setPosition (audio.lua:318-325 and 498-505), by the
  # rules test_get_orientation names.
  def test_get_position
    # check getting values matches what was set
    Lota::Audio.position = 1, 2, 3
    x, y, z = Lota::Audio.position
    assert_equal(1, x, "check x position")
    assert_equal(2, y, "check y position")
    assert_equal(3, z, "check z position")
  end

  def test_set_position
    # check setting position vals are returned
    Lota::Audio.position = 1, 2, 3
    x, y, z = Lota::Audio.position
    assert_equal(1, x, "check x position")
    assert_equal(2, y, "check y position")
    assert_equal(3, z, "check z position")
  end

  # Translated to Ruby from love.test.audio.getVelocity and
  # love.test.audio.setVelocity (audio.lua:336-343 and 509-516), by the
  # rules test_get_orientation names.
  def test_get_velocity
    # check getting values matches what was set
    Lota::Audio.velocity = 1, 2, 3
    x, y, z = Lota::Audio.velocity
    assert_equal(1, x, "check x velocity")
    assert_equal(2, y, "check y velocity")
    assert_equal(3, z, "check z velocity")
  end

  def test_set_velocity
    # check setting velocity vals are returned
    Lota::Audio.velocity = 1, 2, 3
    x, y, z = Lota::Audio.velocity
    assert_equal(1, x, "check x velocity")
    assert_equal(2, y, "check y velocity")
    assert_equal(3, z, "check z velocity")
  end

  # Translated to Ruby from love.test.audio.setDistanceModel
  # (audio.lua:400-411), by the rules test_get_distance_model names; Lua's
  # loop over a table is each over an Array.
  def test_set_distance_model
    # check setting each of the distance models is accepted and val returned
    distancemodel = %i[none inverse inverseclamped linear linearclamped exponent exponentclamped]
    distancemodel.each do |model|
      Lota::Audio.distance_model = model
      assert_equal(model, Lota::Audio.distance_model, "check model set to #{model}")
    end
  end
  # SPDX-SnippetEnd
end
