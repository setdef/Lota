# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "ios_build"

# SDL3 for an iOS or iPadOS app's slices (tasks/ios_build.rb), which a
# Fledge project points Lota's extension at with
# bundle config build.lota --with-lota-sdl3=tmp/ios/sdl3.
IOS_BUILD = IosBuild.new(root: "tmp/ios/sdl3")

namespace :ios do
  desc "Build SDL3 static for the iOS device and Simulator into tmp/ios/sdl3, on macOS with Xcode"
  task :sdl3 do
    IOS_BUILD.fetch
    IOS_BUILD.build
  rescue IosBuild::Failure, SourceArchive::Failure => e
    abort "❌ #{e.message}"
  end
end
