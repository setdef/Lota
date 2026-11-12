# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
      bundle = "native.#{RbConfig::CONFIG['DLEXT']}"
      assert_includes install, "cp #{build}/lib/lota/#{bundle} #{bundle}\n"
      assert_includes install, "mkdir -p /dest/site/lota\n"
      assert_includes install, "cp #{bundle} /dest/site/lota/#{bundle}.new\n"
      assert_includes install, "mv -f /dest/site/lota/#{bundle}.new /dest/site/lota/#{bundle}\n"
      assert_equal "rm -f #{bundle}\n", run!(root, "make", "-n", "clean")
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
      assert_includes output, "4.1 on Apple Silicon macOS (platform arm64-darwin) and on Linux with\nglibc on x86_64 or arm64 (x86_64-linux-gnu, aarch64-linux-gnu)"
      assert_includes output, "git submodule update --init"
      refute_path_exists File.join(root, "Makefile")
    end
  end

  # A gem's phone build, as `fledge build` unpacks it: extconf.rb, its
  # phone scripts, and lib/lota/version.rb, pinning +pin+ (the text of
  # ext/lota/phone/engines.txt). Returns extconf.rb's path.
  def phone_gem(root, pin: "")
    %w[extconf.rb phone/ios.rb phone/android.rb phone/engine.rb].each do |file|
      write(root, "ext/lota/#{file}", File.read(File.join(ROOT, "ext/lota", file)))
    end
    write(root, "lib/lota/version.rb", File.read(File.join(ROOT, "lib/lota/version.rb")))
    write(root, "ext/lota/phone/engines.txt", pin)
    File.join(root, "ext/lota/extconf.rb")
  end

  # A shim that stands in for a phone Ruby's rbconfig.rb, whose compiler
  # aims at an iOS slice or is the NDK's for an ABI.
  def phone_rbconfig(root, compiler)
    write(root, "phone_rbconfig.rb", "require \"rbconfig\"\nRbConfig::CONFIG[\"CC\"] = #{compiler.inspect}\n")
  end

  IOS_SIMULATOR = "clang -target arm64-apple-ios15.0-simulator"
  ANDROID_X86_64 = "/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang"

  # fledge build ios runs extconf.rb under an iOS Ruby's rbconfig.rb, and
  # the gem it unpacks has no vendor/: the iOS build fetches the engine
  # the gem pins, and a gem that pins none says to build from a clone,
  # before CMake runs.
  def test_under_an_ios_rbconfig_a_gem_that_pins_no_engine_asks_for_a_clone
    in_tree do |root|
      script = phone_gem(root)
      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, IOS_SIMULATOR), script, chdir: root)

      refute status.success?
      assert_includes output, "This Lota pins no prebuilt engine for ios-arm64-simulator"
      assert_includes output, "--with-lota-source=DIR"
      refute_includes output, "Lota's source gem does not ship LÖVE's sources"
      refute_path_exists File.join(root, "Makefile")
    end
  end

  # fledge build android does the same under an Android Ruby's
  # rbconfig.rb, whose compiler is the NDK's for an ABI.
  def test_under_an_android_rbconfig_a_gem_that_pins_no_engine_asks_for_a_clone
    in_tree do |root|
      script = phone_gem(root)
      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, ANDROID_X86_64), script, chdir: root)

      refute status.success?
      assert_includes output, "This Lota pins no prebuilt engine for android-x86_64"
      refute_includes output, "ios"
      refute_includes output, "Lota's source gem does not ship LÖVE's sources"
      refute_path_exists File.join(root, "Makefile")
    end
  end

  # Asked to build from source, the phone build checks the clone first.
  def test_a_phone_build_from_source_needs_a_clone_with_vendor_love
    in_tree do |root|
      script = phone_gem(root)
      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, ANDROID_X86_64), script,
        "--with-lota-source=#{root}/clone", chdir: root)

      refute status.success?
      assert_includes output, "#{root}/clone has no vendor/love"
    end
  end

  # The engine a gem pins is fetched, checked, and unpacked before the
  # rest of the build, here from a mirror in a folder.
  def test_a_phone_build_fetches_the_pinned_engine_from_a_mirror
    in_tree do |root|
      phone_gem(root)
      require_relative "../../tasks/phone_engine"
      manifest = JSON.generate("target" => "android-x86_64",
        "engine_digest" => Lota::PhoneEngine.digest(File.join(root, "ext/lota")))
      files = {
        "manifest.json" => PhoneEngineBuild::Contents.new(text: manifest),
        "lib/liblota_engine.a" => PhoneEngineBuild::Contents.new(text: "!<arch>\n"),
      }
      sha256 = PhoneEngineBuild.write(File.join(root, "mirror", Lota::PhoneEngine.asset("android-x86_64")), files)
      script = phone_gem(root, pin: "release v1.2.3\n#{sha256}  lota-engine-android-x86_64.tar.gz\n")

      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, ANDROID_X86_64), script,
        "--with-lota-engine-url=file://#{root}/mirror/", "--with-lota-engine-cache=#{root}/cache", chdir: root)

      refute status.success?
      assert_includes output, "Lota's engine for android-x86_64: #{root}/cache/#{sha256}/android-x86_64"
      assert_includes output, "Lota's Android build needs --with-rice-dir=DIR"
      assert_path_exists File.join(root, "cache", sha256, "android-x86_64/lib/liblota_engine.a")
    end
  end

  # Only a build in a clone reads Rice, so Bundler installs it there and
  # no installed gem depends on it.
  def test_rice_is_a_development_dependency
    rice = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).dependencies.find { |dep| dep.name == "rice" }

    assert_equal :development, rice.type
  end
end
