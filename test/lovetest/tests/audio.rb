# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.audio tests (vendor/love/testing/tests/audio.lua),
# translated to Ruby by ADR 001's rules, all 31 of them. They run in the
# test suite's own process (test/lovetest/audio_test.rb), whose OpenAL Soft
# plays into a wave file, as Lövetest's does on LÖVE's CI
# (test/alsoft.conf), and under lota run (test/lovetest/game), also from
# the installed precompiled gem, which carries OpenAL Soft
# (ext/lota/licenses.rb).
class AudioTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type
  # (love.test.audio.RecordingDevice and love.test.audio.Source).
  TYPES = %w[RecordingDevice Source].freeze

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
  # (vendor/love/testing/tests/audio.lua:58-200): newSource becomes
  # Source.new (rule 2) with its type a symbol (rule 9), as are its units;
  # the getters drop get (rule 3), and isPlaying, isLooping, and
  # isRelative become playing?, looping?, and relative? (rule 8); setters
  # of one value become writers (rule 5) and of several writers of an
  # Array (rule 6), whose getters return Arrays (rule 4); and
  # love.audio.stop with a Source Lota::Audio.stop. newQueueableSource
  # becomes QueueableSource.new (rule 2), and newSoundData SoundData.new.
  # setFilter, setEffect, and love.audio.setEffect return whether they
  # could, so they stay methods (rule 7), and their tables of settings
  # become keywords (rule 10), as getFilter's table becomes a frozen
  # Filter and getEffect's results an Array (rule 4), whose table
  # argument for LÖVE to fill in is dropped. Lua's math.pi and math.floor
  # are Ruby's Math::PI and floor; assertRange becomes assert_includes of
  # a Range, as test_random in tests/math.rb has it.
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

    # create queue source
    queue = Lota::Audio::QueueableSource.new(44100, 16, 1, 3)
    sdata = Lota::Sound::SoundData.new(1024, 44100, 16, 1)
    assert_object(queue)
    run = queue.queue(sdata)
    assert_true(run, "check queued sound")
    queue.stop

    # check making a filer
    setfilter = stereo.set_filter(
      type: :lowpass,
      volume: 0.5,
      highgain: 0.3
    )
    assert_true(setfilter, "check filter applied")
    filter = stereo.filter
    assert_equal(:lowpass, filter.type, "check filter type")
    assert_equal(0.5, filter.volume, "check filter volume")
    assert_includes(0.3..0.4, filter.highgain, "check filter highgain")
    assert_nil(filter.lowgain, "check filter lowgain")

    # add an effect
    effsource = Lota::Audio::Source.new("resources/click.ogg", :static)
    Lota::Audio.set_effect("testeffect",
      type: :flanger,
      volume: 0.75)
    seteffect = effsource.set_effect("testeffect",
      type: :highpass,
      volume: 0.3,
      lowgain: 0.1)

    # both these fail on 12 using stereo or mono, no err
    assert_true(seteffect, "check effect was applied")
    filtersettings = effsource.effect("effectthatdoesntexist").first
    assert_not_nil(filtersettings)

    Lota::Audio.stop(stereo)
    Lota::Audio.stop(mono)
    Lota::Audio.stop(effsource)
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

  # Translated to Ruby from love.test.audio.RecordingDevice
  # (audio.lua:12-54), which skips as Lövetest does: on a GitHub runner,
  # whose OpenAL Soft plays into the wave writer, as this suite's does on
  # every computer (Lovetest::PLAYBACK_ONLY), and where there is no
  # recording device. getRecordingDevices becomes
  # recording_devices (rule 3), whose table is an Array; the device's
  # getters drop get (rule 3), and isRecording becomes recording? (rule
  # 8). Lua's devices[1] is the Array's first, and assertMatch of a list
  # assert_includes.
  def test_recording_device
    # skip recording device on runners, they cant emulate it
    skip("cant emulate recording devices in CI") if Lovetest::GITHUB_RUNNER || Lovetest::PLAYBACK_ONLY

    # check devices first
    devices = Lota::Audio.recording_devices
    skip("cant test this works: no recording devices found") if devices.empty?

    # check object created and basics
    device = devices.first
    assert_object(device)
    assert_includes([1, 2], device.channel_count, "check channel count is 1 or 2")
    refute_equal(nil, device.name, "check has name")

    # check initial data is empty as we haven't recorded anything yet
    assert_not_nil(device.bit_depth)
    assert_nil(device.data, "check initial data empty")
    assert_equal(0, device.sample_count, "check initial sample empty")
    assert_not_nil(device.sample_rate)
    assert_false(device.recording?, "check not recording")

    # start recording for a short time
    startrecording = device.start(32000, 4000, 16, 1)
    wait_frames(10)
    assert_true(startrecording, "check recording started")
    assert_true(device.recording?, "check now recording")
    assert_equal(4000, device.sample_rate, "check sample rate set")
    assert_equal(16, device.bit_depth, "check bit depth set")
    assert_equal(1, device.channel_count, "check channel count set")
    recording = device.stop
    wait_frames(10)

    # after recording
    assert_false(device.recording?, "check not recording")
    assert_nil(device.data, "using stop should clear buffer")
    assert_object(recording)
  end

  # Translated to Ruby from love.test.audio.getActiveEffects
  # (audio.lua:206-216): getActiveEffects becomes active_effects (rule 3),
  # whose table is an Array, and setEffect stays set_effect, as it returns
  # whether it could (rule 7), with its table of settings as keywords
  # (rule 10). Lua's # is size, and list[1] first.
  def test_get_active_effects
    # check we get a value
    assert_not_nil(Lota::Audio.active_effects)
    # check setting an effect active
    Lota::Audio.set_effect("testeffect",
      type: :chorus,
      volume: 0.75)
    assert_equal(1, Lota::Audio.active_effects.size, "check 1 effect running")
    assert_equal("testeffect", Lota::Audio.active_effects.first, "check effect details")
  end

  # Translated to Ruby from love.test.audio.getActiveSourceCount
  # (audio.lua:220-231): getActiveSourceCount becomes active_source_count
  # (rule 3).
  def test_get_active_source_count
    # check we get a value
    assert_not_nil(Lota::Audio.active_source_count)
    # check source isn't active by default
    testsource = Lota::Audio::Source.new("resources/click.ogg", :static)
    Lota::Audio.stop(testsource)
    assert_equal(0, Lota::Audio.active_source_count, "check not active")
    # check playing a source marks it as active
    Lota::Audio.play(testsource)
    assert_equal(1, Lota::Audio.active_source_count, "check now active")
    Lota::Audio.pause
  end

  # Translated to Ruby from love.test.audio.getEffect and
  # love.test.audio.setEffect (audio.lua:258-271 and 425-436): getEffect
  # becomes effect (rule 3), whose table is a frozen Effect (rule 10), with
  # its type a symbol (rule 9). Minitest refuses assert_equal with nil, so
  # Lua's assertEquals(nil, ...) becomes assert_nil.
  def test_get_effect
    # check getting a non-existent effect
    assert_nil(Lota::Audio.effect("madeupname"), "check wrong name")
    # check getting a valid effect
    Lota::Audio.set_effect("testeffect",
      type: :chorus,
      volume: 0.75)
    assert_not_nil(Lota::Audio.effect("testeffect"))
    # check effect values match creation values
    assert_equal(:chorus, Lota::Audio.effect("testeffect").type, "check effect type")
    assert_equal(0.75, Lota::Audio.effect("testeffect").volume, "check effect volume")
  end

  def test_set_effect
    # check effect is set correctly
    effect = Lota::Audio.set_effect("testeffect",
      type: :chorus,
      volume: 0.75)
    assert_true(effect, "check effect created")
    # check values set match
    settings = Lota::Audio.effect("testeffect")
    assert_equal(:chorus, settings.type, "check effect type")
    assert_equal(0.75, settings.volume, "check effect volume")
  end

  # Translated to Ruby from love.test.audio.getMaxSceneEffects,
  # love.test.audio.getMaxSourceEffects, love.test.audio.isEffectsSupported,
  # and love.test.audio.getRecordingDevices (audio.lua:275-285, 330-332,
  # and 355-357): the getters drop get (rule 3), and isEffectsSupported
  # becomes effects_supported? (rule 8).
  def test_get_max_scene_effects
    assert_not_nil(Lota::Audio.max_scene_effects)
  end

  def test_get_max_source_effects
    assert_not_nil(Lota::Audio.max_source_effects)
  end

  def test_is_effects_supported
    assert_not_nil(Lota::Audio.effects_supported?)
  end

  def test_get_recording_devices
    assert_not_nil(Lota::Audio.recording_devices)
  end

  # Translated to Ruby from love.test.audio.getPlaybackDevice,
  # love.test.audio.getPlaybackDevices, and
  # love.test.audio.setPlaybackDevice (audio.lua:303-314 and 460-494):
  # the getters drop get (rule 3), and setPlaybackDevice stays
  # set_playback_device, as it returns whether it could (rule 7), its two
  # results an Array (rule 4), whose first Lua's assertions take. Lua's
  # check that the function exists becomes Ruby's method, and its loop
  # over the devices a find.
  def test_get_playback_device
    assert_not_nil(Lota::Audio.method(:playback_device))
    assert_not_nil(Lota::Audio.playback_device)
  end

  def test_get_playback_devices
    assert_not_nil(Lota::Audio.method(:playback_devices))
    assert_operator(Lota::Audio.playback_devices.size, :>=, 0, "check table")
  end

  def test_set_playback_device
    # check method
    assert_not_nil(Lota::Audio.method(:set_playback_device))

    # check blank string name
    assert_true(Lota::Audio.set_playback_device("").first, "check blank device is fine")

    # check invalid name
    assert_false(Lota::Audio.set_playback_device("loveFM").first, "check invalid device fails")

    # check setting already set
    assert_true(Lota::Audio.set_playback_device(Lota::Audio.playback_device).first,
      "check existing device is fine")

    # if other devices to play with lets set a different one
    devices = Lota::Audio.playback_devices
    if devices.size > 1
      current = Lota::Audio.playback_device
      another = devices.find { |device| device != current } || ""
      if another != ""
        # check setting new device
        success4, _msg4 = Lota::Audio.set_playback_device(another)
        assert_true(success4, "check setting different device")
        # check resetting to default
        success5, _msg5 = Lota::Audio.set_playback_device
        assert_true(success5, "check resetting")
        assert_equal(current, Lota::Audio.playback_device)
      end
    end
  end

  # Translated to Ruby from love.test.audio.newQueueableSource
  # (audio.lua:362-365): newQueueableSource becomes QueueableSource.new
  # (rule 2).
  def test_new_queueable_source
    assert_object(Lota::Audio::QueueableSource.new(32, 8, 1, 8))
  end

  # Translated to Ruby from love.test.audio.pause (audio.lua:376-386):
  # pause's table of the Sources it paused is an Array, whose size Lua's
  # # gives.
  def test_pause
    # check nothing paused (as should be nothing playing)
    nopauses = Lota::Audio.pause
    assert_equal(0, nopauses.size, "check nothing paused")
    # check 1 source paused after playing/pausing 1
    source = Lota::Audio::Source.new("resources/click.ogg", :static)
    Lota::Audio.play(source)
    onepause = Lota::Audio.pause
    assert_equal(1, onepause.size, "check 1 paused")
    Lota::Audio.stop(source)
  end

  # Translated to Ruby from love.test.audio.setMixWithSystem
  # (audio.lua:440-442): setMixWithSystem stays set_mix_with_system, as it
  # returns whether it could (rule 7).
  def test_set_mix_with_system
    assert_not_nil(Lota::Audio.set_mix_with_system(true))
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
