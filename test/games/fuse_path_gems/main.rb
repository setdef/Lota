# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "sample_helper"

# Says what test/games/fuse's game says, and where it loaded sample_helper
# from and what that gem made of a word, then quits with status 3.
def Lota.load(_arguments)
  puts "fused: #{Lota::Filesystem.fused?}"
  puts "yjit: #{defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : 'absent'}"
  puts "identity: #{Lota::Filesystem.identity}"
  puts "saved: #{Lota::Filesystem.write('check.txt', 'saved').first}"
  puts "save directory: #{Lota::Filesystem.save_directory}"
  Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
  puts "#{Lota::System.os}: #{Lota::Audio.active_source_count} source playing"
  spec = Gem.loaded_specs.fetch("sample_helper")
  puts "sample_helper: #{spec.version}"
  puts "sample_helper from the app: #{spec.full_gem_path.tr('\\', '/').downcase.include?('/game/') && spec.full_gem_path.end_with?('gems/sample_helper')}"
  puts "sample_helper says: #{SampleHelper.shout('ok').inspect}"
  Lota::Event.quit(3)
end
