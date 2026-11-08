# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/ios_build"
require_relative "../../tasks/windows_build"
require "stringio"

# IosBuild builds SDL3 static for each slice of an iOS app. Its options
# are checked here; the build itself runs where Xcode's iOS SDKs are, in
# the iOS jobs that build an app.
class IosBuildTest < Minitest::Test
  include TreeHelper

  def ios_build(root = "/r") = IosBuild.new(root:, repository: "/repo", out: StringIO.new)

  # One SDL for every platform Lota builds from source: LÖVE's.
  def test_sdl_is_the_release_windows_builds
    windows = WindowsBuild::ARCHIVES.find { |archive| archive.name == "SDL" }

    assert_equal [windows.directory, windows.url, windows.sha256],
      [IosBuild::SDL.directory, IosBuild::SDL.url, IosBuild::SDL.sha256]
    assert_equal "vendor/sources/ios/SDL3-3.4.10.tar.gz", IosBuild::SDL.path
  end

  def test_each_slice_is_arm64_on_its_sdk_for_ios_15_static
    {
      "ios-arm64" => "iphoneos", "ios-arm64-simulator" => "iphonesimulator"
    }.each do |slice, sdk|
      options = ios_build.options(slice)

      assert_includes options, "-DCMAKE_SYSTEM_NAME=iOS"
      assert_includes options, "-DCMAKE_OSX_SYSROOT=#{sdk}"
      assert_includes options, "-DCMAKE_OSX_ARCHITECTURES=arm64"
      assert_includes options, "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0"
      assert_includes options, "-DCMAKE_INSTALL_PREFIX=/r/#{slice}"
      assert_includes options, "-DSDL_STATIC=ON"
      assert_includes options, "-DSDL_SHARED=OFF"
    end
  end

  def test_an_unknown_slice_is_refused
    assert_raises(KeyError) { ios_build.options("ios-x86_64-simulator") }
  end

  def test_build_refuses_before_fetch
    in_tree do |root|
      error = assert_raises(IosBuild::Failure) { IosBuild.new(root: "tmp/ios", repository: root).build }

      assert_includes error.message, "vendor/sources/ios/SDL3-3.4.10.tar.gz is missing"
    end
  end
end
