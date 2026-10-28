# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "json"
require "tmpdir"

# What the compiled bundles export, link, and look for at load time
# (ext/lota/cmake/LotaExtension.cmake), checked on the bundles this
# process loaded.
class BundleTest < Minitest::Test
  include NativeHelper

  BUNDLES = { "lota/native" => "Init_native", "lota_native_test" => "Init_lota_native_test" }.freeze

  # What a bundle's rpaths start with to be relative to the bundle: dyld's
  # @loader_path on macOS, and $ORIGIN on Linux (ld.so(8)).
  RELATIVE = TestHome::LINUX ? "$ORIGIN" : "@loader_path"

  # The directory LÖVE's dependencies are found in, which the rpaths point
  # into: love-apple-dependencies on macOS, and on Linux the installdir
  # rake dependencies builds in tmp/dependencies (tasks/linux_build.rb),
  # which an extension in tmp/engine/build reaches as ../dependencies.
  DEPENDENCIES = TestHome::LINUX ? "dependencies/installdir" : "love-apple-dependencies"

  def tool(*command)
    output, status = capture2e(TOOL_ENV, *command)
    assert status.success?, "#{command.join(' ')} failed (#{status.inspect}):\n#{output}"
    output
  end

  # The symbols +bundle+ exports, as C names them.
  def exported(bundle)
    return tool("nm", "-D", "--defined-only", bundle).lines.map { |line| line.split.last } if TestHome::LINUX

    tool("nm", "-gU", bundle).lines.map { |line| line.split.last.delete_prefix("_") }
  end

  # The rpaths +bundle+ names, as it names them.
  def rpaths(bundle)
    return tool("otool", "-l", bundle).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten unless TestHome::LINUX

    tool("readelf", "-d", bundle).scan(/\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*)\]$/).flatten
      .flat_map { |paths| paths.split(":") }
  end

  # The libraries +bundle+ loads, as it names them.
  def libraries(bundle)
    return tool("readelf", "-d", bundle).scan(/\(NEEDED\)\s+Shared library: \[(.*)\]$/).flatten if TestHome::LINUX

    tool("otool", "-L", bundle).lines.drop(1).map { |line| line.split.first }
  end

  # Whether +library+, as a bundle names it, is the system's own, which
  # it loads from where the system keeps it: on macOS by absolute path,
  # and on Linux by a name the dynamic linker's cache knows. The sanitizer
  # runtime is one; DYLD_INSERT_LIBRARIES or LD_PRELOAD loads it
  # (tasks/sanitized_build.rb).
  def system_library?(library)
    return library.start_with?("/usr/lib/", "/System/", "@rpath/libclang_rt.") unless TestHome::LINUX

    @system_libraries ||= tool("ldconfig", "-p").scan(/^\s+(\S+) \(/).flatten
    @system_libraries.include?(library)
  end

  # Where +library+, as +bundle+ names it, is found through the bundle's
  # relative rpaths, or nil.
  def through_rpaths(bundle, library)
    name = library.delete_prefix("@rpath/")
    rpaths(bundle).filter_map { |rpath| rpath.sub(RELATIVE, File.dirname(bundle)) if rpath.start_with?(RELATIVE) }
      .map { |directory| File.join(directory, name) }.find { |path| File.exist?(path) }
  end

  def test_each_bundle_exports_only_its_init_function
    BUNDLES.each do |feature, init|
      assert_equal [init], exported(loaded(feature)), feature
    end
  end

  def test_rpaths_are_relative_to_the_bundle_and_name_existing_directories
    BUNDLES.each_key do |feature|
      bundle = loaded(feature)
      ours = rpaths(bundle).select { |path| path.include?(DEPENDENCIES) }

      refute_empty ours, feature
      ours.each do |path|
        assert path.start_with?("#{RELATIVE}/"), "#{feature}: #{path} is not relative to the bundle"
        assert File.directory?(path.sub(RELATIVE, File.dirname(bundle))), "#{feature}: #{path} does not resolve"
      end
    end
  end

  # System libraries load from where the system keeps them, and LÖVE's
  # libraries, frameworks on macOS, through the bundle's relative rpaths,
  # so no load command names the machine that built it.
  def test_bundles_load_libraries_only_through_their_relative_rpaths
    BUNDLES.each_key do |feature|
      bundle = loaded(feature)

      libraries(bundle).each { |library| assert_loads(feature, bundle, library) }
    end
  end

  # Whether +library+ is one of LÖVE's dependencies: on macOS, one that
  # is not the system's; on Linux, one the installdir has.
  def ours?(library)
    return !system_library?(library) unless TestHome::LINUX

    File.exist?(File.join(ROOT, "tmp", DEPENDENCIES, "lib", library))
  end

  # On macOS LÖVE's frameworks load through @rpath and the rest by
  # absolute path; on Linux a library is LÖVE's when the installdir has
  # it, and the system's otherwise.
  def assert_loads(feature, bundle, library)
    unless ours?(library)
      assert system_library?(library), "#{feature} loads #{library}, which is neither LÖVE's nor one the " \
        "dynamic linker's cache knows"
      return
    end

    assert library.start_with?("@rpath/"), "#{feature} loads #{library}" unless TestHome::LINUX
    assert through_rpaths(bundle, library), "#{feature}: no rpath resolves #{library}"
  end

  # The window needs SDL at load time, and Lota::Native binds the window.
  def test_lota_native_loads_sdl
    sdl = TestHome::LINUX ? "libSDL3.so.0" : "@rpath/SDL3.framework/Versions/A/SDL3"

    assert_includes libraries(loaded("lota/native")), sdl
  end

  # Every binding reaches Rice through native/binding.hpp, so no binding
  # can wrap a love::Object with Rice's deleting Wrapper.
  def test_only_binding_hpp_includes_rice
    sources = Dir.glob("ext/**/*.{cpp,hpp,h}", base: ROOT)
    includers = sources.select { |path| File.read(File.join(ROOT, path)).match?(%r{#include\s*<rice/}) }

    assert_equal ["ext/lota/native/binding.hpp"], includers
  end
end
