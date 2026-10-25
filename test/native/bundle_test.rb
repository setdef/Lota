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

  BUNDLES = { "lota/native" => "_Init_native", "lota_native_test" => "_Init_lota_native_test" }.freeze

  def tool(*command)
    output, status = capture2e(TOOL_ENV, *command)
    assert status.success?, "#{command.join(' ')} failed (#{status.inspect}):\n#{output}"
    output
  end

  def test_each_bundle_exports_only_its_init_function
    BUNDLES.each do |feature, init|
      exported = tool("nm", "-gU", loaded(feature)).lines.map { |line| line.split.last }

      assert_equal [init], exported, feature
    end
  end

  def test_rpaths_are_relative_to_the_bundle_and_name_existing_directories
    BUNDLES.each_key do |feature|
      bundle = loaded(feature)
      rpaths = tool("otool", "-l", bundle).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten
      ours = rpaths.select { |path| path.include?("love-apple-dependencies") }

      refute_empty ours, feature
      ours.each do |path|
        assert path.start_with?("@loader_path/"), "#{feature}: #{path} is not relative to the bundle"
        assert File.directory?(path.sub("@loader_path", File.dirname(bundle))), "#{feature}: #{path} does not resolve"
      end
    end
  end

  # System libraries load by absolute path, and LÖVE's frameworks through
  # @rpath, which the bundle's relative rpaths resolve, so no load command
  # names the machine that built it. The sanitizer runtime is the one
  # @rpath library they do not resolve; DYLD_INSERT_LIBRARIES loads it
  # (tasks/sanitized_build.rb).
  def test_bundles_load_frameworks_only_through_their_relative_rpaths
    BUNDLES.each_key do |feature|
      bundle = loaded(feature)
      rpaths = tool("otool", "-l", bundle).scan(/^\s+path @loader_path(\S+) \(offset \d+\)$/).flatten
      libraries = tool("otool", "-L", bundle).lines.drop(1).map { |line| line.split.first }

      libraries.each do |library|
        next if library.start_with?("/usr/lib/", "/System/", "@rpath/libclang_rt.")

        assert library.start_with?("@rpath/"), "#{feature} loads #{library}"
        name = library.delete_prefix("@rpath/")
        assert rpaths.any? { |rpath| File.exist?(File.join(File.dirname(bundle), rpath, name)) },
          "#{feature}: no rpath resolves #{library}"
      end
    end
  end

  # The window needs SDL at load time, and Lota::Native binds the window.
  def test_lota_native_loads_sdl
    libraries = tool("otool", "-L", loaded("lota/native")).lines.drop(1).map { |line| line.split.first }

    assert_includes libraries, "@rpath/SDL3.framework/Versions/A/SDL3"
  end

  # Every binding reaches Rice through native/binding.hpp, so no binding
  # can wrap a love::Object with Rice's deleting Wrapper.
  def test_only_binding_hpp_includes_rice
    sources = Dir.glob("ext/**/*.{cpp,hpp,h}", base: ROOT)
    includers = sources.select { |path| File.read(File.join(ROOT, path)).match?(%r{#include\s*<rice/}) }

    assert_equal ["ext/lota/native/binding.hpp"], includers
  end
end
