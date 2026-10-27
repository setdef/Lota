# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Sound
    # Every sample of a sound, decoded, matching LÖVE's SoundData class
    # (src/modules/sound/SoundData.h).
    #
    # A SoundData holds a sound as a run of sample frames, one sample for
    # each channel in each, at its sample rate: a sound decoded from a
    # file, or silence the game writes into, sample by sample, to make a
    # sound of its own. Each sample reads and writes as a Float from -1 to
    # 1, however many bits it is stored in.
    #
    # LÖVE's SoundData is a Data, so it also has Data's #size and #string,
    # which Lota defines here (ADR 001's rule 1 would name their module
    # Lota::Data, which waits for the maintainer: inside Lota it would hide
    # Ruby's own Data class).
    #
    # === Example
    #
    #   beep = Lota::Sound::SoundData.new(44_100 / 10, 44_100, 16, 1)
    #   beep.sample_count.times do |i|
    #     beep.sample = i, Math.sin(i * 2 * Math::PI * 440 / 44_100) * 0.5
    #   end
    class SoundData
      include Object

      # The engine's SoundData, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a SoundData the engine made. :nodoc:
      def self.from_native(native)
        sound_data = allocate
        sound_data.instance_variable_set(:@native, native)
        sound_data
      end

      # Makes a SoundData, matching love.sound.newSoundData
      # (src/modules/sound/wrap_Sound.cpp, w_newSoundData), in one of two
      # forms:
      #
      # - <tt>SoundData.new(samples, sample_rate = 44100, bit_depth = 16,
      #   channels = 2)</tt>: silence of +samples+ sample frames, as an
      #   Integer, at +sample_rate+ frames a second, with +bit_depth+ bits,
      #   8 or 16, in each sample, and +channels+ channels.
      # - <tt>SoundData.new(file)</tt>: every sample of a sound file, as a
      #   String path in the game's folder or its save directory, a
      #   Lota::Filesystem::FileData, or a Lota::Sound::Decoder, which
      #   decodes all it has left.
      #
      # Raises RuntimeError, with LÖVE's message, for a sample count,
      # sample rate, or channel count below 1 or a bit depth but 8 or 16,
      # for a file the engine cannot open or decode, and when the sound
      # module is not open.
      #
      # === Examples
      #
      #   Lota::Sound::SoundData.new("sounds/click.wav")
      #   Lota::Sound::SoundData.new(1378, 44_100, 16, 1)
      def self.new(source, sample_rate = 44_100, bit_depth = 16, channels = 2)
        native = if source.is_a?(Numeric)
          Native::Sound.new_sound_data(source, sample_rate, bit_depth, channels)
        else
          decoder = source.is_a?(Decoder) ? source : Decoder.new(source)
          Native::Sound.new_sound_data_from_decoder(decoder.native)
        end
        from_native(native)
      end

      # How many channels the sound has, as an Integer: 1 for mono, 2 for
      # stereo, matching SoundData:getChannelCount
      # (src/modules/sound/wrap_SoundData.cpp, w_SoundData_getChannelCount).
      #
      # === Example
      #
      #   sound.channel_count # => 2
      def channel_count
        @native.channel_count
      end

      # How many bits each sample has, as an Integer, 8 or 16, matching
      # SoundData:getBitDepth (src/modules/sound/wrap_SoundData.cpp,
      # w_SoundData_getBitDepth).
      #
      # === Example
      #
      #   sound.bit_depth # => 16
      def bit_depth
        @native.bit_depth
      end

      # How many sample frames the sound plays a second, as an Integer,
      # matching SoundData:getSampleRate
      # (src/modules/sound/wrap_SoundData.cpp, w_SoundData_getSampleRate).
      #
      # === Example
      #
      #   sound.sample_rate # => 44100
      def sample_rate
        @native.sample_rate
      end

      # How many sample frames the sound has, one sample for each channel
      # in each, as an Integer, matching SoundData:getSampleCount
      # (src/modules/sound/wrap_SoundData.cpp, w_SoundData_getSampleCount).
      #
      # === Example
      #
      #   sound.sample_count # => 2927
      def sample_count
        @native.sample_count
      end

      # How many seconds the sound lasts, as a Float, matching
      # SoundData:getDuration (src/modules/sound/wrap_SoundData.cpp,
      # w_SoundData_getDuration).
      #
      # === Example
      #
      #   sound.duration # => 0.06637188047170639
      def duration
        @native.duration
      end

      # How many bytes the samples take, as an Integer, matching
      # Data:getSize (src/modules/data/wrap_Data.cpp, w_Data_getSize).
      #
      # === Example
      #
      #   sound.size # => 11708
      def size
        @native.size
      end

      # The samples' bytes, as LÖVE stores them, as a String, matching
      # Data:getString (src/modules/data/wrap_Data.cpp, w_Data_getString):
      # each sample frame's samples, channel by channel, 16-bit ones signed
      # and 8-bit ones unsigned, in the machine's byte order.
      #
      # [offset] Integer byte to start at.
      # [size] Integer bytes to take; every byte from +offset+ on when
      #   +nil+ or left out.
      #
      # The String is in Ruby's default external encoding, as File.read's
      # is, holding the bytes as they are. Raises RuntimeError, with LÖVE's
      # message, for a +size+ below 1, or bytes outside the SoundData.
      #
      # === Example
      #
      #   sound.string(0, 4).bytesize # => 4
      def string(offset = 0, size = nil)
        @native.string(offset, size)
      end

      # Sample +i+ of the sound, from -1 to 1, as a Float, matching
      # SoundData:getSample as LÖVE runs it, in the LuaJIT code that takes
      # over from its C++ (src/modules/sound/wrap_SoundData.lua).
      #
      # [i] Float or Integer position of the sample, rounded down: of the
      #   sample frame when +channel+ is given, and among every channel's
      #   samples, frame after frame, when it is not.
      # [channel] Integer channel, counting from 1, or +nil+.
      #
      # Raises RuntimeError, with LÖVE's message, for a channel the sound
      # does not have, and for a sample outside it.
      #
      # === Examples
      #
      #   sound.sample(0)    # => -0.00021362956633198035
      #   sound.sample(0, 2) # => 0.00027466658528397473
      def sample(i, channel = nil)
        @native.sample(i, channel)
      end

      # Sets a sample of the sound, matching SoundData:setSample as LÖVE
      # runs it, in the LuaJIT code that takes over from its C++
      # (src/modules/sound/wrap_SoundData.lua), whose several values rule 6
      # of ADR 001 makes one Array.
      #
      # [arguments] An Array of the sample's position and its Float or
      #   Integer value, from -1 to 1, or of its position, its Integer
      #   channel, counting from 1, and its value. The position is rounded
      #   down, as #sample rounds it.
      #
      # Raises RuntimeError, with LÖVE's message, for a channel the sound
      # does not have, and for a sample outside it.
      #
      # === Examples
      #
      #   sound.sample = 0, 0.5
      #   sound.sample = 0, 2, -0.5
      def sample=(arguments)
        unless arguments.size.between?(2, 3)
          raise ArgumentError, "wrong number of arguments (given #{arguments.size}, expected 2..3)"
        end

        @native.set_sample(arguments)
      end

      # Copies +count+ sample frames of +source+, from frame +source_start+,
      # into this SoundData from frame +destination_start+, matching
      # SoundData:copyFrom (src/modules/sound/wrap_SoundData.cpp,
      # w_SoundData_copyFrom).
      #
      # [source] Lota::Sound::SoundData with as many channels.
      # [source_start] Integer first frame of +source+ to copy.
      # [count] Integer how many frames.
      # [destination_start] Integer frame they go to.
      #
      # Samples of another bit depth are converted. Raises RuntimeError,
      # with LÖVE's message, for a +source+ with another number of
      # channels, and for frames outside either SoundData.
      #
      # === Example
      #
      #   loud.copy_from(quiet, 0, 100)
      def copy_from(source, source_start, count, destination_start = 0)
        @native.copy_from(source.native, source_start, count, destination_start)
      end

      # A new SoundData of +length+ sample frames of this one, from frame
      # +start+, matching SoundData:slice
      # (src/modules/sound/wrap_SoundData.cpp, w_SoundData_slice).
      #
      # [start] Integer first frame.
      # [length] Integer how many frames; -1, or left out, for every frame
      #   from +start+ on.
      #
      # Raises RuntimeError, with LÖVE's message, for a +length+ of 0 and
      # for frames outside this SoundData.
      #
      # === Example
      #
      #   sound.slice(0, 100).sample_count # => 100
      def slice(start, length = -1)
        SoundData.from_native(@native.slice(start, length))
      end
    end
  end
end
