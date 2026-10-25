# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "open3"
require "rbconfig"

# ext/lota/extconf.rb, run as RubyGems and rake-compiler run it: in a
# directory of its own, with the Ruby that will load the extension.
class ExtconfTest < Minitest::Test
  include TreeHelper

  parallelize_me!

  EXTCONF = File.join(ROOT, "ext/lota/extconf.rb")

  def extconf(dir, *options, script: EXTCONF)
    Open3.capture2e(RbConfig.ruby, script, *options, chdir: dir)
  end

  # The CMake cache's entries, one per line.
  def cache(build)
    File.readlines(File.join(build, "CMakeCache.txt"), chomp: true).grep(/\A\w+:\w+=/)
  end

  def test_it_builds_against_the_rice_the_gemspec_pins
    pinned = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).dependencies.find { |dep| dep.name == "rice" }

    assert_equal Gem::Requirement.new("= #{File.read(EXTCONF)[/^RICE_VERSION = "(.+)"$/, 1]}"), pinned.requirement
  end

  def test_it_configures_cmake_with_this_ruby_and_the_pinned_rice
    in_tree do |root|
      build = File.join(root, "build")
      output, status = extconf(root, "--with-cmake-build-dir=#{build}")

      assert status.success?, output
      assert_includes cache(build), "Ruby_EXECUTABLE:FILEPATH=#{RbConfig.ruby}"
      assert_includes cache(build), "RICE_DIR:PATH=#{Gem.loaded_specs.fetch('rice').full_gem_path}"
      assert_includes cache(build), "LOTA_NATIVE_TEST:BOOL=OFF"
      assert_includes cache(build), "LOTA_SANITIZE:BOOL=OFF"
      assert_includes cache(build), "CMAKE_GENERATOR:INTERNAL=Ninja"
    end
  end

  def test_options_turn_on_the_test_extension_and_the_sanitizers
    in_tree do |root|
      build = File.join(root, "build")
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", "--enable-native-test", "--enable-sanitizers")

      assert status.success?, output
      assert_includes cache(build), "LOTA_NATIVE_TEST:BOOL=ON"
      assert_includes cache(build), "LOTA_SANITIZE:BOOL=ON"
    end
  end

  # What make and make install do, as RubyGems and rake-compiler call them
  # (make -n prints the commands without running them).
  def test_the_makefile_builds_with_cmake_and_installs_the_bundle
    in_tree do |root|
      build = File.join(root, "build")
      output, status = extconf(root, "--with-cmake-build-dir=#{build}")
      assert status.success?, output

      install = run!(root, "make", "-n", "install", "sitearchdir=/site", "target_prefix=/lota", "DESTDIR=/dest")
      assert_includes install, "cmake --build #{build}\n"
      assert_includes install, "cp #{build}/lib/lota/native.bundle native.bundle\n"
      assert_includes install, "mkdir -p /dest/site/lota\n"
      assert_includes install, "cp native.bundle /dest/site/lota/native.bundle\n"
      assert_equal "rm -f native.bundle\n", run!(root, "make", "-n", "clean")
    end
  end

  # The source gem ships without LÖVE's sources, so gem install stops here
  # and names the gem that runs instead.
  def test_without_vendor_love_it_names_the_precompiled_gem
    in_tree do |root|
      script = write(root, "ext/lota/extconf.rb", File.read(EXTCONF))
      output, status = extconf(root, script:)

      refute status.success?
      assert_includes output, "Lota builds LÖVE's engine from vendor/love, which is missing from #{root}."
      assert_includes output, "(platform arm64-darwin) and Ruby 4.0"
      assert_includes output, "git submodule update --init"
      refute_path_exists File.join(root, "Makefile")
    end
  end

  # Only a build in a clone reads Rice, so Bundler installs it there and
  # no installed gem depends on it.
  def test_rice_is_a_development_dependency
    rice = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).dependencies.find { |dep| dep.name == "rice" }

    assert_equal :development, rice.type
  end
end
