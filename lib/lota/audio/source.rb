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

      # Makes a Source from a sound file, matching love.audio.newSource
      # with a filename (src/modules/audio/wrap_Audio.cpp, w_newSource).
      #
      # [filename] String path of the file, found in the game's folder or
      #   its save directory: a WAVE, Ogg Vorbis, MP3, FLAC, or tracker
      #   module file.
      # [type] Symbol <tt>:static</tt>, which decodes the whole file now,
      #   or <tt>:stream</tt>, which decodes it as it plays (ADR 001, rule
      #   9).
      #
      # Raises ArgumentError, with LÖVE's message, for a +type+ LÖVE does
      # not know, and RuntimeError for <tt>:queue</tt>, for a file the
      # engine cannot open or decode, and when the audio or the sound
      # module is not open.
      #
      # === Example
      #
      #   Lota::Audio::Source.new("sounds/click.wav", :static)
      def self.new(filename, type)
        from_native(Native::Audio.new_source(filename, EnumName.of(type)))
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
