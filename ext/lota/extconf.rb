# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Configures Lota's CMake project (CMakeLists.txt beside this file) and
# writes a Makefile that builds it.
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

# fledge build ios runs this under an iOS Ruby's rbconfig.rb, whose
# compiler aims at an iOS slice; phone/ios.rb builds the extension there.
if RbConfig::CONFIG.fetch("CC").match?(/-target arm64-apple-ios/)
  require_relative "phone/ios"
  return
end
# fledge build android runs it under an Android Ruby's rbconfig.rb, whose
# compiler is the NDK's for an ABI (aarch64-linux-android26-clang);
# phone/android.rb builds the extension there.
if RbConfig::CONFIG.fetch("CC").match?(/-linux-android\d*-clang/)
  require_relative "phone/android"
  return
end

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
    4.1 on Apple Silicon macOS (platform arm64-darwin) and on Linux with
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
# The ninja on PATH now, by its path. CMake keeps the generator's program
# in its cache, CMAKE_MAKE_PROGRAM, which find_program fills once and never
# searches for again while it is set (CMakeNinjaFindMake.cmake), so a tree
# configured before a version manager moved or upgraded ninja otherwise
# fails in project(), running a ninja that is gone. Naming it changes no
# compile command, so nothing is rebuilt for it.
ninja = find_executable("ninja")
configure += ["-G", "Ninja", "-DCMAKE_MAKE_PROGRAM:FILEPATH=#{ninja}"] if ninja
# The compiler launchers the environment names (ccache), for the same
# reason: CMake takes CMAKE_<language>_COMPILER_LAUNCHER from the
# environment only when it makes a tree, so a tree configured before a
# version manager moved ccache went on compiling through the one that is
# gone, every compile command failing with "not found". A language the
# environment names none for is cleared. Objective-C's are named only
# where the environment or the tree knows them, since a tree that never
# enabled those languages would warn of an unused variable.
cache = File.join(build, "CMakeCache.txt")
known = File.exist?(cache) ? File.read(cache) : ""
%w[C CXX OBJC OBJCXX].each do |language|
  variable = "CMAKE_#{language}_COMPILER_LAUNCHER"
  next unless %w[C CXX].include?(language) || ENV.key?(variable) || known.include?("#{variable}:")

  configure << "-D#{variable}:STRING=#{ENV.fetch(variable, '')}"
end
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
# On Windows the preloader goes beside the bundle, and the DLLs it loads in
# libraries/ beside them (ext/lota/preload).
preload = "preload.#{RbConfig::CONFIG['DLEXT']}"
windows = RbConfig::CONFIG["host_os"].include?("mingw")
build_preload = windows ? <<~MAKE : ""
  \tcp $(BUILD)/lib/lota/#{preload} #{preload}
  \trm -rf libraries
  \tcp -R $(BUILD)/lib/lota/libraries libraries
MAKE
install_preload = windows ? <<~MAKE : ""
  \tcp #{preload} $(DESTDIR)$(sitearchdir)$(target_prefix)/#{preload}
  \tcp -R libraries $(DESTDIR)$(sitearchdir)$(target_prefix)/
MAKE
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
  #{build_preload}
  install: all
  \tmkdir -p $(DESTDIR)$(sitearchdir)$(target_prefix)
  \tcp $(BUNDLE) $(DESTDIR)$(sitearchdir)$(target_prefix)/$(BUNDLE).new
  \tmv -f $(DESTDIR)$(sitearchdir)$(target_prefix)/$(BUNDLE).new $(DESTDIR)$(sitearchdir)$(target_prefix)/$(BUNDLE)
  #{install_preload}

  clean:
  \trm -f $(BUNDLE)

  .PHONY: all install clean
MAKEFILE
