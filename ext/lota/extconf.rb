# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Configures Lota's CMake project (CMakeLists.txt beside this file) and
# writes a Makefile that builds it, as Plan 001's walking skeleton asks.
# RubyGems runs this at gem install, and rake-compiler at rake compile; both
# then run make and make install, which this Makefile turns into a CMake
# build and a copy of the bundle.
#
# Options, which rake passes through rake-compiler (tasks/native.rake):
#
# [--with-cmake-build-dir=DIR] The CMake build tree; default +build+ here.
# [--enable-native-test] Also build the test-only extension.
# [--enable-sanitizers] Build everything with ASan and UBSan.

require "mkmf"
require "rbconfig"
require "shellwords"

# The Rice lota.gemspec pins. Its headers are what the extension compiles
# against, so the version must match what binding.hpp specializes.
RICE_VERSION = "4.12.0"

# The repository, or the installed gem: the directory that holds ext/.
#
# Only a clone can build: the build needs LÖVE's sources from vendor/, and
# its dependencies, love-apple-dependencies' frameworks from vendor/ or on
# Linux the libraries `rake dependencies` builds, and the source gem ships
# none of them. RubyGems installs the source gem only where no precompiled
# gem fits (tasks/native_gem.rb), so stopping here, before CMake and Rice,
# names the gems that do.
ROOT = File.expand_path("../..", __dir__)
unless File.exist?(File.join(ROOT, "vendor/love/src/common/Object.h"))
  abort <<~MESSAGE
    Lota builds LÖVE's engine from vendor/love, which is missing from #{ROOT}.

    Lota's source gem does not ship LÖVE's sources, so it cannot build here.
    Install Lota's precompiled gem instead, which RubyGems chooses for Ruby
    4.0 on Apple Silicon macOS (platform arm64-darwin) and on Linux with
    glibc on x86_64 or arm64 (x86_64-linux-gnu, aarch64-linux-gnu). Lota
    has no build for other platforms or Rubies yet.

    In a clone of Lota's repository, run `git submodule update --init`.
  MESSAGE
end

cmake = find_executable("cmake") or abort "Lota's extension builds with CMake, which is not on PATH."
build = File.expand_path(with_config("cmake-build-dir", "build"))

gem "rice", RICE_VERSION
rice = Gem.loaded_specs.fetch("rice").full_gem_path

configure = [cmake, "-S", __dir__, "-B", build]
configure += %w[-G Ninja] if find_executable("ninja")
configure += [
  "-DRuby_EXECUTABLE:FILEPATH=#{RbConfig.ruby}",
  "-DRICE_DIR:PATH=#{rice}",
  "-DLOTA_NATIVE_TEST=#{enable_config('native-test', false) ? 'ON' : 'OFF'}",
  "-DLOTA_SANITIZE=#{enable_config('sanitizers', false) ? 'ON' : 'OFF'}",
]
# From this directory, so a version manager's shim (mise.toml) resolves
# cmake as it does in the repository, whatever directory runs this script.
system(*configure, chdir: __dir__) or abort "CMake could not configure #{__dir__} into #{build} (its output is above)."

# make runs in other directories, so the Makefile names the cmake binary
# itself, which CMake records, rather than whatever is first on PATH.
cmake = File.read(File.join(build, "CMakeCache.txt"))[/^CMAKE_COMMAND:INTERNAL=(.+)$/, 1]

# rake-compiler and RubyGems run make install with sitearchdir set to where
# the bundle belongs, and target_prefix to its directory under it. The
# bundle replaces the one there, rather than being written over it, since
# a process may have the old one loaded, as rake test's has when it builds
# the sanitized tree: Linux maps a library from its file, and a process
# that reads a page of one written over while it runs dies with SIGBUS.
bundle = "native.#{RbConfig::CONFIG['DLEXT']}"
File.write("Makefile", <<~MAKEFILE)
  # Written by ext/lota/extconf.rb. Do not edit.
  CMAKE = #{cmake.shellescape}
  BUILD = #{build.shellescape}
  BUNDLE = #{bundle}
  sitearchdir = #{RbConfig::CONFIG['sitearchdir'].shellescape}
  target_prefix = /lota
  DESTDIR =

  all:
  \t$(CMAKE) --build $(BUILD)
  \tcp $(BUILD)/lib/lota/$(BUNDLE) $(BUNDLE)

  install: all
  \tmkdir -p $(DESTDIR)$(sitearchdir)$(target_prefix)
  \tcp $(BUNDLE) $(DESTDIR)$(sitearchdir)$(target_prefix)/$(BUNDLE).new
  \tmv -f $(DESTDIR)$(sitearchdir)$(target_prefix)/$(BUNDLE).new $(DESTDIR)$(sitearchdir)$(target_prefix)/$(BUNDLE)

  clean:
  \trm -f $(BUNDLE)

  .PHONY: all install clean
MAKEFILE
