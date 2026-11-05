# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require_relative "cmake_build"
require_relative "engine_sources"
require_relative "linux_build"
require_relative "windows_build"

# The tree that builds LÖVE's engine, Lota::Native, and the test-only
# extension from ext/lota. ext/lota/extconf.rb configures it (rake compile,
# tasks/native.rake), since only Ruby knows which Ruby and which Rice to
# build against, so engine:configure is defined beside rake compile; cpp:tidy
# reads the compile_commands.json it writes.
ENGINE_BUILD = "tmp/engine/build"
ENGINE = CMakeBuild.new(source: "ext/lota", build: ENGINE_BUILD)

# The engine's source list is evaluated for the host platform
# (ext/lota/engine/sources_macos.cmake on macOS, sources_linux.cmake on
# Linux), so each platform's list is checked on that platform, and iOS's
# (sources_ios.cmake) on macOS, beside macOS's.
ENGINE_PLATFORM = EngineSources.platform(RbConfig::CONFIG["host_os"])
ENGINE_LOVE_COMMIT = `git -C vendor/love rev-parse HEAD`.strip
ENGINE_SOURCE_LISTS = EngineSources.generated_on(ENGINE_PLATFORM).to_h do |platform|
  sources = EngineSources.new(
    source: "vendor/love", build: "tmp/engine/sources/#{platform}", cmake_args: EngineSources.cmake_args(platform),
    label: EngineSources.label(ENGINE_LOVE_COMMIT, platform)
  )
  ["ext/lota/engine/sources_#{platform}.cmake", sources]
end.freeze
ENGINE_SOURCES_FILE, ENGINE_SOURCES = ENGINE_SOURCE_LISTS.first

namespace :engine do
  desc "Regenerate the engine's source lists from vendor/love"
  task :sources do
    ENGINE_SOURCE_LISTS.each do |file, sources|
      sources.write(file)
      puts "✅ Wrote #{file}"
    end
  end

  namespace :sources do
    desc "Fail if an engine source list differs from what vendor/love generates"
    task :check do
      ENGINE_SOURCE_LISTS.each do |file, sources|
        problems = sources.problems(file)
        abort <<~ERROR if problems.any?
          ❌ #{file} does not match vendor/love:
          #{problems.map { |line| "  #{line}" }.join("\n")}

          Review the change, then run `bundle exec rake engine:sources` to regenerate it.
        ERROR

        puts "✅ #{file} matches vendor/love"
      end
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

# On Windows, tasks/windows_build.rb builds them from each release's source,
# as rake sources:fetch downloaded it.
WINDOWS_BUILD = WindowsBuild.new(sources: WindowsBuild::SOURCES, root: "tmp/dependencies")

if ENGINE_PLATFORM == "windows"
  file WINDOWS_BUILD.dependencies_stamp => ["tasks/windows_build.rb"] do
    WINDOWS_BUILD.dependencies
  rescue WindowsBuild::Failure => e
    abort "❌ #{e.message}"
  end
end

# What the engine build waits for on each platform: the stamp of LÖVE's
# dependencies where Lota builds them, and nothing on macOS.
DEPENDENCIES_STAMPS = {
  "linux" => [LINUX_BUILD.dependencies_stamp],
  "windows" => [WINDOWS_BUILD.dependencies_stamp],
}.fetch(ENGINE_PLATFORM, []).freeze

desc "Build LÖVE's Linux or Windows dependencies into tmp/dependencies, from what sources:fetch downloaded"
task dependencies: DEPENDENCIES_STAMPS

desc "Build LÖVE's engine as a static library, with the extensions that link it"
task engine: %w[dependencies engine:sources:check bindings:check engine:configure] do
  ENGINE.build
end
