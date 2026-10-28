# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require_relative "cmake_build"
require_relative "engine_sources"
require_relative "linux_build"

# The tree that builds LÖVE's engine, Lota::Native, and the test-only
# extension from ext/lota. ext/lota/extconf.rb configures it (rake compile,
# tasks/native.rake), since only Ruby knows which Ruby and which Rice to
# build against, so engine:configure is defined beside rake compile; cpp:tidy
# reads the compile_commands.json it writes.
ENGINE_BUILD = "tmp/engine/build"
ENGINE = CMakeBuild.new(source: "ext/lota", build: ENGINE_BUILD)

# The engine's source list is evaluated for the host platform
# (ext/lota/engine/sources_macos.cmake on macOS, sources_linux.cmake on
# Linux), so each platform's list is checked on that platform.
ENGINE_PLATFORM = EngineSources.platform(RbConfig::CONFIG["host_os"])
ENGINE_SOURCES_FILE = "ext/lota/engine/sources_#{ENGINE_PLATFORM}.cmake"
ENGINE_SOURCES_ARGS = EngineSources.cmake_args(ENGINE_PLATFORM)
ENGINE_SOURCES = EngineSources.new(
  source: "vendor/love", build: "tmp/engine/sources/#{ENGINE_PLATFORM}", cmake_args: ENGINE_SOURCES_ARGS,
  label: "vendor/love #{`git -C vendor/love rev-parse HEAD`.strip} on #{ENGINE_PLATFORM} with " \
    "#{ENGINE_SOURCES_ARGS.grep(/\A-D/).join(' ')}"
)

namespace :engine do
  desc "Regenerate the engine's source list from vendor/love"
  task :sources do
    ENGINE_SOURCES.write(ENGINE_SOURCES_FILE)
    puts "✅ Wrote #{ENGINE_SOURCES_FILE}"
  end

  namespace :sources do
    desc "Fail if the engine's source list differs from what vendor/love generates"
    task :check do
      problems = ENGINE_SOURCES.problems(ENGINE_SOURCES_FILE)
      abort <<~ERROR if problems.any?
        ❌ #{ENGINE_SOURCES_FILE} does not match vendor/love:
        #{problems.map { |line| "  #{line}" }.join("\n")}

        Review the change, then run `bundle exec rake engine:sources` to regenerate it.
      ERROR

      puts "✅ #{ENGINE_SOURCES_FILE} matches vendor/love"
    end
  end
end

# LÖVE's dependencies on Linux, which love-appimage-source's Makefile
# builds from source, as LÖVE's own Linux CI builds them
# (tasks/linux_build.rb): rake sources:fetch downloads them, and the engine
# build builds them into tmp/dependencies first, without the network. On
# macOS they come built, from vendor/love-apple-dependencies.
LINUX_BUILD = LinuxBuild.new(makefile: "vendor/love-appimage-source/Makefile", sources: "vendor/sources/linux",
  root: "tmp/dependencies")

if ENGINE_PLATFORM == "linux"
  # Built again when the Makefile or the recipe changes, or when the stamp
  # is gone, as after rm -rf tmp.
  file LINUX_BUILD.dependencies_stamp => [LINUX_BUILD.makefile, "tasks/linux_build.rb"] do
    LINUX_BUILD.dependencies
  rescue LinuxBuild::Failure => e
    abort "❌ #{e.message}"
  end
end

desc "Build LÖVE's Linux dependencies into tmp/dependencies, from what sources:fetch downloaded (Linux only)"
task dependencies: ((ENGINE_PLATFORM == "linux") ? [LINUX_BUILD.dependencies_stamp] : [])

desc "Build LÖVE's engine as a static library, with the extensions that link it"
task engine: %w[dependencies engine:sources:check bindings:check engine:configure] do
  ENGINE.build
end
