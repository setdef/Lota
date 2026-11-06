# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "android_build"
require_relative "engine_sources"

# LÖVE's dependencies for an Android app's ABIs (tasks/android_build.rb),
# which a Fledge project points Lota's extension at with
# bundle config build.lota --with-lota-android-deps=tmp/android/deps, and
# the engine's Android source list, which only a computer with the NDK
# can evaluate, so neither is part of the gate.
ANDROID_BUILD = AndroidBuild.new(root: "tmp/android/deps")

namespace :android do
  desc "Build LÖVE's dependencies for Android's arm64-v8a and x86_64 into tmp/android/deps, with ANDROID_NDK_ROOT"
  task :deps do
    ANDROID_BUILD.fetch
    ANDROID_BUILD.build
  rescue AndroidBuild::Failure, SourceArchive::Failure => e
    abort "❌ #{e.message}"
  end

  # The engine's Android source list, evaluated with the NDK's toolchain.
  android_sources = lambda do
    ndk = ENV["ANDROID_NDK_ROOT"] || ENV["ANDROID_NDK_HOME"] or abort "❌ Set ANDROID_NDK_ROOT to the NDK"
    EngineSources.new(
      source: "vendor/love", build: "tmp/engine/sources/android",
      cmake_args: EngineSources.cmake_args("android", ndk:),
      label: EngineSources.label(`git -C vendor/love rev-parse HEAD`.strip, "android")
    )
  end

  desc "Regenerate ext/lota/engine/sources_android.cmake from vendor/love, with ANDROID_NDK_ROOT"
  task :sources do
    android_sources.call.write("ext/lota/engine/sources_android.cmake")
    puts "✅ Wrote ext/lota/engine/sources_android.cmake"
  end

  namespace :sources do
    desc "Fail if ext/lota/engine/sources_android.cmake differs from what vendor/love generates"
    task :check do
      problems = android_sources.call.problems("ext/lota/engine/sources_android.cmake")
      abort <<~ERROR if problems.any?
        ❌ ext/lota/engine/sources_android.cmake does not match vendor/love:
        #{problems.map { |line| "  #{line}" }.join("\n")}

        Review the change, then run `bundle exec rake android:sources` to regenerate it.
      ERROR

      puts "✅ ext/lota/engine/sources_android.cmake matches vendor/love"
    end
  end
end
