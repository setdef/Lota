# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Audio
    # Sources that play the sound a game queues on them as it makes it,
    # translating love.audio.newQueueableSource
    # (src/modules/audio/wrap_Audio.cpp, w_newQueueableSource). LÖVE has
    # no QueueableSource class: the factory makes a Source of the type
    # <tt>:queue</tt>, so this is a module whose +new+ returns a Source and
    # whose <tt>===</tt> asks a Source's type, as
    # Lota::Graphics::Canvas asks whether a Texture is a canvas (ADR 001,
    # rule 2).
    #
    # === Example
    #
    #   synth = Lota::Audio::QueueableSource.new(44_100, 16, 1)
    #   synth.queue(Lota::Sound::SoundData.new(1024, 44_100, 16, 1))
    #   synth.play
    #   Lota::Audio::QueueableSource === synth # => true
    module QueueableSource
      # A new Source that plays what is queued on it, matching
      # love.audio.newQueueableSource.
      #
      # [samplerate] Integer samples a second of the sound it plays.
      # [bitdepth] Integer 8 or 16.
      # [channels] Integer 1 or 2.
      # [buffers] Integer most buffers it queues at once; the engine's
      #   default when 0 or left out.
      #
      # Raises RuntimeError with LÖVE's message for settings the engine
      # cannot play.
      #
      # === Example
      #
      #   Lota::Audio::QueueableSource.new(44_100, 16, 2, 8).get_type # => :queue
      def self.new(samplerate, bitdepth, channels, buffers = 0)
        Source.from_native(Native::Audio.new_queueable_source(samplerate, bitdepth, channels, buffers))
      end

      # Whether +object+ is a Source that newQueueableSource could have
      # made: one of the type <tt>:queue</tt>.
      #
      # === Example
      #
      #   Lota::Audio::QueueableSource === Lota::Audio::Source.new("click.ogg", :static) # => false
      def self.===(object)
        object.is_a?(Source) && object.get_type == :queue
      end
    end
  end
end
