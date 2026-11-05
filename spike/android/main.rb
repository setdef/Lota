# frozen_string_literal: true

# The app's program: boots the game in game/ as a fused game, as lota fuse's
# entry script would (ADR 002, section 5), and reports how it ended.
$stdout.sync = true
puts "LotaSpike starts Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}, YJIT #{defined?(RubyVM::YJIT) ? 'present' : 'absent'}"
require "lota"
puts "LotaSpike loaded Lota #{Lota::VERSION}"
status = Lota::Boot.new(File.join(__dir__, "game"), [], fused: true).call
puts "LotaSpike exits with status #{status}"
exit status
