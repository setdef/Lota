# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Says it reached Lota.load, plays half a second of a quiet 440 Hz tone,
# unless MACAUDIO_SILENT=1, and quits with 0 after two seconds.
def Lota.load(_arguments)
  puts "load: reached Lota.load, fused: #{Lota::Filesystem.fused?}"
  rate = 44_100
  count = rate / 2
  sound = Lota::Sound::SoundData.new(count, rate, 16, 1)
  count.times { |i| sound.sample = i, 0.2 * Math.sin(2 * Math::PI * 440 * i / rate) }
  @source = Lota::Audio::Source.new(sound)
  @source.play unless ENV["MACAUDIO_SILENT"] == "1"
  puts "load: playing #{@source.playing?}, #{Lota::Audio.active_source_count} source(s) active"
  @elapsed = 0.0
end

def Lota.update(dt)
  @elapsed += dt
  return if @elapsed < 2

  puts "update: quitting after #{@elapsed.round(2)} s"
  Lota::Event.quit(0)
end
