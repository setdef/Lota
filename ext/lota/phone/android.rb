# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Lota's extension for an Android app, which ext/lota/extconf.rb loads
# when Fledge's `fledge build android` runs it for one of the app's ABIs:
# under the phone Ruby's rbconfig.rb, with mkmf's $static set, and
# CMAKE_TOOLCHAIN_FILE in the environment naming the NDK's toolchain for
# the ABI (Fledge's ADRs 022 and 027). Fledge links every extension's
# archive, and the archives and libraries it names, into the app's one
# libfledgeext.so for the ABI (its ADR 022, section 3).
#
# CMake builds LÖVE's engine and Lota::Native (CMakeLists.txt beside
# extconf.rb) as static archives, as phone/ios.rb does; mkmf then
# compiles phone/native_android.c, whose Init_native calls the
# extension's, and names the archives, the shared libraries, and the
# system's libraries for Fledge to link (phone_link.txt, which
# engine/dependencies_android.cmake writes). Fledge copies the shared
# libraries, libSDL3.so and libopenal.so, into the app beside
# libfledgeext.so (its ADR 025, section 2).
#
# Options, which Bundler passes from `bundle config build.lota`:
#
# [--with-lota-source=DIR] A clone of Lota's repository with its
#                          submodules: the gem does not carry LÖVE's
#                          sources (vendor/love).
# [--with-lota-sdl3=DIR] SDL3 built shared for each ABI, in DIR/arm64-v8a
#                        and DIR/x86_64 (Fledge's
#                        examples/sdl_phone/sdl3/build.sh android DIR).
# [--with-lota-android-deps=DIR] LÖVE's other dependencies built for each
#                                ABI, in DIR/arm64-v8a and DIR/x86_64
#                                (`rake android:deps` in that clone).
# [--with-rice-dir=DIR] The rice gem's directory, since Fledge runs this
#                       with --disable-gems.

require "mkmf"
require "rbconfig"
require "shellwords"

abi = RbConfig::CONFIG.fetch("CC").include?("aarch64-linux-android") ? "arm64-v8a" : "x86_64"
lota_source = with_config("lota-source") or abort "Lota's Android build needs --with-lota-source=DIR, a clone " \
  "of Lota's repository with its submodules (bundle config build.lota)"
lota_source = File.expand_path(lota_source)
abort "#{lota_source} has no vendor/love; run git submodule update --init there" unless
  File.exist?(File.join(lota_source, "vendor/love/src/common/Object.h"))
sdl3 = with_config("lota-sdl3") or abort "Lota's Android build needs --with-lota-sdl3=DIR, from Fledge's " \
  "examples/sdl_phone/sdl3/build.sh android DIR"
deps = with_config("lota-android-deps") or abort "Lota's Android build needs --with-lota-android-deps=DIR, " \
  "from rake android:deps"
rice = with_config("rice-dir") or abort "Lota's Android build needs --with-rice-dir=DIR, the rice gem's directory"
ENV["CMAKE_TOOLCHAIN_FILE"] or abort "Lota's Android build needs CMAKE_TOOLCHAIN_FILE, which fledge build android sets"

cmake = find_executable("cmake") or abort "Lota's extension builds with CMake, which is not on PATH."
# A new folder for each ABI, which is how CMake reads the toolchain from
# the environment (cmake-env-variables(7), CMAKE_TOOLCHAIN_FILE).
build = File.expand_path("lota-build")
configure = [cmake, "-S", File.expand_path("..", __dir__), "-B", build]
configure += %w[-G Ninja] if find_executable("ninja")
configure += [
  "-DCMAKE_BUILD_TYPE=Release",
  "-DENGINE_SOURCE_DIR:PATH=#{File.join(lota_source, 'vendor/love')}",
  "-DLOTA_ANDROID_SDL3_DIR:PATH=#{File.join(File.expand_path(sdl3), abi)}",
  "-DLOTA_ANDROID_DEPS_DIR:PATH=#{File.join(File.expand_path(deps), abi)}",
  "-DRICE_DIR:PATH=#{File.expand_path(rice)}",
  "-DLOTA_RUBY_INCLUDE_DIRS=#{[RbConfig::CONFIG['rubyhdrdir'], RbConfig::CONFIG['rubyarchhdrdir']].uniq.join(';')}",
  "-DLOTA_NATIVE_TEST=OFF",
  "-DLOTA_SANITIZE=OFF",
]
system(*configure) or abort "CMake could not configure Lota for #{abi} (its output is above)."
system(cmake, "--build", build, "--target", "lota_native") or abort "CMake could not build Lota for #{abi}."

archives = [File.join(build, "lib/lota/liblota_native.a"), File.join(build, "engine/liblota_engine.a")]
libraries, flags = File.readlines(File.join(build, "phone_link.txt"), chomp: true).reject(&:empty?)
  .partition { |line| line.end_with?(".a") }
$LOCAL_LIBS << " #{(archives + libraries).shelljoin}"
$libs << " #{flags.shelljoin}"
# iOS's entry point sits beside this one (phone/native_ios.c).
$srcs = ["native_android.c"]
create_makefile("lota/native", __dir__)
