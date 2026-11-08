# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/android_build"
require_relative "../../tasks/windows_build"
require "stringio"

# AndroidBuild builds LÖVE's dependencies for each Android ABI with the
# NDK, from the release archives WindowsBuild builds. Its archives and
# options are checked here; the build itself runs where an NDK is, in the
# Android jobs that build an app.
class AndroidBuildTest < Minitest::Test
  include TreeHelper

  def android_build(ndk: "/ndk") = AndroidBuild.new(root: "/r", ndk:, repository: "/repo", out: StringIO.new)

  # One release of each library for every platform Lota builds from
  # source, SDL among them, LÖVE's version, which Lota builds for Android
  # itself rather than taking an SDL of Fledge's.
  def test_the_archives_are_the_windows_builds_releases
    windows = WindowsBuild::ARCHIVES

    assert_includes AndroidBuild::ARCHIVES.map(&:name), "SDL"
    assert_equal windows.map { |archive| [archive.name, archive.directory, archive.url, archive.sha256] },
      AndroidBuild::ARCHIVES.map { |archive| [archive.name, archive.directory, archive.url, archive.sha256] }
    AndroidBuild::ARCHIVES.each do |archive|
      assert archive.path.start_with?("#{AndroidBuild::SOURCES}/#{archive.directory}.tar."), archive.path
    end
  end

  # Fledge's two ABIs, which its NDK toolchain files aim CMake at (its
  # ADR 027), at Fledge's minimum API level, 26.
  def test_each_abi_is_built_with_the_ndks_toolchain_at_api_26
    AndroidBuild::ABIS.each do |abi|
      options = android_build.cmake_options(abi)

      assert_includes options, "-DCMAKE_TOOLCHAIN_FILE=/ndk/build/cmake/android.toolchain.cmake"
      assert_includes options, "-DANDROID_ABI=#{abi}"
      assert_includes options, "-DANDROID_PLATFORM=android-26"
      assert_includes options, "-DANDROID_STL=c++_static"
      assert_includes options, "-DCMAKE_INSTALL_PREFIX=/r/#{abi}"
    end
    assert_equal %w[arm64-v8a x86_64], AndroidBuild::ABIS
  end

  # Autotools' --host for each ABI, the triple the NDK's compilers are
  # named for.
  def test_autotools_aims_at_the_abis_triple
    assert_equal "aarch64-linux-android", AndroidBuild.triple("arm64-v8a")
    assert_equal "x86_64-linux-android", AndroidBuild.triple("x86_64")
    assert_raises(KeyError) { AndroidBuild.triple("armeabi-v7a") }
  end

  # OpenAL Soft is a shared library apart, as LÖVE's Android build ships
  # libopenal.so, with the OpenSL ES backend Android has, and without Oboe,
  # which LÖVE's build takes from Gradle's prefab and Lota has no Gradle
  # step to take it from. Every other library is static.
  def test_openal_soft_is_shared_with_opensl_and_the_rest_static
    openal = android_build.options("OpenAL Soft")

    assert_includes openal, "-DLIBTYPE=SHARED"
    assert_includes openal, "-DALSOFT_REQUIRE_OPENSL=ON"
    assert_includes openal, "-DALSOFT_BACKEND_OBOE=OFF"
    %w[libogg libvorbis FreeType HarfBuzz].each do |name|
      assert_includes android_build.options(name), "-DBUILD_SHARED_LIBS=OFF", name
    end
  end

  # SDL's Java finds libSDL3.so by name and registers its methods from that
  # library's JNI_OnLoad, so SDL is shared, and its Java, which the Gradle
  # project compiles, is no part of this build.
  def test_sdl_is_shared_without_its_java_archive
    sdl = android_build.options("SDL")

    assert_includes sdl, "-DSDL_SHARED=ON"
    assert_includes sdl, "-DSDL_STATIC=OFF"
    assert_includes sdl, "-DSDL_ANDROID_JAR=OFF"
  end

  # SDLActivity checks that libSDL3.so is its own release
  # (SDLActivity.java, nativeGetVersion), so the host's Java classes are
  # the release this build compiles.
  def test_the_android_hosts_sdl_java_is_the_release_built_here
    activity = File.read(File.join(ROOT, "ext/lota/phone/host/android/src/main/java/org/libsdl/app/SDLActivity.java"))
    version = %w[MAJOR MINOR MICRO].map { |part| activity[/SDL_#{part}_VERSION = (\d+);/, 1] }.join(".")
    sdl = AndroidBuild::ARCHIVES.find { |archive| archive.name == "SDL" }

    assert_equal "SDL3-#{version}", sdl.directory
  end

  def test_freetype_links_the_static_zlib_built_before_it
    freetype = android_build.options("FreeType", "/r/arm64-v8a")

    assert_includes freetype, "-DZLIB_LIBRARY=/r/arm64-v8a/lib/libz.a"
    assert_includes freetype, "-DFT_DISABLE_BZIP2=ON"
  end

  def test_build_refuses_without_an_ndk
    error = assert_raises(AndroidBuild::Failure) { AndroidBuild.new(root: "/r", ndk: nil).build }

    assert_includes error.message, "ANDROID_NDK_ROOT"
  end

  def test_build_refuses_before_fetch
    in_tree do |root|
      ndk = File.join(root, "ndk")
      FileUtils.mkdir_p(File.join(ndk, "build/cmake"))
      File.write(File.join(ndk, "build/cmake/android.toolchain.cmake"), "")
      error = assert_raises(AndroidBuild::Failure) do
        AndroidBuild.new(root: "tmp/android/deps", ndk:, repository: root, out: StringIO.new).build
      end

      assert_includes error.message, "vendor/sources/android/zlib-1.3.tar.gz is missing"
    end
  end
end
