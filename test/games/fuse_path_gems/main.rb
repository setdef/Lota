# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "sample_helper"

# Whether sample_tool, of the Gemfile's development group, loads.
def sample_tool?
  require "sample_tool"
  true
rescue LoadError
  false
end

# Says what test/games/fuse's game says, where it loaded sample_helper from
# and what that gem made of a word, and whether the development group's
# sample_tool reached the app, then quits with status 3.
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
  puts "sample_tool in the app: #{sample_tool?}"
  Lota::Event.quit(3)
end
