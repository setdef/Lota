# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "sound/decoder"
require_relative "sound/sound_data"

module Lota
  # The decoders that read sound files, translated from love.sound.
  #
  # LÖVE reads a WAVE, Ogg Vorbis, MP3, FLAC, or tracker module file with
  # its sound module, and love.audio asks it to whenever it makes a Source
  # from a file. A game can also decode a file itself: a
  # Lota::Sound::Decoder reads one a piece at a time, and a
  # Lota::Sound::SoundData holds every sample of one, or of silence the
  # game fills in, which it can read and change sample by sample.
  #
  # Lota opens it before Lota::Audio, as LÖVE does, unless your settings
  # turn it off (<tt>t.modules.sound = false</tt>), and then neither these
  # classes nor Lota::Audio::Source.new can read a file.
  #
  # === Example
  #
  #   sound = Lota::Sound::SoundData.new("sounds/click.wav")
  #   sound.sample_rate # => 44100
  #   sound.sample(0)   # => 0.0
  module Sound
  end
end
