# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Audio
    # A microphone or another device that records sound, matching LÖVE's
    # RecordingDevice class (src/modules/audio/RecordingDevice.h), which
    # Lota::Audio.recording_devices lists.
    #
    # A device records into a buffer of its own once it starts, which
    # #data empties. Recording runs across frames, as a Source plays, so
    # #start and #stop are not a pair with a block form
    # (doc/contributors/design/translation.md).
    #
    # === Example
    #
    #   mic = Lota::Audio.recording_devices.first
    #   mic.start(32_000, 44_100, 16, 1)
    #   # ... frames later
    #   sound = mic.stop # => a Lota::Sound::SoundData, or nil
    class RecordingDevice < Object
      # Wraps a RecordingDevice the engine made. :nodoc:
      private_class_method def self.from_native(native)
        device = allocate
        device.instance_variable_set(:@native, native)
        device
      end

      # Starts recording, matching RecordingDevice:start
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_start), and returns whether it started.
      #
      # [samples] Integer most samples to hold; with nothing given, the
      #   device records with the settings it last recorded with.
      # [samplerate] Integer samples a second; 8000 when left out.
      # [bitdepth] Integer 8 or 16; 16 when left out.
      # [channels] Integer 1 or 2; 1 when left out.
      #
      # Raises RuntimeError with LÖVE's message for settings the device
      # cannot record with.
      #
      # === Example
      #
      #   mic.start(32_000, 44_100) # => true
      def start(samples = nil, samplerate = nil, bitdepth = nil, channels = nil)
        @native.start(samples, samplerate, bitdepth, channels)
      end

      # Stops recording, matching RecordingDevice:stop
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_stop), and returns what it recorded since #data
      # last emptied its buffer, as a Lota::Sound::SoundData, or +nil+
      # when it recorded nothing.
      #
      # === Example
      #
      #   mic.stop # => #<Lota::Sound::SoundData>
      def stop
        sound(@native.stop)
      end

      # What the device recorded since this was last called, matching
      # RecordingDevice:getData
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_getData), as a Lota::Sound::SoundData, or +nil+
      # when it recorded nothing; it empties the device's buffer.
      #
      # === Example
      #
      #   mic.data # => nil
      def data
        sound(@native.data)
      end

      # How many samples the device holds, matching
      # RecordingDevice:getSampleCount
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_getSampleCount).
      #
      # === Example
      #
      #   mic.sample_count # => 0
      def sample_count
        @native.sample_count
      end

      # The device's samples a second, matching
      # RecordingDevice:getSampleRate
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_getSampleRate).
      #
      # === Example
      #
      #   mic.sample_rate # => 8000
      def sample_rate
        @native.sample_rate
      end

      # The bits of each of the device's samples, matching
      # RecordingDevice:getBitDepth
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_getBitDepth).
      #
      # === Example
      #
      #   mic.bit_depth # => 16
      def bit_depth
        @native.bit_depth
      end

      # The device's channels, matching RecordingDevice:getChannelCount
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_getChannelCount).
      #
      # === Example
      #
      #   mic.channel_count # => 1
      def channel_count
        @native.channel_count
      end

      # The device's name, matching RecordingDevice:getName
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_getName).
      #
      # === Example
      #
      #   mic.name # => "MacBook Pro Microphone"
      def name
        @native.name
      end

      # Whether the device is recording, matching
      # RecordingDevice:isRecording
      # (src/modules/audio/wrap_RecordingDevice.cpp,
      # w_RecordingDevice_isRecording).
      #
      # === Example
      #
      #   mic.recording? # => false
      def recording?
        @native.recording?
      end

      # The SoundData wrapping +native+, or +nil+. :nodoc:
      private def sound(native)
        native && Sound::SoundData.__send__(:from_native, native)
      end
    end
  end
end
