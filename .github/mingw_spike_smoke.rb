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
# Each check prints its result or its error, so one run reports them all.

mode, directory = ARGV
puts "mode: #{mode}, RUBY_PLATFORM #{RUBY_PLATFORM}, #{RUBY_DESCRIPTION}"
RubyInstaller::Runtime.add_dll_directory(directory) if mode == "add-dll-directory"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

def check(name)
  result = yield
  puts "PASS #{name}: #{result.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "FAIL #{name}: #{e.class}: #{e.message.lines.first(3).join}"
  raise if name == "require lota"
end

check("require lota") { require "lota" }
check("Lota::Math.random") { Lota::Math.random }
check("Lota::Math.random(1, 6)") { Lota::Math.random(1, 6) }
check("Lota::System.os") { Lota::System.os }
check("Lota::System.processor_count") { Lota::System.processor_count }
check("Lota::System.memory_size") { Lota::System.memory_size }
check("Lota::System.preferred_locales") { Lota::System.preferred_locales }
check("Lota::Timer.step") { Lota::Timer.step }
check("Lota::Timer.time") { Lota::Timer.time }
check("Lota::Timer.sleep(0.01)") { Lota::Timer.sleep(0.01) }
check("Lota::Filesystem.identity=") { Lota::Filesystem.identity = "lota-mingw-spike" }
check("Lota::Filesystem.save_directory") { Lota::Filesystem.save_directory }
check("Lota::Filesystem.write") { Lota::Filesystem.write("spike.txt", "héllo\nwörld\n") }
check("Lota::Filesystem.read") { Lota::Filesystem.read("spike.txt") }
check("Lota::Filesystem.lines") { Lota::Filesystem.lines("spike.txt").to_a }
check("Lota::Filesystem.info") { Lota::Filesystem.info("spike.txt") }
check("Lota::Filesystem.remove") { Lota::Filesystem.remove("spike.txt") }
check("Lota::Native constants") { Lota::Native.constants.size }
