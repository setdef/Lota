# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's music.lua
# (test/fixtures/flash_blip/game/music.lua, lines 1-359), by the rules of
# doc/contributors/design/translation.md: love.audio.newSource and
# newQueueableSource become Lota::Audio::Source.new and
# Lota::Audio::QueueableSource.new, and love.sound.newSoundData
# Lota::Sound::SoundData.new (rule 2), with the source type a symbol
# (rule 9); setLooping and setVolume become writers (rule 5), setSample a
# writer that takes the index and the value (rule 6), isRunning running?
# (rule 8), and getFreeBufferCount free_buffer_count (rules 3 and 13).
# The module's Lua locals are its instance variables. love.thread is
# reached through threads.rb, as Threads.new_thread and Threads.channel.
#
# The music is generated in a thread, from a Lua string that becomes a
# Ruby string of the same code. It generates 1,572,864 samples, so the
# Ruby works on Integers where Lua's doubles only ever hold whole
# numbers there (the playback time steps by 1 from 0): an Integer's
# division and % floor exactly as math.floor of the double quotient
# does, since every quotient that is not whole lies further than a
# double's rounding error from the next whole number, and Lua's loops
# over the low six bits of non-negative whole numbers are ^ and |. The
# fractions, the bass, the notes' powers of two, the envelope, and the
# sample, are Floats computed in Lua's order. The web path, which steps
# by 4.0, keeps the Lua's floor-and-divide arithmetic on Floats as it is.

require "settings"
require "threads"
require "lua"

module Music
  def self.bytebeat1(t)
    y = t % 16384
    drum = 0
    if y != 0
      div = 3000.0 / y
      drum = (div.floor % 2) * 35
    end
    idx = (t / 65536.0).floor % 4
    mults = "6689"
    mult = Lua.tonumber(mults.byteslice(idx, 1))
    temp = t * mult / 24.0
    x = temp.floor % 128
    bass = x * y / 40000.0
    t8 = (t / 256.0).floor
    t10 = (t / 1024.0).floor
    t14 = (t / 16384.0).floor
    t8_low = t8 % 64
    t10_low = t10 % 64
    t14_low = t14 % 64
    x_low = x % 64
    xor_low = 0
    pow = 1
    a = t8_low
    b = t10_low
    6.times do
      ba = a % 2
      bb = b % 2
      xor_low += pow if ba != bb
      a = (a / 2.0).floor
      b = (b / 2.0).floor
      pow *= 2
    end
    bor1 = 0
    a = xor_low
    b = t14_low
    pow = 1
    6.times do
      ba = a % 2
      bb = b % 2
      bor1 += pow if ba == 1 || bb == 1
      a = (a / 2.0).floor
      b = (b / 2.0).floor
      pow *= 2
    end
    lead = 0
    a = bor1
    b = x_low
    pow = 1
    6.times do
      ba = a % 2
      bb = b % 2
      lead += pow if ba == 1 || bb == 1
      a = (a / 2.0).floor
      b = (b / 2.0).floor
      pow *= 2
    end
    drum + bass + lead
  end
  private_class_method :bytebeat1

  # Samples one step of a melody string as a square-wave note (see bytebeat2)
  def self.sample_note(pattern, octave, rate_exponent, period, t)
    idx = (t / (2.0 ** rate_exponent)).floor % period
    char_code = pattern.getbyte(idx) || 32
    return 0 if char_code == 32

    (t % 32) * (2.0 ** ((char_code / 12.0) - octave))
  end
  private_class_method :sample_note

  def self.bytebeat2(t)
    part1 = sample_note("0 0     7 7     037:<<", 6, 10, 32, t)
    part2 = 0
    if (t / 4096.0).floor % 2 == 1
      env = (4096 - (t % 4096)) / 4096.0
      part2 = sample_note("037", 4, 8, 3, t) * env
    end
    part1 + part2
  end
  private_class_method :bytebeat2

  def self.combined_bytebeat(t)
    bytebeat1(t) + bytebeat2(t)
  end
  private_class_method :combined_bytebeat

  def self.generate_buffer_samples(buffer, start_playback_time, num_samples, step, amplitude, cycle_length)
    current_playback_time = start_playback_time
    num_samples.times do |i|
      s = combined_bytebeat(current_playback_time)
      sample = ((s / 128.0) - 1) * amplitude
      buffer.sample = i, sample
      current_playback_time += step
      current_playback_time -= cycle_length if current_playback_time >= cycle_length
    end
    current_playback_time
  end
  private_class_method :generate_buffer_samples

  def self.create_audio_source(sound_data, is_muted)
    source = Lota::Audio::Source.new(sound_data, :static)
    source.looping = true
    source.volume = is_muted ? 0 : Settings.is_music_volume
    source.play
    source
  end
  private_class_method :create_audio_source

  @source = nil
  @queue_source = nil
  @is_generating = false
  @is_muted = !Settings.is_music_enabled
  @playback_time = 0
  @cycle_length = 1572864
  @full_rate = 32000
  @web_rate = 8000
  @amplitude = 0.2
  @buffer_size = 512
  @web_buffer_count = 256
  @web_step = @full_rate.fdiv(@web_rate)

  @generation_thread = nil
  @sound_data_channel = Threads.channel("sound_data")
  @is_generating_sound_data = false
  @is_ready = false

  def self.stop
    if @source
      @source.stop
      @source = nil
    end
    if @queue_source
      @queue_source.stop
      @queue_source = nil
    end
    @is_generating = false
    @is_generating_sound_data = false
    @is_ready = false
    return unless @generation_thread

    @generation_thread.wait
    @generation_thread = nil
  end

  # Enable to adjust music volume
  def self.toggle_mute(mute)
    @is_muted = mute

    final_volume = @is_muted ? 0 : Settings.is_music_volume

    @source&.volume = final_volume
    @queue_source&.volume = final_volume
  end

  # The thread's code, as Lota::Thread runs it: in a Ractor of its own,
  # so it holds everything it needs. Its helper functions are methods of
  # the object it runs in.
  @generate_sound_data_code = <<~RUBY
    # require("love.sound"): Lota has its sound module wherever this runs.

    # Lota::Thread hands values back on its channels once Lota has threads;
    # until then this runs inline, and threads.rb's channels do.
    channel = Lota.const_defined?(:Thread, false) ? Lota::Thread.method(:channel) : Threads.method(:channel)

    rate = 32000
    step = 1
    total_samples = 1572864
    bits = 16
    channels = 1
    amplitude = 0.2
    cycle_length = 1572864

    # The low +bits+ bits of a XOR b, as Lua's loop over them computes for
    # the non-negative whole numbers it is given.
    def xor_bits(a, b, bits)
      (a ^ b) & ((1 << bits) - 1)
    end

    # The low +bits+ bits of a OR b, likewise.
    def or_bits(a, b, bits)
      (a | b) & ((1 << bits) - 1)
    end

    # t is a whole number, so Integer division floors as Lua's math.floor
    # of the double quotient does.
    def bytebeat1(t)
      y = t % 16384
      drum = 0
      if y != 0
        div = 3000 / y
        drum = (div % 2) * 35
      end
      idx = (t / 65536) % 4
      mults = "6689"
      # tonumber(mults:sub(idx + 1, idx + 1)), the digit's value
      mult = mults.getbyte(idx) - 48
      x = (t * mult / 24) % 128
      bass = x * y / 40000.0
      t8 = t / 256
      t10 = t / 1024
      t14 = t / 16384
      t8_low = t8 % 64
      t10_low = t10 % 64
      t14_low = t14 % 64
      x_low = x % 64
      xor_low = xor_bits(t8_low, t10_low, 6)
      bor1 = or_bits(xor_low, t14_low, 6)
      lead = or_bits(bor1, x_low, 6)
      drum + bass + lead
    end

    def sample_note(pattern, octave, rate_exponent, period, t)
      idx = (t >> rate_exponent) % period
      char_code = pattern.getbyte(idx) || 32
      return 0 if char_code == 32

      (t % 32) * (2.0**((char_code / 12.0) - octave))
    end

    def bytebeat2(t)
      part1 = sample_note("0 0     7 7     037:<<", 6, 10, 32, t)
      part2 = 0
      if (t / 4096) % 2 == 1
        env = (4096 - (t % 4096)) / 4096.0
        part2 = sample_note("037", 4, 8, 3, t) * env
      end
      part1 + part2
    end

    def combined_bytebeat(t)
      bytebeat1(t) + bytebeat2(t)
    end

    sound_data = Lota::Sound::SoundData.new(total_samples, rate, bits, channels)

    current_playback_time = 0
    total_samples.times do |i|
      s = combined_bytebeat(current_playback_time)
      current_playback_time += step
      current_playback_time -= cycle_length if current_playback_time >= cycle_length
      sample = ((s / 128.0) - 1) * amplitude
      sound_data.sample = i, sample
    end

    channel.call("sound_data").push(sound_data)
  RUBY

  def self.play
    if @source
      @source.stop
      @source = nil
    end
    if @queue_source
      @queue_source.stop
      @queue_source = nil
    end
    @is_generating = false
    @is_ready = false
    @playback_time = 0

    is_web = Settings.is_web

    if !is_web
      unless @is_generating_sound_data
        @generation_thread = Threads.new_thread(@generate_sound_data_code)
        @generation_thread.start
        @is_generating_sound_data = true
      end
    else
      @queue_source = Lota::Audio::QueueableSource.new(@web_rate, 16, 1, @web_buffer_count)
      @queue_source.volume = @is_muted ? 0 : Settings.is_music_volume

      while @queue_source.free_buffer_count.positive?
        buffer = Lota::Sound::SoundData.new(@buffer_size, @web_rate, 16, 1)
        @playback_time = generate_buffer_samples(buffer, @playback_time, @buffer_size, @web_step, @amplitude,
          @cycle_length)
        @queue_source.queue(buffer)
      end

      @queue_source.play
      @is_generating = true
      @is_ready = true
    end
  end

  def self.set_volume(volume)
    volume = (Lua.tonumber(volume) || 1.0).clamp(0, 1)
    volume = 0 if volume < 0.005
    Settings.is_music_volume = volume

    final_volume = @is_muted ? 0 : volume

    @source&.volume = final_volume

    @queue_source&.volume = final_volume
  end

  def self.update(_dt)
    if !@is_generating || !@queue_source
      if !Settings.is_web && @is_generating_sound_data && @generation_thread
        return if @generation_thread.running?

        sound_data = @sound_data_channel.pop
        if sound_data
          @source = create_audio_source(sound_data, @is_muted)
          @is_generating_sound_data = false
          @is_ready = true
          @generation_thread.wait
          @generation_thread = nil
        end
        return

      end
      return
    end

    while @queue_source.free_buffer_count.positive?
      buffer = Lota::Sound::SoundData.new(@buffer_size, @web_rate, 16, 1)
      @playback_time = generate_buffer_samples(buffer, @playback_time, @buffer_size, @web_step, @amplitude,
        @cycle_length)
      @queue_source.queue(buffer)
    end
  end

  def self.is_ready
    @is_ready
  end
end
# SPDX-SnippetEnd
