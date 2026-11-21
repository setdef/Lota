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

  def extconf(dir, *options, script: EXTCONF, env: {})
    Open3.capture2e(env, RbConfig.ruby, script, *options, chdir: dir)
  end

  # An environment whose PATH looks in +dir+ first.
  def path_first(dir)
    { "PATH" => [dir, ENV.fetch("PATH")].join(File::PATH_SEPARATOR) }
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

  # A version manager moves ninja, as mise does when its data folder or the
  # pinned version changes, between two configures of one tree. The tree
  # keeps the first ninja's path in its cache, and the second configure
  # names the ninja on PATH now rather than fail in project() running the
  # one that is gone.
  def test_a_tree_whose_ninja_moved_configures_with_the_ninja_on_path
    in_tree do |root|
      exe = "ninja#{RbConfig::CONFIG['EXEEXT']}"
      ninja = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, exe) }
        .find { |path| File.executable?(path) && !File.directory?(path) }
      assert ninja, "no ninja on PATH, which mise.toml pins"
      build = File.join(root, "build")
      old = File.join(root, "old")
      FileUtils.mkdir_p(old)
      FileUtils.cp(File.realpath(ninja), old)
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", env: path_first(old))
      assert status.success?, output
      assert_includes cache(build), "CMAKE_MAKE_PROGRAM:FILEPATH=#{File.join(old, exe)}"

      new = File.join(root, "new")
      FileUtils.mv(old, new)
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", env: path_first(new))

      assert status.success?, output
      assert_includes cache(build), "CMAKE_MAKE_PROGRAM:FILEPATH=#{File.join(new, exe)}"
    end
  end

  # A compiler launcher that runs its command, as ccache does.
  def launcher(dir)
    write(dir, "ccache", "#!/bin/sh\nexec \"$@\"\n").tap { |file| File.chmod(0o755, file) }
  end

  # The names of CMake's compiler launchers, which it initializes from
  # these environment variables on a tree's first configure and never again.
  def launchers(path)
    { "CMAKE_C_COMPILER_LAUNCHER" => path, "CMAKE_CXX_COMPILER_LAUNCHER" => path }
  end

  # A compiler cache moves, as mise moves ccache when its folder changes,
  # between two configures of one tree. The tree keeps the first launcher's
  # path in its cache, so the second configure names the one the
  # environment holds now rather than compile through one that is gone.
  def test_a_tree_whose_compiler_launcher_moved_configures_with_the_one_in_the_environment
    in_tree do |root|
      build = File.join(root, "build")
      old = launcher(File.join(root, "old"))
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", env: launchers(old))
      assert status.success?, output
      assert_includes cache(build), "CMAKE_CXX_COMPILER_LAUNCHER:STRING=#{old}"

      new = File.join(root, "new")
      FileUtils.mv(File.dirname(old), new)
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", env: launchers(File.join(new, "ccache")))

      assert status.success?, output
      assert_includes cache(build), "CMAKE_C_COMPILER_LAUNCHER:STRING=#{File.join(new, 'ccache')}"
      assert_includes cache(build), "CMAKE_CXX_COMPILER_LAUNCHER:STRING=#{File.join(new, 'ccache')}"
    end
  end

  # A launcher the environment no longer names is not compiled through,
  # whatever the tree remembers.
  def test_a_tree_configured_with_a_launcher_configures_without_one_when_the_environment_has_none
    in_tree do |root|
      build = File.join(root, "build")
      old = launcher(File.join(root, "old"))
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", env: launchers(old))
      assert status.success?, output

      FileUtils.rm_rf(File.dirname(old))
      output, status = extconf(root, "--with-cmake-build-dir=#{build}", env: launchers(nil))

      assert status.success?, output
      assert_includes cache(build), "CMAKE_CXX_COMPILER_LAUNCHER:STRING="
      refute_includes cache(build), "CMAKE_CXX_COMPILER_LAUNCHER:STRING=#{old}"
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
    %w[extconf.rb phone/ios.rb phone/android.rb phone/engine.rb phone/extension.rb].each do |file|
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

  # A mirror in +root+ of the engine and the extension a release publishes
  # for +target+, the extension built against +ruby_version+ and the
  # headers of the Ruby running the test. Returns the pin of both.
  def phone_release(root, target, ruby_version: RbConfig::CONFIG["ruby_version"])
    require_relative "../../ext/lota/phone/extension"
    phone_gem(root)
    ext = File.join(root, "ext/lota")
    mirror = File.join(root, "mirror")
    manifest = JSON.generate("target" => target, "engine_digest" => Lota::PhoneEngine.digest(ext))
    engine = Lota::PhoneEngine.pack(File.join(mirror, Lota::PhoneEngine.asset(target)),
      { "manifest.json" => manifest, "lib/liblota_engine.a" => "!<arch>\n" })
    write(root, "built/liblota_native.a", "!<arch>\n")
    headers = Lota::PhoneExtension::Headers.of(RbConfig::CONFIG).with(ruby_version:)
    extension = Lota::PhoneExtension.pack(into: mirror, target:, archive: File.join(root, "built/liblota_native.a"),
      link: ["/built/engine/lib/libSDL3.a", "-lc++"], engine: "/built/engine", ext:, headers:, fledge: "v0.14.0",
      version: "1.2.3")
    "release v1.2.3\n#{engine}  #{Lota::PhoneEngine.asset(target)}\n" \
      "#{Digest::SHA256.file(extension).hexdigest}  #{Lota::PhoneExtension.asset(target)}\n"
  end

  # A gem that pins the extension too fetches it, and links it with the
  # fetched engine, with no CMake run and no Rice.
  def test_a_phone_build_links_the_pinned_extension_without_compiling_it
    in_tree do |root|
      script = phone_gem(root, pin: phone_release(root, "ios-arm64-simulator"))

      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, IOS_SIMULATOR), script,
        "--with-lota-engine-url=file://#{root}/mirror/", "--with-lota-engine-cache=#{root}/cache", chdir: root)

      assert status.success?, output
      fetched = output[/Lota's extension for ios-arm64-simulator: (\S+)/, 1]
      engine = output[/Lota's engine for ios-arm64-simulator: (\S+)/, 1]
      refute_nil fetched, output
      makefile = File.read(File.join(root, "Makefile"))
      assert_includes makefile, "#{fetched}/lib/liblota_native.a #{engine}/lib/liblota_engine.a #{engine}/lib/libSDL3.a"
      assert_match(/^LIBS = .* -lc\+\+/, makefile)
      refute_path_exists File.join(root, "lota-build")
    end
  end

  # A gem built between releases pins the last release's extension, built
  # from other files, so its build compiles the extension, which needs
  # Rice, as a gem that pins none does.
  def test_a_phone_build_compiles_the_extension_when_the_pinned_one_is_of_other_files
    in_tree do |root|
      pin = phone_release(root, "android-x86_64")
      write(root, "ext/lota/native/graphics.cpp", "void draw() {}\n")
      script = phone_gem(root, pin:)

      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, ANDROID_X86_64), script,
        "--with-lota-engine-url=file://#{root}/mirror/", "--with-lota-engine-cache=#{root}/cache", chdir: root)

      refute status.success?
      assert_includes output, "So Lota compiles its extension for android-x86_64."
      assert_includes output, "Lota's Android build needs --with-rice-dir=DIR"
    end
  end

  # An extension built for a Ruby of another ABI is refused before
  # anything links it, and the refusal says what to do.
  def test_a_phone_build_refuses_an_extension_built_for_another_ruby
    in_tree do |root|
      script = phone_gem(root, pin: phone_release(root, "android-x86_64", ruby_version: "4.0.0"))

      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, ANDROID_X86_64), script,
        "--with-lota-engine-url=file://#{root}/mirror/", "--with-lota-engine-cache=#{root}/cache", chdir: root)

      refute status.success?
      assert_includes output, "was built for Ruby 4.0.0, the phone Ruby of Fledge v0.14.0, and this phone's Ruby " \
        "is #{RbConfig::CONFIG['ruby_version']}, whose ABI differs. Name Fledge v0.14.0 in the Gemfile, or compile " \
        "the extension for this Ruby: pass --with-rice-dir=DIR"
      refute_path_exists File.join(root, "Makefile")
    end
  end

  # Given Rice, as the refusal says, the build compiles the extension for
  # its own Ruby instead, as far as CMake, which needs the toolchain
  # fledge build sets.
  def test_given_rice_a_phone_build_compiles_in_place_of_an_extension_for_another_ruby
    in_tree do |root|
      script = phone_gem(root, pin: phone_release(root, "android-x86_64", ruby_version: "4.0.0"))

      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, ANDROID_X86_64), script,
        "--with-lota-engine-url=file://#{root}/mirror/", "--with-lota-engine-cache=#{root}/cache",
        "--with-rice-dir=#{root}/rice", chdir: root)

      refute status.success?
      assert_includes output, "whose ABI differs."
      assert_includes output, "So Lota compiles its extension for android-x86_64."
      assert_includes output, "Lota's Android build needs CMAKE_TOOLCHAIN_FILE"
    end
  end

  # A kept extension records the Fledge that built it, which its
  # refusal names, so CI's build must say which.
  def test_keeping_the_extension_needs_the_fledge_tag
    in_tree do |root|
      script = phone_gem(root)

      output, status = Open3.capture2e(RbConfig.ruby, "-r", phone_rbconfig(root, IOS_SIMULATOR), script,
        "--with-lota-extension-out=#{root}/out", chdir: root)

      refute status.success?
      assert_includes output, "--with-lota-extension-out needs --with-lota-extension-fledge=TAG"
    end
  end

  # Only a build in a clone reads Rice, so Bundler installs it there and
  # no installed gem depends on it.
  def test_rice_is_a_development_dependency
    rice = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).dependencies.find { |dep| dep.name == "rice" }

    assert_equal :development, rice.type
  end
end
