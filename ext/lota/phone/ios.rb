# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Lota's extension for an iOS or iPadOS app, which ext/lota/extconf.rb
# loads when Fledge's `fledge build ios` runs it for one of the app's
# slices: under the phone Ruby's rbconfig.rb, with mkmf's $static set, and
# CMAKE_TOOLCHAIN_FILE in the environment naming the slice's SDK and
# compilers (Fledge's ADRs 022 and 027). An iOS app loads no extension at
# run time, so everything here is a static archive the app links.
#
# CMake builds LÖVE's engine and Lota::Native (CMakeLists.txt beside
# extconf.rb) as on a desktop, but as static archives; mkmf then compiles
# phone/native_ios.c, whose Init_native calls the extension's, and names the
# archives and the system's libraries for Fledge to link (phone_link.txt,
# which engine/dependencies_ios.cmake writes).
#
# Options, which Bundler passes from `bundle config build.lota`:
#
# [--with-lota-source=DIR] A clone of Lota's repository with its
#                          submodules: the gem does not carry LÖVE's
#                          sources (vendor/love) or its iOS libraries
#                          (vendor/love-apple-dependencies).
# [--with-lota-sdl3=DIR] SDL3 built static for each slice, in
#                        DIR/ios-arm64 and DIR/ios-arm64-simulator
#                        (`rake ios:sdl3` in that clone).
# [--with-rice-dir=DIR] The rice gem's directory, since Fledge runs this
#                       with --disable-gems.

require "mkmf"
require "rbconfig"
require "shellwords"

ios_slice = RbConfig::CONFIG.fetch("CC").include?("-simulator") ? "ios-arm64-simulator" : "ios-arm64"
lota_source = with_config("lota-source") or abort "Lota's iOS build needs --with-lota-source=DIR, a clone of " \
  "Lota's repository with its submodules (bundle config build.lota)"
lota_source = File.expand_path(lota_source)
abort "#{lota_source} has no vendor/love; run git submodule update --init there" unless
  File.exist?(File.join(lota_source, "vendor/love/src/common/Object.h"))
sdl3 = with_config("lota-sdl3") or abort "Lota's iOS build needs --with-lota-sdl3=DIR, from rake ios:sdl3"
rice = with_config("rice-dir") or abort "Lota's iOS build needs --with-rice-dir=DIR, the rice gem's directory"
ENV["CMAKE_TOOLCHAIN_FILE"] or abort "Lota's iOS build needs CMAKE_TOOLCHAIN_FILE, which fledge build ios sets"

cmake = find_executable("cmake") or abort "Lota's extension builds with CMake, which is not on PATH."
# A new folder for each slice, which is how CMake reads the toolchain from
# the environment (cmake-env-variables(7), CMAKE_TOOLCHAIN_FILE).
build = File.expand_path("lota-build")
configure = [cmake, "-S", File.expand_path("..", __dir__), "-B", build]
configure += %w[-G Ninja] if find_executable("ninja")
configure += [
  "-DCMAKE_BUILD_TYPE=Release",
  "-DENGINE_SOURCE_DIR:PATH=#{File.join(lota_source, 'vendor/love')}",
  "-DENGINE_DEPS_DIR:PATH=#{File.join(lota_source, 'vendor/love-apple-dependencies')}",
  "-DLOTA_IOS_SDL3_DIR:PATH=#{File.join(File.expand_path(sdl3), ios_slice)}",
  "-DRICE_DIR:PATH=#{File.expand_path(rice)}",
  "-DLOTA_RUBY_INCLUDE_DIRS=#{[RbConfig::CONFIG['rubyhdrdir'], RbConfig::CONFIG['rubyarchhdrdir']].uniq.join(';')}",
  "-DLOTA_NATIVE_TEST=OFF",
  "-DLOTA_SANITIZE=OFF",
]
system(*configure) or abort "CMake could not configure Lota for #{ios_slice} (its output is above)."
system(cmake, "--build", build, "--target", "lota_native") or abort "CMake could not build Lota for #{ios_slice}."

archives = [File.join(build, "lib/lota/liblota_native.a"), File.join(build, "engine/liblota_engine.a")]
libraries, flags = File.readlines(File.join(build, "phone_link.txt"), chomp: true).reject(&:empty?)
  .partition { |line| line.end_with?(".a") }
$LOCAL_LIBS << " #{(archives + libraries).shelljoin}"
$libs << " #{flags.shelljoin}"
# Android's entry point sits beside this one (phone/native_android.c).
$srcs = ["native_ios.c"]
create_makefile("lota/native", __dir__)
