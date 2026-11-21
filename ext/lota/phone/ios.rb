# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Lota's extension for an iOS or iPadOS app, which ext/lota/extconf.rb
# loads when Fledge's `fledge build ios` runs it for one of the app's
# slices: under the phone Ruby's rbconfig.rb, with mkmf's $static set, and
# CMAKE_TOOLCHAIN_FILE in the environment naming the slice's SDK and
# compilers (Fledge's doc/contributors/design/phone-projects.md, "Gems with extensions" and "CMake
# toolchain files"). An iOS app loads no extension at
# run time, so everything here is a static archive the app links.
#
# LÖVE's engine, with the libraries it links, comes prebuilt for the
# slice from Lota's release (phone/engine.rb), checked against the SHA-256
# this gem pins; or, given a clone of Lota, CMake builds it from LÖVE's
# sources as on a desktop, as a static archive. Lota::Native comes
# prebuilt as well, from the same release, when the gem pins it for the
# slice and the phone's Ruby is the one it was built against
# (phone/extension.rb), and then neither CMake nor Rice is needed.
# Otherwise CMake builds Lota::Native (CMakeLists.txt beside extconf.rb)
# over the engine. Either way mkmf compiles
# phone/native_ios.c, whose Init_native calls the extension's, and names
# the archives and the system's libraries for Fledge to link
# (phone_link.txt, which engine/dependencies_ios.cmake or the prebuilt
# engine's engine.cmake writes).
#
# Options, which Bundler passes from `bundle config build.lota`:
#
# [--with-lota-source=DIR] Build the engine from source, from a clone of
#                          Lota's repository with its submodules: the gem
#                          does not carry LÖVE's sources (vendor/love) or
#                          its iOS libraries (vendor/love-apple-dependencies).
# [--with-lota-sdl3=DIR] With --with-lota-source, SDL3 built static for
#                        each slice, in DIR/ios-arm64 and
#                        DIR/ios-arm64-simulator (`rake ios:sdl3` in that
#                        clone).
# [--with-lota-engine-url=URL] Where to fetch the prebuilt engine from, a
#                              mirror of the release's assets; by default
#                              the release of this version of Lota.
# [--with-lota-engine-cache=DIR] Where fetched engines are kept; by
#                                default lota/phone-engine in
#                                XDG_CACHE_HOME or ~/.cache.
# [--with-rice-dir=DIR] The rice gem's directory, since Fledge runs this
#                       with --disable-gems; needed only to compile the
#                       extension, which it then does in place of one
#                       the gem pins for another Ruby.
# [--with-lota-extension-out=DIR] Compile the extension against the
#                                 prebuilt engine even if the gem pins a
#                                 prebuilt one, and pack it into DIR as
#                                 the bundle a release publishes, as
#                                 Lota's CI builds it.
# [--with-lota-extension-fledge=TAG] With --with-lota-extension-out, the
#                                    tag of the Fledge running the
#                                    build, which the bundle records.

require "mkmf"
require "rbconfig"
require "shellwords"
require_relative "engine"
require_relative "extension"
require_relative "../../../lib/lota/version"

ios_slice = RbConfig::CONFIG.fetch("CC").include?("-simulator") ? "ios-arm64-simulator" : "ios-arm64"
ext = File.expand_path("..", __dir__)
headers = Lota::PhoneExtension::Headers.of(RbConfig::CONFIG)
keep = with_config("lota-extension-out")
fledge = keep && (with_config("lota-extension-fledge") or abort "--with-lota-extension-out needs " \
  "--with-lota-extension-fledge=TAG, the tag of the Fledge running the build")
lota_source = with_config("lota-source")
if lota_source
  lota_source = File.expand_path(lota_source)
  abort "#{lota_source} has no vendor/love; run git submodule update --init there" unless
    File.exist?(File.join(lota_source, "vendor/love/src/common/Object.h"))
  sdl3 = with_config("lota-sdl3") or abort "Lota's iOS build from source needs --with-lota-sdl3=DIR, from rake ios:sdl3"
  engine = [
    "-DENGINE_SOURCE_DIR:PATH=#{File.join(lota_source, 'vendor/love')}",
    "-DENGINE_DEPS_DIR:PATH=#{File.join(lota_source, 'vendor/love-apple-dependencies')}",
    "-DLOTA_IOS_SDL3_DIR:PATH=#{File.join(File.expand_path(sdl3), ios_slice)}",
  ]
else
  begin
    cache = with_config("lota-engine-cache", Lota::PhoneEngine.cache)
    url = with_config("lota-engine-url")
    prebuilt = Lota::PhoneEngine.new(ios_slice, ext:, url:).fetch(cache:)
    extension = Lota::PhoneExtension.new(ios_slice, ext:, url:, headers:, compiles: !with_config("rice-dir").nil?)
    fetched = extension.fetch(cache:) if extension.pinned? && !keep
  rescue Lota::PhoneEngine::Failure => e
    abort e.message
  end
  engine = ["-DLOTA_ENGINE_DIR:PATH=#{prebuilt}"]
end
engine_archive = prebuilt && File.join(prebuilt, "lib/liblota_engine.a")

if fetched
  archives = [File.join(fetched, "lib/liblota_native.a"), engine_archive]
  link = Lota::PhoneExtension.link(fetched, prebuilt)
else
  rice = with_config("rice-dir") or abort "Lota's iOS build needs --with-rice-dir=DIR, the rice gem's directory"
  ENV["CMAKE_TOOLCHAIN_FILE"] or abort "Lota's iOS build needs CMAKE_TOOLCHAIN_FILE, which fledge build ios sets"

  cmake = find_executable("cmake") or abort "Lota's extension builds with CMake, which is not on PATH."
  # A new folder for each slice, which is how CMake reads the toolchain from
  # the environment (cmake-env-variables(7), CMAKE_TOOLCHAIN_FILE).
  build = File.expand_path("lota-build")
  configure = [cmake, "-S", ext, "-B", build]
  configure += %w[-G Ninja] if find_executable("ninja")
  configure += [
    "-DCMAKE_BUILD_TYPE=Release",
    *engine,
    "-DRICE_DIR:PATH=#{File.expand_path(rice)}",
    "-DLOTA_RUBY_INCLUDE_DIRS=#{[RbConfig::CONFIG['rubyhdrdir'], RbConfig::CONFIG['rubyarchhdrdir']].uniq.join(';')}",
    "-DLOTA_NATIVE_TEST=OFF",
    "-DLOTA_SANITIZE=OFF",
  ]
  # Apple's archivers write each member's date unless told not to, so a
  # kept archive (--with-lota-extension-out) holds none.
  ENV["ZERO_AR_DATE"] = "1"
  system(*configure) or abort "CMake could not configure Lota for #{ios_slice} (its output is above)."
  system(cmake, "--build", build, "--target", "lota_native") or abort "CMake could not build Lota for #{ios_slice}."

  engine_archive ||= File.join(build, "engine/liblota_engine.a")
  archives = [File.join(build, "lib/lota/liblota_native.a"), engine_archive]
  link = File.readlines(File.join(build, "phone_link.txt"), chomp: true).reject(&:empty?)
  if keep
    abort "--with-lota-extension-out keeps an extension built against a prebuilt engine, not one from source" unless
      prebuilt
    puts "Lota's extension for #{ios_slice}, kept: " +
      Lota::PhoneExtension.pack(into: File.expand_path(keep), target: ios_slice, archive: archives.first, link:,
        engine: prebuilt, ext:, headers:, fledge:, version: Lota::VERSION)
  end
end
libraries, flags = link.partition { |line| line.end_with?(".a") }
$LOCAL_LIBS << " #{(archives + libraries).shelljoin}"
$libs << " #{flags.shelljoin}"
# Android's entry point sits beside this one (phone/native_android.c).
$srcs = ["native_ios.c"]
create_makefile("lota/native", __dir__)
