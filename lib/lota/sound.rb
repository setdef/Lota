# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The decoders that read sound files, translated from love.sound.
  #
  # LÖVE reads a WAVE, Ogg Vorbis, MP3, FLAC, or tracker module file with
  # its sound module, and love.audio asks it to whenever it makes a Source
  # from a file. Lota opens it before Lota::Audio, as LÖVE does, unless
  # your settings turn it off (<tt>t.modules.sound = false</tt>), and then
  # Lota::Audio::Source.new cannot read a file. Its own functions, which
  # decode a file into samples a game can read, come later.
  #
  # === Example
  #
  #   lota.sound # => Lota::Sound
  module Sound
  end
end
