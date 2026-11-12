# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's sound.lua
# (test/fixtures/flash_blip/game/sound.lua, lines 1-92), by the rules of
# doc/contributors/design/translation.md: love.sound.newSoundData and
# love.audio.newSource become Lota::Sound::SoundData.new and
# Lota::Audio::Source.new (rule 2), setVolume a writer (rule 5), and
# setSample a writer that takes the index and the value (rule 6). The
# module's Lua locals are its instance variables, and Sound:load, which
# calls the module's functions through self, is Sound.load. The sounds'
# names are the game's own, so they stay Strings, and each sound's
# parameters, a table read by field, are a SoundParams.
#
# The samples are the Lua's doubles: the frequencies stay whole numbers,
# as Lua's doubles hold them, and every division whose operands are both
# whole divides as Floats.

require "settings"
require "lua"

module Sound
  # A sound's parameters, read as params.start_freq and so on.
  SoundParams = Struct.new(:start_freq, :end_freq, :duration, :volume)

  @sounds = {}
  @is_muted = !Settings.is_sfx_enabled

  # Enable to adjust SE volume
  def self.set_volume(volume)
    volume = (Lua.tonumber(volume) || 1.0).clamp(0, 1)
    volume = 0 if volume < 0.005
    Settings.is_sfx_volume = volume

    final_volume = @is_muted ? 0 : volume

    @sounds.each_value do |sound|
      sound.volume = final_volume
    end
  end

  def self.toggle_mute(mute)
    @is_muted = mute

    final_volume = @is_muted ? 0 : Settings.is_sfx_volume

    @sounds.each_value do |sound|
      sound.volume = final_volume
    end
  end

  # Generates a sound wave procedurally.
  def self.generate_sound(name)
    sound_params = {
      "blip" => SoundParams.new(800, 1600, 0.07, 0.4),
      "explosion" => SoundParams.new(200, 50, 0.2, 0.6),
      "star_powerup" => SoundParams.new(1000, 2000, 0.15, 0.4),
      "slowdown_powerup" => SoundParams.new(2000, 1000, 0.15, 0.4),
      "phaseshift_powerup" => SoundParams.new(500, 2500, 0.2, 0.4),
      "teleport" => SoundParams.new(1500, 800, 0.1, 0.4),
      "bolt_powerup" => SoundParams.new(2500, 500, 0.2, 0.4),
      "debuff_emp" => SoundParams.new(300, 100, 0.25, 0.4),
    }

    params = sound_params[name]
    return unless params

    sample_rate = 44100
    bit_depth = 16
    channels = 1
    sample_count = (sample_rate * params.duration).floor
    sound_data = Lota::Sound::SoundData.new(sample_count, sample_rate, bit_depth, channels)

    sample_count.times do |i|
      time = i.fdiv(sample_rate)
      freq = if name == "blip"
        params.start_freq + ((params.end_freq - params.start_freq) * (time / params.duration))
      else
        params.start_freq * (params.end_freq.fdiv(params.start_freq) ** (time / params.duration))
      end
      value = Math.sin(2 * Math::PI * freq * time).positive? ? params.volume : -params.volume
      sound_data.sample = i, value
    end

    @sounds[name] = Lota::Audio::Source.new(sound_data)
  end

  def self.play(name)
    sound = @sounds[name]
    return unless sound

    sound.stop
    sound.volume = @is_muted ? 0 : Settings.is_sfx_volume
    sound.play
  end

  def self.load
    generate_sound("explosion")
    generate_sound("blip")
    generate_sound("star_powerup")
    generate_sound("slowdown_powerup")
    generate_sound("phaseshift_powerup")
    generate_sound("teleport")
    generate_sound("bolt_powerup")
    generate_sound("debuff_emp")
  end
end
# SPDX-SnippetEnd
