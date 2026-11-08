# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Restarts once, as LÖVE's fused game restarts, with its process id as
# the value, and says each run's process id and value, then says whether it runs fused, with YJIT, and where it
# saves, saves a file, plays a tenth of a second of silence through the
# gem's OpenAL Soft, and quits with status 3, so an exit status of 0
# cannot pass by accident.
def Lota.load(_arguments)
  puts "run: #{Process.pid} #{Lota.restart.inspect}"
  return Lota::Event.restart(Process.pid) if Lota.restart.nil?

  puts "fused: #{Lota::Filesystem.fused?}"
  puts "yjit: #{defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : 'absent'}"
  puts "identity: #{Lota::Filesystem.identity}"
  puts "saved: #{Lota::Filesystem.write('check.txt', 'saved').first}"
  puts "save directory: #{Lota::Filesystem.save_directory}"
  Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
  puts "#{Lota::System.os}: #{Lota::Audio.active_source_count} source playing"
  Lota::Event.quit(3)
end
