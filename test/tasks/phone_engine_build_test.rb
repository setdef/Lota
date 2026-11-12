# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/phone_engine"
require "stringio"
require "zlib"

# PhoneEngineBuild builds a phone's engine as `fledge build` would and
# packs it. What it configures and packs is checked here; the build itself
# runs where the SDKs are, in CI's phone engine jobs.
class PhoneEngineBuildTest < Minitest::Test
  include TreeHelper

  def build(target, **) = PhoneEngineBuild.new(target, repository: "/repo", ndk: "/ndk", out: StringIO.new, **)

  # Fledge aims each target at its runtime's triple (its
  # lib/fledge/mobile_extensions.rb): iOS 15 for a slice, API 26 for an ABI.
  def test_each_target_is_the_triple_fledge_builds_its_runtime_for
    assert_equal "arm64-apple-ios15.0", build("ios-arm64").triple
    assert_equal "arm64-apple-ios15.0-simulator", build("ios-arm64-simulator").triple
    assert_equal "aarch64-linux-android26", build("android-arm64-v8a").triple
    assert_equal "x86_64-linux-android26", build("android-x86_64").triple
  end

  # The text of Fledge's toolchain files (its
  # lib/fledge/mobile_extensions/cmake.rb), past its header comment.
  def test_the_toolchain_file_sets_what_fledges_does
    ios = build("ios-arm64-simulator").toolchain(sysroot: "/sdk/iPhoneSimulator.sdk", cc: "/x/clang", cxx: "/x/clang++")

    assert_includes ios, <<~CMAKE
      set(CMAKE_SYSTEM_NAME iOS)
      set(CMAKE_OSX_SYSROOT "/sdk/iPhoneSimulator.sdk")
      set(CMAKE_OSX_ARCHITECTURES arm64)
      set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
      set(CMAKE_C_COMPILER "/x/clang")
      set(CMAKE_CXX_COMPILER "/x/clang++")
      set(CMAKE_OBJC_COMPILER "/x/clang")
      set(CMAKE_OBJCXX_COMPILER "/x/clang++")
    CMAKE
    assert_includes build("android-arm64-v8a").toolchain, <<~CMAKE
      set(ANDROID_ABI arm64-v8a)
      set(ANDROID_PLATFORM android-26)
      include("/ndk/build/cmake/android.toolchain.cmake")
    CMAKE
  end

  # What phone/ios.rb and phone/android.rb pass CMake, with the extension
  # left out.
  def test_it_configures_the_engine_as_the_phone_extconf_does_without_the_extension
    ios = build("ios-arm64", ios_sdl3: "/sdl").options
    android = build("android-x86_64", android_deps: "/deps").options

    [ios, android].each do |options|
      assert_includes options, "-DCMAKE_BUILD_TYPE=Release"
      assert_includes options, "-DENGINE_SOURCE_DIR:PATH=/repo/vendor/love"
      assert_includes options, "-DLOTA_EXTENSION=OFF"
      assert_includes options, "-DLOTA_SANITIZE=OFF"
    end
    assert_includes ios, "-DENGINE_DEPS_DIR:PATH=/repo/vendor/love-apple-dependencies"
    assert_includes ios, "-DLOTA_IOS_SDL3_DIR:PATH=/sdl/ios-arm64"
    assert_includes android, "-DLOTA_ANDROID_DEPS_DIR:PATH=/deps/x86_64"
    assert_includes android, "-DLOTA_ANDROID_SDL3_DIR:PATH=/deps/x86_64"
    refute(ios.any? { |option| option.include?("RICE") })
  end

  def test_the_extconfs_pass_the_same_engine_options
    %w[ios android].each do |phone|
      extconf = File.read(File.join(ROOT, "ext/lota/phone/#{phone}.rb"))

      %w[-DCMAKE_BUILD_TYPE=Release -DENGINE_SOURCE_DIR:PATH -DLOTA_NATIVE_TEST=OFF -DLOTA_SANITIZE=OFF].each do |option|
        assert_includes extconf, option, "phone/#{phone}.rb"
      end
    end
  end

  def test_sections_reads_engine_interface_txt
    text = "[includes]\n/a\n/a/b\n[definitions]\nHAS_SOCKLEN_T\n[options]\n\n"

    assert_equal({ "includes" => ["/a", "/a/b"], "definitions" => ["HAS_SOCKLEN_T"], "options" => [] },
      PhoneEngineBuild.sections(text))
  end

  def test_a_folder_inside_an_earlier_one_shares_its_copy
    layout = PhoneEngineBuild.include_layout(%w[/b/patched /love/src /love/src/libraries /love/src/modules /deps /deps])

    assert_equal({
"/b/patched" => "0",
"/love/src" => "1",
"/love/src/libraries" => "1/libraries",
"/love/src/modules" => "1/modules",
"/deps" => "2",
}, layout)
  end

  def test_relink_carries_each_archive_and_each_shared_library_a_flag_finds
    in_tree do |root|
      write(root, "deps/lib/libopenal.so", "elf")
      write(root, "sdl/lib/libSDL3.so", "elf")
      link = "#{root}/deps/lib/libz.a\n-L#{root}/deps/lib\n-lopenal\n-L#{root}/sdl/lib\n-lSDL3\n-landroid\n-lstdc++\n"

      libraries, flags = PhoneEngineBuild.relink(link)

      assert_equal ["#{root}/deps/lib/libz.a", "#{root}/deps/lib/libopenal.so", "#{root}/sdl/lib/libSDL3.so"], libraries
      assert_equal %w[-L${LOTA_ENGINE_LIB} -lopenal -lSDL3 -landroid -lstdc++], flags
    end
  end

  def test_engine_cmake_names_only_the_bundles_own_paths
    text = PhoneEngineBuild.engine_cmake(includes: %w[include/0 include/1/libraries], definitions: %w[HAS_SOCKLEN_T],
      options: [], archives: %w[lib/libz.a], flags: %w[-L${LOTA_ENGINE_LIB} -lopenal -Wl,-framework,UIKit])

    assert_includes text, 'IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/lib/liblota_engine.a"'
    assert_includes text,
      'INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_LIST_DIR}/include/0;${CMAKE_CURRENT_LIST_DIR}/include/1/libraries"'
    assert_includes text, 'INTERFACE_COMPILE_DEFINITIONS "HAS_SOCKLEN_T"'
    assert_includes text, "${CMAKE_CURRENT_LIST_DIR}/lib/libz.a;-L${CMAKE_CURRENT_LIST_DIR}/lib;-lopenal;" \
      "-Wl,-framework,UIKit"
  end

  def test_files_carries_the_engine_its_headers_its_libraries_and_a_manifest
    in_tree do |root|
      write(root, "build/engine/liblota_engine.a", "engine")
      write(root, "love/src/common/Object.h", "h")
      write(root, "love/src/common/Object.cpp", "cpp")
      write(root, "love/src/libraries/glm/glm.inl", "inl")
      write(root, "deps/lib/libz.a", "z")
      write(root, "deps/lib/libopenal.so", "so")
      interface = "[includes]\n#{root}/love/src\n#{root}/love/src/libraries\n[definitions]\nHAS_SOCKLEN_T\n[options]\n"
      link = "#{root}/deps/lib/libz.a\n-L#{root}/deps/lib\n-lopenal\n-llog\n"

      files = build("android-x86_64").files(build: "#{root}/build", interface:, link:, digest: "d" * 64,
        love: "c" * 40, toolchain_version: "NDK 30.0.16248370")

      assert_equal %w[
        engine.cmake
        include/0/common/Object.h
        include/0/libraries/glm/glm.inl
        lib/liblota_engine.a
        lib/libopenal.so
        lib/libz.a
        manifest.json
], files.keys.sort
      manifest = JSON.parse(files.fetch("manifest.json").text)

      assert_equal ["android-x86_64", Lota::VERSION, "d" * 64, "c" * 40],
        manifest.values_at("target", "lota", "engine_digest", "love")
      assert_includes files.fetch("engine.cmake").text, "${CMAKE_CURRENT_LIST_DIR}/include/0/libraries"
    end
  end

  def test_a_bundle_is_the_same_bytes_each_time_and_fetch_unpacks_it
    in_tree do |root|
      write(root, "engine.a", "engine")
      files = {
"lib/liblota_engine.a" => File.join(root, "engine.a"),
"manifest.json" => PhoneEngineBuild::Contents.new(text: "{}\n"),
}

      first = PhoneEngineBuild.write(File.join(root, "one/bundle.tar.gz"), files)
      second = PhoneEngineBuild.write(File.join(root, "two/bundle.tar.gz"), files)

      assert_equal first, second
      # gzip's MTIME, bytes 4 to 7 (RFC 1952, 2.3), fixed rather than now.
      assert_equal 1, File.binread(File.join(root, "one/bundle.tar.gz"))[4, 4].unpack1("V")
      Zlib::GzipReader.open(File.join(root, "one/bundle.tar.gz")) do |gzip|
        Lota::PhoneEngine::Tar.extract(gzip, File.join(root, "out"))
      end
      assert_equal "engine", File.read(File.join(root, "out/lib/liblota_engine.a"))
    end
  end
end
