# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"

# A method YJIT compiles once it is called often enough.
def sandbox_hot(number) = (number * 3) + 1

# Restarts once, as test/games/fuse does, unless FUSE_SANDBOX_RESTART
# is 0, then says whether it runs
# fused, with YJIT, and whether YJIT compiled and entered machine code;
# whether it runs in an App Sandbox container and can list the real home
# folder; saves a file and reads it back from the save directory; plays
# silence; and quits with status 3.
def Lota.load(_arguments)
  puts "run: #{Process.pid} #{Lota.restart.inspect}"
  return Lota::Event.restart(Process.pid) if Lota.restart.nil? && ENV["FUSE_SANDBOX_RESTART"] != "0"

  puts "fused: #{Lota::Filesystem.fused?}"
  puts "yjit: #{defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : 'absent'}"
  total = 0
  20_000.times { |number| total += sandbox_hot(number) }
  stats = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? RubyVM::YJIT.runtime_stats : {}
  keys = %i[compiled_iseq_count compiled_iseq_entry compiled_block_count inline_code_size code_region_size]
  puts "yjit stats: #{keys.map { |key| "#{key}=#{stats[key].inspect}" }.join(' ')} total=#{total}"
  puts "sandbox container: #{ENV.fetch('APP_SANDBOX_CONTAINER_ID', 'none')}"
  puts "home: #{Dir.home}"
  real = Etc.getpwuid.dir
  begin
    puts "real home #{real}: listed #{Dir.children(real).size} entries"
  rescue SystemCallError => e
    puts "real home #{real}: #{e.class}"
  end
  stamp = "saved by #{Process.pid}"
  puts "saved: #{Lota::Filesystem.write('check.txt', stamp).first}"
  directory = Lota::Filesystem.save_directory
  puts "save directory: #{directory}"
  puts "read back: #{File.read(File.join(directory, 'check.txt')) == stamp}"
  Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
  puts "#{Lota::System.os}: #{Lota::Audio.active_source_count} source playing"
  Lota::Event.quit(3)
end
