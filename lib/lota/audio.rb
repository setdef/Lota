# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "audio/effect"
require_relative "audio/filter"
require_relative "audio/queueable_source"
require_relative "audio/recording_device"
require_relative "audio/source"

module Lota
  # Sound effects and music, translated from love.audio.
  #
  # A game plays a sound when something happens: a click, a jump, an
  # explosion. Each sound is a Lota::Audio::Source, made once from a file
  # in the game's folder and played as often as the game likes, and
  # Lota::Audio plays and stops Sources and sets the volume of them all.
  #
  # Lota opens the audio module, and the sound module that decodes files
  # for it, unless your settings turn them off (<tt>t.modules.audio =
  # false</tt>), as LÖVE does. LÖVE plays through OpenAL Soft. When it
  # cannot open the system's audio device, as on a computer with none, it
  # prints why and opens a silent audio module instead, whose Sources play
  # nothing, and so does Lota.
  #
  # === Example
  #
  #   def Lota.load
  #     @click = Lota::Audio::Source.new("sounds/click.wav", :static)
  #   end
  #
  #   def Lota.mousepressed(x, y, button)
  #     Lota::Audio.play(@click)
  #   end
  module Audio
    # Plays +source+, matching love.audio.play with one Source
    # (src/modules/audio/wrap_Audio.cpp, w_play), as Source#play does.
    #
    # Returns +true+ when it started, and +false+ when it could not, as
    # when every one of the engine's voices is busy. Raises RuntimeError
    # when the audio module is not open.
    #
    # === Example
    #
    #   Lota::Audio.play(@click) # => true
    def self.play(source)
      Native::Audio.play(source.__send__(:native))
    end

    # Stops +source+, or every Source playing when left out, matching
    # love.audio.stop (src/modules/audio/wrap_Audio.cpp, w_stop). A
    # stopped Source starts from its beginning when it plays again.
    #
    # Raises RuntimeError when the audio module is not open.
    #
    # === Examples
    #
    #   Lota::Audio.stop(@music)
    #   Lota::Audio.stop
    def self.stop(source = nil)
      source ? Native::Audio.stop_source(source.__send__(:native)) : Native::Audio.stop
    end

    # How loud every Source plays, from 0 for silence to 1 for as loud as
    # each is, as a Float, matching love.audio.getVolume
    # (src/modules/audio/wrap_Audio.cpp, w_getVolume).
    #
    # === Example
    #
    #   Lota::Audio.volume # => 1.0
    def self.volume
      Native::Audio.volume
    end

    # Sets how loud every Source plays, matching love.audio.setVolume
    # (src/modules/audio/wrap_Audio.cpp, w_setVolume).
    #
    # [volume] Float or Integer, from 0 for silence to 1 for as loud as
    #   each Source is.
    #
    # === Example
    #
    #   Lota::Audio.volume = 0.5
    def self.volume=(volume)
      Native::Audio.set_volume(volume)
    end

    # How many Sources are playing, as an Integer, matching
    # love.audio.getActiveSourceCount
    # (src/modules/audio/wrap_Audio.cpp, w_getActiveSourceCount).
    #
    # === Example
    #
    #   Lota::Audio.active_source_count # => 2
    def self.active_source_count
      Native::Audio.active_source_count
    end

    # Sets the listener's position, matching love.audio.setPosition
    # (src/modules/audio/wrap_Audio.cpp, w_setPosition): x, y, and
    # optionally z, 0 by default, as an Array (rule 6 of
    # doc/contributors/design/translation.md).
    #
    # A mono Source plays louder and from its side the nearer and the more
    # to that side of the listener it is. Raises TypeError for a value that
    # is not a number.
    #
    # === Example
    #
    #   Lota::Audio.position = player.x, player.y
    def self.position=(position)
      x, y, z = Audio::Source.__send__(:numbers, position)
      Native::Audio.set_position(Source.__send__(:number, x), Source.__send__(:number, y), Source.__send__(:number, z, 0))
    end

    # The listener's position, as an Array of three Floats (rule 4 of
    # doc/contributors/design/translation.md), matching love.audio.getPosition
    # (src/modules/audio/wrap_Audio.cpp, w_getPosition).
    #
    # === Example
    #
    #   x, y, z = Lota::Audio.position # => [0.0, 0.0, 0.0]
    def self.position
      Native::Audio.position
    end

    # Sets the listener's orientation, matching love.audio.setOrientation
    # (src/modules/audio/wrap_Audio.cpp, w_setOrientation): the forward
    # vector's x, y, and z, then the up vector's, six numbers in an Array
    # (rule 6 of doc/contributors/design/translation.md).
    #
    # Raises TypeError for fewer than six numbers, or one that is not a
    # number.
    #
    # === Example
    #
    #   Lota::Audio.orientation = 0, 0, -1, 0, 1, 0
    def self.orientation=(orientation)
      fx, fy, fz, ux, uy, uz = Source.__send__(:numbers, orientation)
      Native::Audio.set_orientation([
        Source.__send__(:number, fx),
        Source.__send__(:number, fy),
        Source.__send__(:number, fz),
        Source.__send__(:number, ux),
        Source.__send__(:number, uy),
        Source.__send__(:number, uz),
])
    end

    # The listener's forward and up vectors, as an Array of six Floats (rule 4
    # of doc/contributors/design/translation.md), matching
    # love.audio.getOrientation (src/modules/audio/wrap_Audio.cpp,
    # w_getOrientation).
    #
    # === Example
    #
    #   fx, fy, fz, ux, uy, uz = Lota::Audio.orientation
    def self.orientation
      Native::Audio.orientation
    end

    # Sets the listener's velocity, which the Doppler effect reads,
    # matching love.audio.setVelocity (src/modules/audio/wrap_Audio.cpp,
    # w_setVelocity), as position= takes a position.
    #
    # === Example
    #
    #   Lota::Audio.velocity = 0, 0, 0
    def self.velocity=(velocity)
      x, y, z = Audio::Source.__send__(:numbers, velocity)
      Native::Audio.set_velocity(Source.__send__(:number, x), Source.__send__(:number, y), Source.__send__(:number, z, 0))
    end

    # The listener's velocity, as an Array of three Floats (rule 4 of
    # doc/contributors/design/translation.md), matching love.audio.getVelocity
    # (src/modules/audio/wrap_Audio.cpp, w_getVelocity).
    #
    # === Example
    #
    #   x, y, z = Lota::Audio.velocity
    def self.velocity
      Native::Audio.velocity
    end

    # Sets how strong the Doppler effect is, matching
    # love.audio.setDopplerScale (src/modules/audio/wrap_Audio.cpp,
    # w_setDopplerScale): 1 by default, 0 for none.
    #
    # === Example
    #
    #   Lota::Audio.doppler_scale = 0
    def self.doppler_scale=(scale)
      Native::Audio.set_doppler_scale(scale)
    end

    # The Float Doppler scale, matching love.audio.getDopplerScale
    # (src/modules/audio/wrap_Audio.cpp, w_getDopplerScale).
    #
    # === Example
    #
    #   Lota::Audio.doppler_scale # => 1.0
    def self.doppler_scale
      Native::Audio.doppler_scale
    end

    # Sets how a Source's volume falls with its distance from the listener,
    # matching love.audio.setDistanceModel
    # (src/modules/audio/wrap_Audio.cpp, w_setDistanceModel): +:none+,
    # +:inverse+, +:inverseclamped+ (the default), +:linear+,
    # +:linearclamped+, +:exponent+, or +:exponentclamped+ (rule 9 of
    # doc/contributors/design/translation.md).
    #
    # Raises ArgumentError, with LÖVE's message, for a model it does not
    # know.
    #
    # === Example
    #
    #   Lota::Audio.distance_model = :linearclamped
    def self.distance_model=(model)
      Native::Audio.set_distance_model(EnumName.of(model))
    end

    # The distance model, as a Symbol, matching love.audio.getDistanceModel
    # (src/modules/audio/wrap_Audio.cpp, w_getDistanceModel).
    #
    # === Example
    #
    #   Lota::Audio.distance_model # => :inverseclamped
    def self.distance_model
      Native::Audio.distance_model.to_sym
    end

    # Pauses Sources, matching love.audio.pause
    # (src/modules/audio/wrap_Audio.cpp, w_pause).
    #
    # With no Source, it pauses every Source playing and returns them, as
    # an Array where LÖVE returns a table, to play again later. With one,
    # it pauses that Source and returns +nil+. LÖVE also takes several
    # Sources, or a table of them, which Lota does not bind yet. Raises
    # RuntimeError when the audio module is not open.
    #
    # === Examples
    #
    #   paused = Lota::Audio.pause
    #   paused.each(&:play)
    #   Lota::Audio.pause(@music) # => nil
    def self.pause(source = nil)
      return Native::Audio.pause_source(source.__send__(:native)) if source

      Native::Audio.pause.map { |native| Source.__send__(:from_native, native) }
    end

    # Makes, changes, or removes a named effect that Sources can play
    # through, matching love.audio.setEffect
    # (src/modules/audio/wrap_Audio.cpp, w_setEffect), and returns whether
    # it could (rule 7 of doc/contributors/design/translation.md), as with no
    # effects on the system.
    #
    # [name] String name of the effect, which Source#set_effect takes.
    # [settings] LÖVE's table, as keywords (rule 10): +type+, one of
    #   <tt>:chorus</tt>, <tt>:compressor</tt>, <tt>:distortion</tt>,
    #   <tt>:echo</tt>, <tt>:equalizer</tt>, <tt>:flanger</tt>,
    #   <tt>:reverb</tt>, and <tt>:ringmodulator</tt>, +volume+, and the
    #   settings of the type (Lota::Audio::Effect), each a number, a
    #   boolean, or a waveform's Symbol. With no settings, or +false+, it
    #   removes the effect.
    #
    # Raises RuntimeError with LÖVE's message for settings without a
    # +type+, a setting the type does not have, or a setting of the wrong
    # kind, and ArgumentError for a type or waveform LÖVE does not know.
    #
    # === Examples
    #
    #   Lota::Audio.set_effect("cave", type: :reverb, decaytime: 3) # => true
    #   Lota::Audio.set_effect("cave", false) # => true
    def self.set_effect(name, enabled = nil, **settings)
      raise TypeError, "wrong argument type #{enabled.class} (expected false)" unless enabled.nil? || enabled == false

      Native::Audio.set_effect(name, (enabled == false) ? nil : setting_pairs(settings))
    end

    # The settings of the effect +name+, matching love.audio.getEffect
    # (src/modules/audio/wrap_Audio.cpp, w_getEffect), as a frozen
    # Lota::Audio::Effect, or +nil+ when there is none. LÖVE also fills in
    # a table the caller passes; an Effect is frozen, so Lota makes a new
    # one each time and takes no table (rule 10).
    #
    # === Example
    #
    #   Lota::Audio.effect("cave").type # => :reverb
    def self.effect(name)
      pairs = Native::Audio.effect(name)
      pairs && Effect.__send__(:of, pairs)
    end

    # The names of the effects set, as an Array, matching
    # love.audio.getActiveEffects (src/modules/audio/wrap_Audio.cpp,
    # w_getActiveEffects).
    #
    # === Example
    #
    #   Lota::Audio.active_effects # => ["cave"]
    def self.active_effects
      Native::Audio.active_effects
    end

    # How many effects can be set at once, matching
    # love.audio.getMaxSceneEffects (src/modules/audio/wrap_Audio.cpp,
    # w_getMaxSceneEffects).
    #
    # === Example
    #
    #   Lota::Audio.max_scene_effects # => 64
    def self.max_scene_effects
      Native::Audio.max_scene_effects
    end

    # How many effects one Source can play through at once, matching
    # love.audio.getMaxSourceEffects (src/modules/audio/wrap_Audio.cpp,
    # w_getMaxSourceEffects).
    #
    # === Example
    #
    #   Lota::Audio.max_source_effects # => 2
    def self.max_source_effects
      Native::Audio.max_source_effects
    end

    # Whether the system plays effects, matching
    # love.audio.isEffectsSupported (src/modules/audio/wrap_Audio.cpp,
    # w_isEffectsSupported).
    #
    # === Example
    #
    #   Lota::Audio.effects_supported? # => true
    def self.effects_supported?
      Native::Audio.effects_supported?
    end

    # Sets whether the game's sound mixes with other apps' sound, matching
    # love.audio.setMixWithSystem (src/modules/audio/wrap_Audio.cpp,
    # w_setMixWithSystem), and returns whether it could (rule 7 of
    # doc/contributors/design/translation.md): only iOS and Android can, so on
    # the desktop it returns +false+. Lota::Boot calls it with
    # <tt>t.audio.mixwithsystem</tt> before the audio module opens, as LÖVE's
    # boot does.
    #
    # === Example
    #
    #   Lota::Audio.set_mix_with_system(true) # => false on the desktop
    def self.set_mix_with_system(mix)
      Native::Audio.set_mix_with_system(mix)
    end

    # The name of the device the game plays through, matching
    # love.audio.getPlaybackDevice (src/modules/audio/wrap_Audio.cpp,
    # w_getPlaybackDevice).
    #
    # === Example
    #
    #   Lota::Audio.playback_device # => "MacBook Pro Speakers"
    def self.playback_device
      Native::Audio.playback_device
    end

    # The names of the devices the game could play through, as an Array,
    # matching love.audio.getPlaybackDevices
    # (src/modules/audio/wrap_Audio.cpp, w_getPlaybackDevices).
    #
    # === Example
    #
    #   Lota::Audio.playback_devices # => ["MacBook Pro Speakers"]
    def self.playback_devices
      Native::Audio.playback_devices
    end

    # Plays through the device named +name+, or the system's default
    # when +nil+ or left out, matching love.audio.setPlaybackDevice
    # (src/modules/audio/wrap_Audio.cpp, w_setPlaybackDevice), and returns
    # an Array (rules 4 and 7): <tt>[true]</tt>, or +false+ and LÖVE's
    # message when it could not.
    #
    # === Example
    #
    #   Lota::Audio.set_playback_device("Headphones") # => [true]
    def self.set_playback_device(name = nil)
      Native::Audio.set_playback_device(name)
    end

    # The recording devices, such as microphones, as an Array of
    # Lota::Audio::RecordingDevice, matching love.audio.getRecordingDevices
    # (src/modules/audio/wrap_Audio.cpp, w_getRecordingDevices).
    #
    # === Example
    #
    #   Lota::Audio.recording_devices.map(&:name) # => ["MacBook Pro Microphone"]
    def self.recording_devices
      Native::Audio.recording_devices.map { |native| RecordingDevice.__send__(:from_native, native) }
    end

    # Turns on or off playing through headphones' spatial filter, matching
    # love.audio.setOutputSpatialization
    # (src/modules/audio/wrap_Audio.cpp, w_setOutputSpatialization), and
    # returns whether it could (rule 7 of
    # doc/contributors/design/translation.md).
    #
    # [enable] Whether to.
    # [filter] String name of one of output_spatialization_filters, or
    #   the system's choice when +nil+ or left out.
    #
    # === Example
    #
    #   Lota::Audio.set_output_spatialization(true) # => true
    def self.set_output_spatialization(enable, filter = nil)
      Native::Audio.set_output_spatialization(enable, filter)
    end

    # Whether the game plays through a spatial filter, and its name or
    # +nil+, as an Array (rule 4), matching
    # love.audio.getOutputSpatialization
    # (src/modules/audio/wrap_Audio.cpp, w_getOutputSpatialization).
    #
    # === Example
    #
    #   Lota::Audio.output_spatialization # => [false, nil]
    def self.output_spatialization
      Native::Audio.output_spatialization
    end

    # The names of the spatial filters the system has, as an Array,
    # matching love.audio.getOutputSpatializationFilters
    # (src/modules/audio/wrap_Audio.cpp, w_getOutputSpatializationFilters).
    #
    # === Example
    #
    #   Lota::Audio.output_spatialization_filters # => ["Built-In HRTF"]
    def self.output_spatialization_filters
      Native::Audio.output_spatialization_filters
    end

    # The [name, value] pairs the engine reads an effect's or a filter's
    # keywords as, each Symbol value a name, or +nil+ for none, as LÖVE
    # reads no table. :nodoc:
    private_class_method def self.setting_pairs(settings)
      return nil if settings.empty?

      settings.map { |name, value| [name.name, value.is_a?(Symbol) ? value.name : value] }
    end
  end
end
