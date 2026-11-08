# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "ios_build"
require_relative "phone_notices"

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

  desc "Write the NOTICES.txt of a Fledge project's iOS app into PROJECT"
  task :notices, [:project] do |_, args|
    project = args[:project] or abort "❌ Name the phone project: rake ios:notices[PROJECT]"
    abort "❌ #{project} is not a folder" unless File.directory?(project)

    notices = PhoneNotices.new(licensing: Licensing.load("ext/lota/licenses.rb"), phone: "iOS", root: ".")
    notices.fetch
    notices.write(project)
    puts "✅ Wrote #{File.join(project, Lota::Notices::FILE)}"
  rescue Licensing::Invalid, Licensing::Unrecorded, SourceArchive::Failure => e
    abort "❌ #{e.message}"
  end
end
