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
  end
end
