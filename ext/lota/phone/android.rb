# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
# LÖVE's engine, with the libraries it links, comes prebuilt for the ABI
# from Lota's release (phone/engine.rb), checked against the SHA-256 this
# gem pins; or, given a clone of Lota, CMake builds it from LÖVE's sources
# as a static archive, as phone/ios.rb does. CMake then builds
# Lota::Native (CMakeLists.txt beside extconf.rb) over it; mkmf compiles
# phone/native_android.c, whose Init_native calls the extension's, and
# names the archives, the shared libraries, and the system's libraries for
# Fledge to link (phone_link.txt, which engine/dependencies_android.cmake
# or the prebuilt engine's engine.cmake writes). Fledge copies the shared
# libraries, libSDL3.so and libopenal.so, into the app beside
# libfledgeext.so (its ADR 025, section 2).
#
# Options, which Bundler passes from `bundle config build.lota`:
#
# [--with-lota-source=DIR] Build the engine from source, from a clone of
#                          Lota's repository with its submodules: the gem
#                          does not carry LÖVE's sources (vendor/love).
# [--with-lota-android-deps=DIR] With --with-lota-source, LÖVE's
#                                dependencies, SDL3 among them, built for
#                                each ABI, in DIR/arm64-v8a and
#                                DIR/x86_64 (`rake android:deps` in that
#                                clone).
# [--with-lota-sdl3=DIR] With --with-lota-source, another SDL3 built
#                        shared for each ABI, in the same layout; by
#                        default the one in --with-lota-android-deps.
# [--with-lota-engine-url=URL] Where to fetch the prebuilt engine from, a
#                              mirror of the release's assets; by default
#                              the release of this version of Lota.
# [--with-lota-engine-cache=DIR] Where fetched engines are kept; by
#                                default lota/phone-engine in
#                                XDG_CACHE_HOME or ~/.cache.
# [--with-rice-dir=DIR] The rice gem's directory, since Fledge runs this
#                       with --disable-gems.

require "mkmf"
require "rbconfig"
require "shellwords"
require_relative "engine"

abi = RbConfig::CONFIG.fetch("CC").include?("aarch64-linux-android") ? "arm64-v8a" : "x86_64"
lota_source = with_config("lota-source")
if lota_source
  lota_source = File.expand_path(lota_source)
  abort "#{lota_source} has no vendor/love; run git submodule update --init there" unless
    File.exist?(File.join(lota_source, "vendor/love/src/common/Object.h"))
  deps = with_config("lota-android-deps") or abort "Lota's Android build from source needs " \
    "--with-lota-android-deps=DIR, from rake android:deps"
  sdl3 = with_config("lota-sdl3", deps)
  engine = [
    "-DENGINE_SOURCE_DIR:PATH=#{File.join(lota_source, 'vendor/love')}",
    "-DLOTA_ANDROID_SDL3_DIR:PATH=#{File.join(File.expand_path(sdl3), abi)}",
    "-DLOTA_ANDROID_DEPS_DIR:PATH=#{File.join(File.expand_path(deps), abi)}",
  ]
else
  begin
    prebuilt = Lota::PhoneEngine.new("android-#{abi}", ext: File.expand_path("..", __dir__),
      url: with_config("lota-engine-url")).fetch(cache: with_config("lota-engine-cache", Lota::PhoneEngine.cache))
  rescue Lota::PhoneEngine::Failure => e
    abort e.message
  end
  engine = ["-DLOTA_ENGINE_DIR:PATH=#{prebuilt}"]
end
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
  *engine,
  "-DRICE_DIR:PATH=#{File.expand_path(rice)}",
  "-DLOTA_RUBY_INCLUDE_DIRS=#{[RbConfig::CONFIG['rubyhdrdir'], RbConfig::CONFIG['rubyarchhdrdir']].uniq.join(';')}",
  "-DLOTA_NATIVE_TEST=OFF",
  "-DLOTA_SANITIZE=OFF",
]
system(*configure) or abort "CMake could not configure Lota for #{abi} (its output is above)."
system(cmake, "--build", build, "--target", "lota_native") or abort "CMake could not build Lota for #{abi}."

engine_archive = prebuilt ? File.join(prebuilt, "lib/liblota_engine.a") : File.join(build, "engine/liblota_engine.a")
archives = [File.join(build, "lib/lota/liblota_native.a"), engine_archive]
libraries, flags = File.readlines(File.join(build, "phone_link.txt"), chomp: true).reject(&:empty?)
  .partition { |line| line.end_with?(".a") }
$LOCAL_LIBS << " #{(archives + libraries).shelljoin}"
$libs << " #{flags.shelljoin}"
# iOS's entry point sits beside this one (phone/native_ios.c).
$srcs = ["native_android.c"]
create_makefile("lota/native", __dir__)
