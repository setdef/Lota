# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

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
      Native::Audio.play(source.native)
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
      source ? Native::Audio.stop_source(source.native) : Native::Audio.stop
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
    # optionally z, 0 by default, as an Array (ADR 001, rule 6).
    #
    # A mono Source plays louder and from its side the nearer and the more
    # to that side of the listener it is. Raises TypeError for a value that
    # is not a number.
    #
    # === Example
    #
    #   Lota::Audio.position = player.x, player.y
    def self.position=(position)
      x, y, z = Audio::Source.numbers(position)
      Native::Audio.set_position(Source.number(x), Source.number(y), Source.number(z, 0))
    end

    # The listener's position, as an Array of three Floats (ADR 001, rule
    # 4), matching love.audio.getPosition
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
    # (ADR 001, rule 6).
    #
    # Raises TypeError for fewer than six numbers, or one that is not a
    # number.
    #
    # === Example
    #
    #   Lota::Audio.orientation = 0, 0, -1, 0, 1, 0
    def self.orientation=(orientation)
      fx, fy, fz, ux, uy, uz = Source.numbers(orientation)
      Native::Audio.set_orientation([
        Source.number(fx),
        Source.number(fy),
        Source.number(fz),
        Source.number(ux),
        Source.number(uy),
        Source.number(uz),
])
    end

    # The listener's forward and up vectors, as an Array of six Floats (ADR
    # 001, rule 4), matching love.audio.getOrientation
    # (src/modules/audio/wrap_Audio.cpp, w_getOrientation).
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
      x, y, z = Audio::Source.numbers(velocity)
      Native::Audio.set_velocity(Source.number(x), Source.number(y), Source.number(z, 0))
    end

    # The listener's velocity, as an Array of three Floats (ADR 001, rule
    # 4), matching love.audio.getVelocity
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
    # +:linearclamped+, +:exponent+, or +:exponentclamped+ (ADR 001, rule
    # 9).
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
  end
end
