# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The MinGW spike's headless checks (ADR 002, section 4): load Lota in
# RubyInstaller's Ruby and call what needs no window or GPU. ARGV[0] says
# how the engine's DLLs are found:
#
# [bare] Nothing is done; only the process's default search applies.
# [add-dll-directory] RubyInstaller::Runtime.add_dll_directory(ARGV[1]).
#
# ARGV[2], if given, is the lib directory to load Lota from. SPIKE_GROUPS
# names which modules open, of core, sdl (event, keyboard, mouse), and
# audio; all three by default.
#
# Each check prints its result or its error, so one run reports them all.

require "tmpdir"

mode, directory, lib = ARGV
puts "mode: #{mode}, RUBY_PLATFORM #{RUBY_PLATFORM}, #{RUBY_DESCRIPTION}"
puts "PATH: #{ENV.fetch('PATH', '')}"
RubyInstaller::Runtime.add_dll_directory(directory) if mode == "add-dll-directory"

$LOAD_PATH.unshift(File.expand_path(lib || "../lib", lib ? Dir.pwd : __dir__))

# OpenAL Soft plays into a wave file, as the tests have it (test/alsoft.conf).
home = Dir.mktmpdir("lota-spike-")
ENV["LOTA_TEST_HOME"] = home
ENV["ALSOFT_CONF"] = File.expand_path("../test/alsoft.conf", __dir__)

$failures = 0 # rubocop:disable Style/GlobalVars

def check(name)
  result = yield
  puts "PASS #{name}: #{result.inspect[0, 200]}"
  result
rescue Exception => e # rubocop:disable Lint/RescueException
  $failures += 1 # rubocop:disable Style/GlobalVars
  puts "FAIL #{name}: #{e.class}: #{e.message.lines.first(3).join}"
  raise if name == "require lota"
end

groups = ENV.fetch("SPIKE_GROUPS", "core sdl audio").split
puts "groups: #{groups.join(' ')}"
# Registered first, so it runs last of Ruby's exit procs; a hang after it
# prints is in finalizers or DLL unloading.
at_exit do
  puts "last at_exit proc ran"
  $stdout.flush
end

check("require lota") { require "lota" }
check("loaded from") { $LOADED_FEATURES.grep(/native\.so/) }
opened = %i[Data Timer Sound System Image Font Math Physics]
opened += %i[Event Keyboard Mouse] if groups.include?("sdl")
opened.each do |name|
  check("Native::#{name}.open") { Lota::Native.const_get(name).open }
end
check("Native::Audio.open") { Lota::Native::Audio.open } if groups.include?("audio")
check("Native::Filesystem.open") do
  Lota::Native::Filesystem.open
  Lota::Native::Filesystem.init($PROGRAM_NAME)
end
check("Lota::Math.random") { Lota::Math.random }
check("Lota::Math.random(1, 6)") { Lota::Math.random(1, 6) }
check("Lota::System.os") { Lota::System.os }
check("Lota::System.processor_count") { Lota::System.processor_count }
check("Lota::System.memory_size") { Lota::System.memory_size }
check("Lota::System.preferred_locales") { Lota::System.preferred_locales }
check("Lota::Timer.step") { Lota::Timer.step }
check("Lota::Timer.sleep(0.01)") { Lota::Timer.sleep(0.01) }
check("Lota::Timer.step after sleep") { Lota::Timer.step }
check("Lota::Timer.time") { Lota::Timer.time }
check("Lota::Filesystem.identity=") { Lota::Filesystem.identity = "lota-mingw-spike" }
check("Lota::Filesystem.save_directory") { Lota::Filesystem.save_directory }
check("Lota::Filesystem.write") { Lota::Filesystem.write("spike.txt", "héllo\nwörld\n") }
check("Lota::Filesystem.read") { Lota::Filesystem.read("spike.txt") }
check("Lota::Filesystem.lines") { Lota::Filesystem.lines("spike.txt").to_a }
check("Lota::Filesystem.info") { Lota::Filesystem.info("spike.txt") }
check("Lota::Filesystem.remove") { Lota::Filesystem.remove("spike.txt") }
check("ImageData.new(4, 4)") { Lota::Image::ImageData.new(4, 4).dimensions }
check("SoundData.new(100)") { Lota::Sound::SoundData.new(100).class }
check("Physics world falls") do
  world = Lota::Physics::World.new(0, 9.81 * 64)
  body = Lota::Physics::Body.new(world, 0, 0, :dynamic)
  10.times { world.update(1.0 / 60) }
  [body.get_type, body.position, world.gravity]
end
check("Native constants") { Lota::Native.constants.size }
puts "#{$failures} checks failed" # rubocop:disable Style/GlobalVars
$stdout.flush
