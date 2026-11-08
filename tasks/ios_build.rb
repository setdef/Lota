# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require_relative "source_archive"

# Builds SDL3 for iOS and iPadOS, which Lota's iOS extension links
# (ext/lota/engine/dependencies_ios.cmake), from LÖVE's version of SDL,
# 3.4.10, the one love-apple-dependencies' SDL3.xcframework holds and
# WindowsBuild builds.
#
# love-apple-dependencies has every other library LÖVE's iOS build links,
# as static archives (iOS/libraries), but its SDL3 is a dynamic framework,
# which an app embeds. Fledge links a gem's extension and the archives it
# names into the app's executable (its ADR 022, section 3), and embeds no
# framework of a gem's, so SDL is built static here, once for each of the
# app's slices, with SDL's own CMake build for iOS (SDL's
# docs/README-cmake.md, "iOS/tvOS/visionOS") and the deployment target
# of Fledge's iOS runtime, iOS 15. `bundle config build.lota
# --with-lota-sdl3=DIR` points the extension at #root.
#
# As WindowsBuild does, it keeps downloading apart from building: #fetch
# downloads the release into +sources+ (vendor/sources/ios, which git
# ignores), and #build builds from it without the network.
class IosBuild
  # Raised when a step fails; its output is in the log.
  class Failure < StandardError; end

  # SDL's release archive, as WindowsBuild::Archive records one.
  class Archive < Data.define(:name, :directory, :url, :sha256, :checked)
    # Where #fetch keeps it, relative to the repository.
    def path
      File.join(IosBuild::SOURCES, File.basename(url))
    end
  end

  # Where #fetch keeps the archive, relative to the repository.
  SOURCES = "vendor/sources/ios"

  # LÖVE's SDL, as WindowsBuild::ARCHIVES pins it.
  SDL = Archive.new(
    name: "SDL", directory: "SDL3-3.4.10",
    url: "https://github.com/libsdl-org/SDL/releases/download/release-3.4.10/SDL3-3.4.10.tar.gz",
    sha256: "12b34280415ec8418c864408b93d008a20a6530687ee613d60bfbd20411f2785",
    checked: "github.com/libsdl-org/SDL/releases/tag/release-3.4.10"
  )

  # Each slice of an iOS app, as Fledge names them (its ADR 022, section
  # 1), and the SDK CMake builds it against.
  SLICES = { "ios-arm64" => "iphoneos", "ios-arm64-simulator" => "iphonesimulator" }.freeze

  # The oldest iOS Fledge's iOS runtime runs on (its ADR 011).
  DEPLOYMENT_TARGET = "15.0"

  # [root] Where SDL is built and installed, one folder for each slice.
  # [repository] The repository, which SOURCES is relative to.
  # [out] Where progress goes; +nil+ means wherever $stdout points.
  def initialize(root:, repository: Dir.pwd, out: nil)
    @root = File.expand_path(root, repository)
    @repository = File.expand_path(repository)
    @out = out
  end

  # The build's log.
  def log
    File.join(@root, "build.log")
  end

  # Where SDL for +slice+ is installed: include/ and lib/libSDL3.a.
  def prefix(slice)
    File.join(@root, slice)
  end

  # Downloads SDL's release into SOURCES, unless it is there with the
  # recorded SHA-256, retrying a failed connection as SourceArchive#fetch
  # does.
  def fetch
    SourceArchive.new(SDL, root: @repository, out: @out || $stdout).fetch
    say "✅ #{SDL.path} is #{SDL.url}, SHA-256 #{SDL.sha256}"
  rescue SourceArchive::Failure => e
    raise Failure, e.message
  end

  # Builds SDL for every slice, from what #fetch downloaded, and returns
  # #root. Raises Failure if a step fails, or if #fetch has not run.
  def build
    SourceArchive.new(SDL, root: @repository).verify!
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    run(@root, "cmake", "-E", "tar", "xf", File.join(@repository, SDL.path))
    SLICES.each_key do |slice|
      work = File.join(@root, "build-#{slice}")
      run(@root, "cmake", "-S", File.join(@root, SDL.directory), "-B", work, *options(slice))
      run(@root, "cmake", "--build", work)
      run(@root, "cmake", "--install", work)
    end
    say "✅ Built SDL #{SDL.directory} for #{SLICES.keys.join(' and ')}: #{@root}"
    @root
  rescue SourceArchive::Failure => e
    raise Failure, e.message
  end

  # The CMake options SDL for +slice+ is configured with: CMake's own
  # cross-compiling for iOS (cmake-toolchains(7), "Cross Compiling for
  # iOS"), for arm64 alone, as an app's slice is, and SDL static, without
  # its tests and examples.
  def options(slice)
    sdk = SLICES.fetch(slice)
    %W[
      -G
      Ninja
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_OSX_SYSROOT=#{sdk}
      -DCMAKE_OSX_ARCHITECTURES=arm64
      -DCMAKE_OSX_DEPLOYMENT_TARGET=#{DEPLOYMENT_TARGET}
      -DCMAKE_INSTALL_PREFIX=#{prefix(slice)}
      -DCMAKE_INSTALL_LIBDIR=lib
      -DSDL_SHARED=OFF
      -DSDL_STATIC=ON
      -DSDL_TEST_LIBRARY=OFF
      -DSDL_TESTS=OFF
      -DSDL_EXAMPLES=OFF
    ]
  end

  private def run(dir, *command)
    FileUtils.mkdir_p(File.dirname(log))
    output, status = Open3.capture2e(*command, chdir: dir)
    File.open(log, "a") { |file| file.write("$ #{command.join(' ')}\n#{output}") }
    raise Failure, "#{command.join(' ')} failed in #{dir}; see #{log}" unless status.success?
  end

  private def say(message)
    (@out || $stdout).puts(message)
  end
end
