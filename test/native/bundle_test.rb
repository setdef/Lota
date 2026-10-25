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

  # Neither bundle binds anything that needs a window, so neither loads
  # LÖVE's frameworks, and no load command names the machine that built it.
  def test_bundles_load_no_framework_by_absolute_path
    BUNDLES.each_key do |feature|
      libraries = tool("otool", "-L", loaded(feature)).lines.drop(1).map { |line| line.split.first }

      libraries.each do |library|
        assert library.start_with?("/usr/lib/", "/System/", "@rpath/libclang_rt."), "#{feature} loads #{library}"
      end
    end
  end

  # Every binding reaches Rice through native/binding.hpp, so no binding
  # can wrap a love::Object with Rice's deleting Wrapper.
  def test_only_binding_hpp_includes_rice
    sources = Dir.glob("ext/**/*.{cpp,hpp,h}", base: ROOT)
    includers = sources.select { |path| File.read(File.join(ROOT, path)).match?(%r{#include\s*<rice/}) }

    assert_equal ["ext/lota/native/binding.hpp"], includers
  end
end
