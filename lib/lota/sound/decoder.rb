# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Sound
    # Reads a sound file a piece at a time, matching LÖVE's Decoder class
    # (src/modules/sound/Decoder.h).
    #
    # Music is long, so a game that streams it decodes it as it plays,
    # never all at once. A Decoder knows the sound's format before it
    # decodes any of it, and #decode gives the next piece as a
    # Lota::Sound::SoundData until there is no more.
    #
    # === Example
    #
    #   decoder = Lota::Sound::Decoder.new("music/theme.ogg")
    #   while (piece = decoder.decode)
    #     piece.sample_count # => 4096
    #   end
    class Decoder
      include Object

      # The bytes a Decoder decodes at a time when none are given, as
      # LÖVE's Decoder::DEFAULT_BUFFER_SIZE (src/modules/sound/Decoder.h).
      DEFAULT_BUFFER_SIZE = 16_384

      # The engine's Decoder, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Decoder the engine made. :nodoc:
      def self.from_native(native)
        decoder = allocate
        decoder.instance_variable_set(:@native, native)
        decoder
      end

      # Makes a Decoder for a sound file, matching love.sound.newDecoder
      # (src/modules/sound/wrap_Sound.cpp, w_newDecoder).
      #
      # [file] String path of the file, found in the game's folder or its
      #   save directory, or a Lota::Filesystem::FileData of its bytes: a
      #   WAVE, Ogg Vorbis, MP3, FLAC, or tracker module file, which LÖVE
      #   tells apart by what is in it, not by its name.
      # [buffer_size] Integer bytes to decode at a time.
      # [type] For a file name, Symbol <tt>:file</tt>, which decodes from
      #   the open file, or <tt>:memory</tt>, which reads all of it first
      #   (ADR 001, rule 9); +nil+ or left out for <tt>:file</tt>. A
      #   FileData is decoded from memory, whatever +type+ says.
      #
      # Raises ArgumentError, with LÖVE's message, for a +type+ LÖVE does
      # not know, and RuntimeError for a file it cannot open or decode, and
      # when the sound module is not open.
      #
      # === Examples
      #
      #   Lota::Sound::Decoder.new("music/theme.ogg")
      #   Lota::Sound::Decoder.new("music/theme.ogg", 4096, :memory)
      def self.new(file, buffer_size = DEFAULT_BUFFER_SIZE, type = nil)
        native = if file.is_a?(Filesystem::FileData)
          Native::Sound.new_decoder_from_data(file.native, buffer_size)
        else
          Native::Sound.new_decoder(file, buffer_size, type && EnumName.of(type))
        end
        from_native(native)
      end

      # Makes this Decoder, a copy of +source+ by Ruby's +clone+ or +dup+,
      # LÖVE's copy, matching Decoder:clone
      # (src/modules/sound/wrap_Decoder.cpp, w_Decoder_clone): a new
      # Decoder of the same sound, which decodes it from its start however
      # far +source+ has decoded (ADR 001, section 7).
      #
      # === Example
      #
      #   copy = decoder.dup
      #   copy.decode.sample_count # => 2927
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # Decodes the next piece of the sound, matching Decoder:decode
      # (src/modules/sound/wrap_Decoder.cpp, w_Decoder_decode).
      #
      # Returns a new Lota::Sound::SoundData of the piece, in the
      # Decoder's format, or +nil+ once the whole sound is decoded.
      #
      # === Example
      #
      #   decoder.decode.sample_count # => 2927
      def decode
        native = @native.decode
        native && SoundData.from_native(native)
      end

      # How many channels the sound has, as an Integer: 1 for mono, 2 for
      # stereo, matching Decoder:getChannelCount
      # (src/modules/sound/wrap_Decoder.cpp, w_Decoder_getChannelCount).
      #
      # === Example
      #
      #   decoder.channel_count # => 2
      def channel_count
        @native.channel_count
      end

      # How many bits each sample has, as an Integer, 8 or 16, matching
      # Decoder:getBitDepth (src/modules/sound/wrap_Decoder.cpp,
      # w_Decoder_getBitDepth).
      #
      # === Example
      #
      #   decoder.bit_depth # => 16
      def bit_depth
        @native.bit_depth
      end

      # How many sample frames the sound plays a second, as an Integer,
      # matching Decoder:getSampleRate (src/modules/sound/wrap_Decoder.cpp,
      # w_Decoder_getSampleRate).
      #
      # === Example
      #
      #   decoder.sample_rate # => 44100
      def sample_rate
        @native.sample_rate
      end

      # How many seconds the whole sound lasts, as a Float, or -1 when the
      # decoder cannot tell, matching Decoder:getDuration
      # (src/modules/sound/wrap_Decoder.cpp, w_Decoder_getDuration).
      #
      # === Example
      #
      #   decoder.duration # => 0.0663718820861678
      def duration
        @native.duration
      end
    end
  end
end
