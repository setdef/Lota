# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Audio
    # A sound the game can play, matching LÖVE's Source class
    # (src/modules/audio/Source.h).
    #
    # A short sound effect is decoded whole when it is made, so it starts
    # at once each time it plays: a <tt>:static</tt> Source. Music is long,
    # so it is decoded a little at a time while it plays: a
    # <tt>:stream</tt> Source. A Source plays one sound at a time; playing
    # it again while it plays does nothing.
    #
    # === Example
    #
    #   music = Lota::Audio::Source.new("music/theme.ogg", :stream)
    #   music.looping = true
    #   music.play
    class Source
      include Object

      # The engine's Source, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Source the engine made. :nodoc:
      def self.from_native(native)
        source = allocate
        source.instance_variable_set(:@native, native)
        source
      end

      # Makes a Source, matching love.audio.newSource
      # (src/modules/audio/wrap_Audio.cpp, w_newSource).
      #
      # [source] What it plays: a String path of a sound file, found in the
      #   game's folder or its save directory (a WAVE, Ogg Vorbis, MP3,
      #   FLAC, or tracker module file), or a Lota::Filesystem::FileData
      #   holding one, either of which needs +type+; a
      #   Lota::Sound::SoundData, whose samples it plays as a
      #   <tt>:static</tt> Source; or a Lota::Sound::Decoder, which it
      #   streams.
      # [type] Symbol <tt>:static</tt>, which decodes the whole file now,
      #   or <tt>:stream</tt>, which decodes it as it plays (ADR 001, rule
      #   9); a SoundData or a Decoder takes none, as LÖVE reads none for
      #   them.
      # [streamtype] For a <tt>:stream</tt> Source from a file, how its
      #   Decoder reads the file: <tt>:file</tt>, as it plays, by default,
      #   or <tt>:memory</tt>, all of it first, as Lota::Sound::Decoder.new
      #   takes it.
      #
      # A file becomes a Decoder through Lota::Sound::Decoder.new, and a
      # static one's Decoder a SoundData through
      # Lota::Sound::SoundData.new, as LÖVE converts them with love.sound.
      #
      # Raises ArgumentError, with LÖVE's message, for a +type+ LÖVE does
      # not know; TypeError for a +source+ of another kind, or a file with
      # no +type+; and RuntimeError for <tt>:queue</tt>, for a file the
      # engine cannot open or decode, and when the audio or the sound
      # module is not open.
      #
      # === Examples
      #
      #   Lota::Audio::Source.new("sounds/click.wav", :static)
      #
      #   beep = Lota::Sound::SoundData.new(4410, 44_100, 16, 1)
      #   Lota::Audio::Source.new(beep).get_type # => :static
      def self.new(source, type = nil, streamtype = nil)
        case source
        when Sound::SoundData then return from_native(Native::Audio.new_source_from_sound_data(source.native))
        when Sound::Decoder then return from_native(Native::Audio.new_source_from_decoder(source.native))
        end

        unless type.is_a?(Symbol) || type.is_a?(String)
          raise TypeError, "wrong argument type #{type.class} for type (expected Symbol)"
        end

        static = Native::Audio.source_type(EnumName.of(type)) == "static"
        unless source.is_a?(String) || source.is_a?(Filesystem::FileData)
          raise TypeError,
            "wrong argument type #{source.class} (expected Lota::Sound::Decoder or Lota::Sound::SoundData)"
        end

        decoder = Sound::Decoder.new(source, Sound::Decoder::DEFAULT_BUFFER_SIZE, static ? :memory : streamtype)
        return from_native(Native::Audio.new_source_from_decoder(decoder.native)) unless static

        from_native(Native::Audio.new_source_from_sound_data(Sound::SoundData.new(decoder).native))
      end

      # Makes this Source, a copy of +source+ by Ruby's +clone+ or +dup+,
      # LÖVE's copy, matching Source:clone
      # (src/modules/audio/wrap_Source.cpp, w_Source_clone): a new Source
      # of the same sound, stopped, with +source+'s pitch, volume,
      # looping, and other settings, which it then keeps apart from
      # +source+'s (ADR 001, section 7). A streaming Source's copy streams
      # the file again from its start.
      #
      # === Example
      #
      #   echo = source.clone
      #   echo.volume = 0.5
      #   source.volume # => 1.0
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # Plays the Source from where it is, matching Source:play
      # (src/modules/audio/wrap_Source.cpp, w_Source_play).
      #
      # Returns +true+ when it started, and +false+ when it could not, as
      # when every one of the engine's voices is busy.
      #
      # === Example
      #
      #   source.play # => true
      def play
        @native.play
      end

      # Stops the Source, so that it plays from its beginning next time,
      # matching Source:stop (src/modules/audio/wrap_Source.cpp,
      # w_Source_stop).
      #
      # === Example
      #
      #   source.stop
      def stop
        @native.stop
      end

      # Pauses the Source, so that it plays on from where it stopped next
      # time, matching Source:pause (src/modules/audio/wrap_Source.cpp,
      # w_Source_pause).
      #
      # === Example
      #
      #   source.pause
      def pause
        @native.pause
      end

      # Whether the Source is playing, matching Source:isPlaying
      # (src/modules/audio/wrap_Source.cpp, w_Source_isPlaying).
      #
      # === Example
      #
      #   source.playing? # => false
      def playing?
        @native.playing?
      end

      # How fast the Source plays, as a Float: 1 as recorded, 2 twice as
      # fast and an octave higher, matching Source:getPitch
      # (src/modules/audio/wrap_Source.cpp, w_Source_getPitch).
      #
      # === Example
      #
      #   source.pitch # => 1.0
      def pitch
        @native.pitch
      end

      # Sets how fast the Source plays, matching Source:setPitch
      # (src/modules/audio/wrap_Source.cpp, w_Source_setPitch).
      #
      # [pitch] Float or Integer, more than 0: 1 as recorded, 0.5 half as
      #   fast and an octave lower.
      #
      # Raises RuntimeError, with LÖVE's message, for NaN, 0, a negative
      # number, or infinity.
      #
      # === Example
      #
      #   source.pitch = 0.5
      def pitch=(pitch)
        @native.set_pitch(pitch)
      end

      # How loud the Source plays, as a Float, matching Source:getVolume
      # (src/modules/audio/wrap_Source.cpp, w_Source_getVolume).
      #
      # === Example
      #
      #   source.volume # => 1.0
      def volume
        @native.volume
      end

      # Sets how loud the Source plays, matching Source:setVolume
      # (src/modules/audio/wrap_Source.cpp, w_Source_setVolume).
      #
      # [volume] Float or Integer, 0 for silence and 1 as recorded.
      #
      # === Example
      #
      #   source.volume = 0.25
      def volume=(volume)
        @native.set_volume(volume)
      end

      # Whether the Source starts again from its beginning when it ends,
      # matching Source:isLooping (src/modules/audio/wrap_Source.cpp,
      # w_Source_isLooping).
      #
      # === Example
      #
      #   source.looping? # => false
      def looping?
        @native.looping?
      end

      # Sets whether the Source starts again from its beginning when it
      # ends, matching Source:setLooping
      # (src/modules/audio/wrap_Source.cpp, w_Source_setLooping).
      #
      # [looping] +true+ or +false+.
      #
      # === Example
      #
      #   music.looping = true
      def looping=(looping)
        @native.set_looping(looping)
      end

      # How many channels the Source's sound has, as an Integer: 1 for
      # mono, 2 for stereo, matching Source:getChannelCount
      # (src/modules/audio/wrap_Source.cpp, w_Source_getChannelCount).
      #
      # === Example
      #
      #   source.channel_count # => 1
      def channel_count
        @native.channel_count
      end

      # Sets the Source's position in space, in the units the listener's position is in, matching Source:setPosition
      # (src/modules/audio/wrap_Source.cpp, w_Source_setPosition): x, y, and
      # optionally z, 0 by default, as an Array (ADR 001, rule 6).
      #
      # LÖVE places only a mono Source in space; a stereo one raises
      # RuntimeError with LÖVE's message, as LÖVE does. Raises TypeError for
      # a value that is not a number.
      #
      # === Example
      #
      #   steps.position = 120, 40
      def position=(vector)
        x, y, z = Source.numbers(vector)
        @native.set_position(Source.number(x), Source.number(y), Source.number(z, 0))
      end

      # The Source's position in space, in the units the listener's position is in, as an Array of three Floats (ADR 001, rule 4),
      # matching Source:getPosition (src/modules/audio/wrap_Source.cpp,
      # w_Source_getPosition). A stereo Source raises RuntimeError.
      #
      # === Example
      #
      #   x, y, z = steps.position
      def position
        @native.position
      end

      # Sets the Source's velocity, which the Doppler effect reads, matching Source:setVelocity
      # (src/modules/audio/wrap_Source.cpp, w_Source_setVelocity): x, y, and
      # optionally z, 0 by default, as an Array (ADR 001, rule 6).
      #
      # LÖVE places only a mono Source in space; a stereo one raises
      # RuntimeError with LÖVE's message, as LÖVE does. Raises TypeError for
      # a value that is not a number.
      #
      # === Example
      #
      #   car.velocity = 30, 0, 0
      def velocity=(vector)
        x, y, z = Source.numbers(vector)
        @native.set_velocity(Source.number(x), Source.number(y), Source.number(z, 0))
      end

      # The Source's velocity, which the Doppler effect reads, as an Array of three Floats (ADR 001, rule 4),
      # matching Source:getVelocity (src/modules/audio/wrap_Source.cpp,
      # w_Source_getVelocity). A stereo Source raises RuntimeError.
      #
      # === Example
      #
      #   x, y, z = steps.velocity
      def velocity
        @native.velocity
      end

      # Sets the Source's direction, which its cone points along, matching Source:setDirection
      # (src/modules/audio/wrap_Source.cpp, w_Source_setDirection): x, y, and
      # optionally z, 0 by default, as an Array (ADR 001, rule 6).
      #
      # LÖVE places only a mono Source in space; a stereo one raises
      # RuntimeError with LÖVE's message, as LÖVE does. Raises TypeError for
      # a value that is not a number.
      #
      # === Example
      #
      #   speaker.direction = 0, 1, 0
      def direction=(vector)
        x, y, z = Source.numbers(vector)
        @native.set_direction(Source.number(x), Source.number(y), Source.number(z, 0))
      end

      # The Source's direction, which its cone points along, as an Array of three Floats (ADR 001, rule 4),
      # matching Source:getDirection (src/modules/audio/wrap_Source.cpp,
      # w_Source_getDirection). A stereo Source raises RuntimeError.
      #
      # === Example
      #
      #   x, y, z = steps.direction
      def direction
        @native.direction
      end

      # Sets the Source's cone, matching Source:setCone
      # (src/modules/audio/wrap_Source.cpp, w_Source_setCone): the Float
      # inner and outer angles, in radians, then optionally the volume
      # outside the outer angle (0 by default) and its high-frequency gain
      # (1 by default), as an Array (ADR 001, rule 6).
      #
      # A stereo Source raises RuntimeError with LÖVE's message.
      #
      # === Example
      #
      #   speaker.cone = 0, Math::PI / 2, 0.2
      def cone=(cone)
        inner, outer, volume, gain = Source.numbers(cone)
        @native.set_cone(Source.number(inner), Source.number(outer), Source.number(volume, 0), Source.number(gain, 1))
      end

      # The cone's inner and outer angles, outer volume, and outer
      # high-frequency gain, as an Array of Floats (ADR 001, rule 4),
      # matching Source:getCone (src/modules/audio/wrap_Source.cpp,
      # w_Source_getCone).
      #
      # === Example
      #
      #   inner, outer, volume, gain = speaker.cone
      def cone
        @native.cone
      end

      # Sets whether the Source's position, velocity, and direction are
      # relative to the listener, matching Source:setRelative
      # (src/modules/audio/wrap_Source.cpp, w_Source_setRelative).
      #
      # A relative Source at (0, 0, 0) plays where the listener is,
      # wherever the listener moves. A stereo Source raises RuntimeError.
      #
      # === Example
      #
      #   footsteps.relative = true
      def relative=(enable)
        @native.set_relative(!!enable)
      end

      # Whether the Source is relative to the listener, matching
      # Source:isRelative (src/modules/audio/wrap_Source.cpp,
      # w_Source_isRelative).
      #
      # === Example
      #
      #   footsteps.relative? # => false
      def relative?
        @native.relative?
      end

      # Sets the Source's least and greatest volume, matching
      # Source:setVolumeLimits (src/modules/audio/wrap_Source.cpp,
      # w_Source_setVolumeLimits), as an Array of two Floats (ADR 001, rule
      # 6), which bound the volume distance and cones leave it.
      #
      # Raises RuntimeError with LÖVE's message for a least volume outside
      # 0 to 1 or a negative greatest.
      #
      # === Example
      #
      #   engine.volume_limits = 0.1, 1
      def volume_limits=(limits)
        least, greatest = Source.numbers(limits)
        @native.set_volume_limits(Source.number(least), Source.number(greatest))
      end

      # The least and greatest volume, as an Array of two Floats (ADR 001,
      # rule 4), matching Source:getVolumeLimits
      # (src/modules/audio/wrap_Source.cpp, w_Source_getVolumeLimits).
      #
      # === Example
      #
      #   least, greatest = engine.volume_limits # => [0.0, 1.0]
      def volume_limits
        @native.volume_limits
      end

      # Sets the distances the Source's volume falls between, matching
      # Source:setAttenuationDistances (src/modules/audio/wrap_Source.cpp,
      # w_Source_setAttenuationDistances): the Float reference distance,
      # within which it plays at full volume, and the greatest distance,
      # beyond which it falls no further, as an Array (ADR 001, rule 6).
      #
      # How the volume falls between them is Lota::Audio.distance_model.
      # Raises RuntimeError with LÖVE's message for a negative distance,
      # and for a stereo Source.
      #
      # === Example
      #
      #   campfire.attenuation_distances = 50, 400
      def attenuation_distances=(distances)
        reference, greatest = Source.numbers(distances)
        @native.set_attenuation_distances(Source.number(reference), Source.number(greatest))
      end

      # The reference and greatest distances, as an Array of two Floats
      # (ADR 001, rule 4), matching Source:getAttenuationDistances
      # (src/modules/audio/wrap_Source.cpp,
      # w_Source_getAttenuationDistances).
      #
      # === Example
      #
      #   reference, greatest = campfire.attenuation_distances
      def attenuation_distances
        @native.attenuation_distances
      end

      # Sets how fast the Source's volume falls with distance, matching
      # Source:setRolloff (src/modules/audio/wrap_Source.cpp,
      # w_Source_setRolloff): 1 as the distance model has it, more to fall
      # faster, 0 not to fall.
      #
      # Raises RuntimeError with LÖVE's message for a negative rolloff, and
      # for a stereo Source.
      #
      # === Example
      #
      #   campfire.rolloff = 2
      def rolloff=(rolloff)
        @native.set_rolloff(rolloff)
      end

      # The Float rolloff, matching Source:getRolloff
      # (src/modules/audio/wrap_Source.cpp, w_Source_getRolloff).
      #
      # === Example
      #
      #   campfire.rolloff # => 1.0
      def rolloff
        @native.rolloff
      end

      # Sets how much the air muffles the Source with distance, matching
      # Source:setAirAbsorption (src/modules/audio/wrap_Source.cpp,
      # w_Source_setAirAbsorption): 0, none, by default, up to 10.
      #
      # Raises RuntimeError with LÖVE's message for a negative factor, and
      # for a stereo Source.
      #
      # === Example
      #
      #   thunder.air_absorption = 1
      def air_absorption=(factor)
        @native.set_air_absorption(factor)
      end

      # The Float air absorption factor, matching Source:getAirAbsorption
      # (src/modules/audio/wrap_Source.cpp, w_Source_getAirAbsorption).
      #
      # === Example
      #
      #   thunder.air_absorption # => 0.0
      def air_absorption
        @native.air_absorption
      end

      # Moves the Source's playback to +offset+, matching Source:seek
      # (src/modules/audio/wrap_Source.cpp, w_Source_seek).
      #
      # [offset] Float or Integer position to play from.
      # [unit] <tt>:seconds</tt>, by default, or <tt>:samples</tt>.
      #
      # Returns +nil+. Raises ArgumentError for a negative offset or a unit
      # LÖVE does not know.
      #
      # === Example
      #
      #   music.seek(30)
      def seek(offset, unit = nil)
        @native.seek(offset, unit && EnumName.of(unit))
      end

      # Where the Source plays, as a Float, in <tt>:seconds</tt>, by
      # default, or <tt>:samples</tt>, matching Source:tell
      # (src/modules/audio/wrap_Source.cpp, w_Source_tell).
      #
      # Raises ArgumentError for a unit LÖVE does not know.
      #
      # === Example
      #
      #   music.tell # => 30.0
      def tell(unit = nil)
        @native.tell(unit && EnumName.of(unit))
      end

      # How long the Source's sound is, as a Float, in <tt>:seconds</tt>,
      # by default, or <tt>:samples</tt>, matching Source:getDuration
      # (src/modules/audio/wrap_Source.cpp, w_Source_getDuration); -1 where
      # the decoder cannot tell.
      #
      # Raises ArgumentError for a unit LÖVE does not know.
      #
      # === Example
      #
      #   music.duration(:samples) # => 1323000.0
      def duration(unit = nil)
        @native.duration(unit && EnumName.of(unit))
      end

      # How many of a streaming or queueable Source's buffers are free, as
      # an Integer, matching Source:getFreeBufferCount
      # (src/modules/audio/wrap_Source.cpp, w_Source_getFreeBufferCount);
      # 0 for a static Source.
      #
      # === Example
      #
      #   music.free_buffer_count # => 0
      def free_buffer_count
        @native.free_buffer_count
      end

      # The numbers of a writer of several values (ADR 001, rule 6), one
      # value or an Array. :nodoc:
      def self.numbers(value)
        value.is_a?(Array) ? value : [value]
      end

      # One of those numbers, as luaL_checknumber reads it, or as
      # luaL_optnumber reads it with +default+ when it is nil. :nodoc:
      def self.number(value, default = nil)
        value = default if value.nil?
        case value
        when Integer, Float then value
        else raise TypeError, "wrong argument type #{value.class} (expected Float or Integer)"
        end
      end

      # How the Source holds its sound, as a Symbol, matching
      # Source:getType (src/modules/audio/wrap_Source.cpp,
      # w_Source_getType): <tt>:static</tt>, <tt>:stream</tt>, or
      # <tt>:queue</tt> (ADR 001, rules 9 and 16).
      #
      # A Source has no +type+, as LÖVE's Source answers both Object:type
      # and getType; #object_type is LÖVE's name for its class.
      #
      # === Example
      #
      #   Lota::Audio::Source.new("click.ogg", :static).get_type # => :static
      def get_type
        @native.get_type.to_sym
      end
    end
  end
end
