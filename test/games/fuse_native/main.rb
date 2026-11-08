# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fast_blank"

# Says what test/games/fuse's game says, and what fast_blank's C
# extension makes of two strings and where it loaded from, then quits
# with status 3.
def Lota.load(_arguments)
  puts "fused: #{Lota::Filesystem.fused?}"
  puts "yjit: #{defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : 'absent'}"
  puts "identity: #{Lota::Filesystem.identity}"
  puts "saved: #{Lota::Filesystem.write('check.txt', 'saved').first}"
  puts "save directory: #{Lota::Filesystem.save_directory}"
  Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
  puts "#{Lota::System.os}: #{Lota::Audio.active_source_count} source playing"
  puts "fast_blank: #{" \t".blank?} #{'a'.blank?}"
  extension = $LOADED_FEATURES.find { |feature| File.basename(feature).start_with?("fast_blank.") }.to_s
  puts "fast_blank's extension: #{File.basename(extension)}"
  puts "fast_blank from the app: #{extension.downcase.start_with?(Gem.dir.downcase)}"
  Lota::Event.quit(3)
end
