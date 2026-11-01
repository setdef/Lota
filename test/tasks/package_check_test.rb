# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/package_check"
require "stringio"

# What PackageCheck reads from a compiled bundle and from a run's report of
# what it loaded, checked on rake compile's bundle, whose rpaths point into
# vendor/, or on Linux into tmp/, in this platform's format (NativeFormat).
class PackageCheckTest < Minitest::Test
  include TreeHelper

  BUNDLE = File.expand_path("../../lib/lota/native.#{RbConfig::CONFIG['DLEXT']}", __dir__)
  LINUX = RUBY_PLATFORM.include?("linux")
  MACHO = NativeFormat::MachO.new
  ELF = NativeFormat::ELF.new

  # On Linux, the libraries the bundle needs, and what they need in turn,
  # from the installdir rake dependencies builds.
  LIBRARIES = %w[
    libSDL3.so.0
    libfreetype.so.6
    libharfbuzz.so
    libopenal.so.1
    libmodplug.so.1
    libvorbisfile.so.3
    libz.so.1
    libvorbis.so.0
    libogg.so.0
].freeze

  # The libraries the bundle loads through @rpath.
  FRAMEWORKS = %w[
    SDL3.framework/Versions/A/SDL3
    freetype.framework/Versions/A/freetype
    harfbuzz.framework/Versions/A/harfbuzz
    OpenAL-Soft.framework/Versions/A/OpenAL-Soft
    libmodplug.framework/Versions/A/libmodplug
    vorbis.framework/Versions/A/vorbis
  ].freeze

  # A PackageCheck of one gem, tiny, whose gemspec in +dir+ has +homepage+
  # and ships one empty file.
  def check(dir, homepage: "https://example.com/tiny")
    write(dir, "tiny.gemspec", <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "tiny"
        spec.version = "0.1.0"
        spec.authors = ["Lota's tests"]
        spec.summary = "A gem for PackageCheck's tests."
        spec.license = "MIT"
        spec.homepage = #{homepage.inspect}
        spec.required_ruby_version = ">= 4.0"
        spec.files = ["lib/tiny.rb"]
      end
    RUBY
    write(dir, "lib/tiny.rb")
    git_stage(dir)
    tiny = PackageCheck::Target.new(name: "tiny", dir: ".", packaged: ["lib"], native_packaged: [], extension: "lib/tiny",
      native: nil, refusal: "", smoke: "", games: [])
    PackageCheck.new(root: dir, gems: [tiny], out: StringIO.new)
  end

  # Builds a gem named +name+ for +platform+ into +dir+ and returns its path.
  def package(dir, name, platform = Gem::Platform::RUBY)
    spec = Gem::Specification.new do |gem|
      gem.name = name
      gem.version = "0.1.0"
      gem.authors = ["Lota's tests"]
      gem.summary = "A gem for PackageCheck's tests."
      gem.license = "MIT"
      gem.homepage = "https://example.com/#{name}"
      gem.required_ruby_version = ">= 4.0"
      gem.files = []
      gem.platform = platform
    end
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Gem::Package.build(spec, true, false, File.join(dir, spec.file_name))
    end
  end

  if LINUX
    # SDL3 for the window and events, FreeType and HarfBuzz for text, OpenAL
    # Soft to play sound, libmodplug and libvorbisfile to decode it, and
    # zlib, each needed by its soname and found through the bundle's
    # rpath, and then libvorbis and libogg, which libvorbisfile's own rpath
    # finds.
    def test_the_extension_needs_its_libraries_and_theirs_through_their_rpaths
      assert_equal LIBRARIES.map { |name| "../../tmp/dependencies/installdir/lib/#{name}" }, ELF.dependencies(BUNDLE)
    end

    def test_each_dependency_is_a_library_that_exists
      ELF.dependencies(BUNDLE).each do |relative|
        assert File.file?(File.expand_path(relative, File.dirname(BUNDLE))), relative
      end
    end

    # From lib/, the libraries resolve into tmp/, outside the directory a
    # gem would be; from the repository root, they resolve inside, but for
    # an rpath a library built with its build directory in it, which the gem
    # build replaces.
    def test_a_library_that_resolves_outside_the_gem_escapes_it
      escapes = ELF.escapes(BUNDLE, File.join(ROOT, "lib"))

      LIBRARIES.each { |name| assert_includes escapes, "#{name} resolves outside #{File.join(ROOT, 'lib')}" }
      assert_empty ELF.escapes(BUNDLE, ROOT).grep_v(/\Arpath /)
    end

    def test_a_library_no_rpath_resolves_escapes_the_gem
      in_tree do |dir|
        FileUtils.cp(BUNDLE, dir)
        escapes = ELF.escapes(File.join(dir, File.basename(BUNDLE)), dir)

        assert_equal LIBRARIES.first(7).map { |name| "#{name} resolves outside #{dir}" }, escapes
      end
    end

    # glibc's libraries and GCC's C++ runtime come from the system, and
    # every other library from the gem.
    def test_only_glibc_and_the_cpp_runtime_are_the_systems
      %w[libc.so.6 libm.so.6 libmvec.so.1 libstdc++.so.6 libgcc_s.so.1 ld-linux-aarch64.so.1 ld-linux-x86-64.so.2].each do |name|
        assert_match NativeFormat::ELF::SYSTEM, name
      end
      %w[libSDL3.so.0 libz.so.1 libX11.so.6 libasan.so.6].each { |name| refute_match NativeFormat::ELF::SYSTEM, name }
    end
  else
    # SDL3 for the window and events, FreeType and HarfBuzz for text, OpenAL
    # Soft to play sound, and libmodplug and libvorbis to decode it, which
    # loads libogg in turn.
    def test_the_extension_needs_its_frameworks_and_theirs_beside_it_through_its_rpaths
      frameworks = "../../vendor/love-apple-dependencies/macOS/Frameworks"

      assert_equal [
        "../../vendor/love-apple-dependencies/shared/Frameworks/SDL3.xcframework/macos-arm64_x86_64/" \
          "SDL3.framework",
        "#{frameworks}/freetype.framework",
        "#{frameworks}/harfbuzz.framework",
        "#{frameworks}/OpenAL-Soft.framework",
        "#{frameworks}/libmodplug.framework",
        "#{frameworks}/vorbis.framework",
        "#{frameworks}/ogg.framework",
  ], MACHO.dependencies(BUNDLE)
    end

    def test_each_dependency_is_a_framework_directory_that_exists
      MACHO.dependencies(BUNDLE).each do |relative|
        assert File.directory?(File.expand_path(relative, File.dirname(BUNDLE))), relative
      end
    end

    # From lib/, the frameworks resolve into vendor/, outside the directory
    # a gem would be; from the repository root, they resolve inside.
    def test_a_library_that_resolves_outside_the_gem_escapes_it
      assert_equal FRAMEWORKS.map { |library| "@rpath/#{library} resolves outside #{File.join(ROOT, 'lib')}" },
        MACHO.escapes(BUNDLE, File.join(ROOT, "lib"))
      assert_empty MACHO.escapes(BUNDLE, ROOT)
    end

    def test_a_library_no_rpath_resolves_escapes_the_gem
      in_tree do |dir|
        FileUtils.cp(BUNDLE, dir)

        assert_equal FRAMEWORKS.map { |library| "@rpath/#{library} resolves outside #{dir}" },
          MACHO.escapes(File.join(dir, File.basename(BUNDLE)), dir)
      end
    end
  end

  def test_dyld_loaded_reads_what_dyld_print_libraries_reports
    output = "dyld[1]: <4E21E109-7AF9-3222-97EA-BFD99EAEEC19> /usr/bin/ruby\nwindow 800x600\n" \
      "dyld[1]: <B9EBCD53-332C-3CF1-A6F2-627AD367856C> /gems/SDL3.framework/Versions/A/SDL3\n"

    assert_equal ["/usr/bin/ruby", "/gems/SDL3.framework/Versions/A/SDL3"], MACHO.loaded(output)
  end

  def test_warnings_are_the_lines_rubygems_starts_with_warning
    output = "WARNING:  no homepage specified\nWARNING:  See https://guides.rubygems.org/ for help\n  " \
      "Successfully built RubyGem\n  Name: lota\n"

    assert_equal ["WARNING:  no homepage specified", "WARNING:  See https://guides.rubygems.org/ for help"],
      PackageCheck.warnings(output)
  end

  # gem build still builds a gemspec it warns about, so the check has to
  # stop on the warning itself.
  def test_a_warning_from_gem_build_fails_the_check
    in_tree do |dir|
      error = assert_raises(PackageCheck::Failure) { check(dir, homepage: nil).fast }

      assert_includes error.message, "gem build tiny.gemspec warned:\nWARNING:  no homepage specified"
    end
  end

  # The same gem with a homepage builds without a warning, so the check
  # goes on, and stops later: the source gem installs, having nothing to
  # compile.
  def test_a_gem_build_with_no_warning_passes_the_build
    in_tree do |dir|
      error = assert_raises(PackageCheck::Failure) { check(dir, homepage: "https://example.com/tiny").fast }

      assert_equal "tiny's source gem installed; it ships no LÖVE sources to build from", error.message
    end
  end

  def test_delivery_needs_a_precompiled_gem_for_each_gem
    in_tree do |dir|
      error = assert_raises(PackageCheck::Failure) { check(dir).deliver([]) }

      assert_equal "no precompiled gem given for tiny", error.message
    end
  end

  def test_delivery_refuses_the_source_gem
    in_tree do |dir|
      source = package(dir, "tiny")
      error = assert_raises(PackageCheck::Failure) { check(dir).deliver([source]) }

      assert_equal "tiny-0.1.0.gem is tiny's source gem; give its precompiled gem", error.message
    end
  end

  def test_delivery_refuses_a_gem_this_repository_does_not_publish
    in_tree do |dir|
      other = package(dir, "other", "arm64-darwin")
      error = assert_raises(PackageCheck::Failure) { check(dir).deliver([package(dir, "tiny", "arm64-darwin"), other]) }

      assert_equal "not gems this repository publishes:\n  #{other}", error.message
    end
  end

  def test_delivery_refuses_a_file_that_is_not_a_gem
    in_tree do |dir|
      junk = write(dir, "junk.gem", "junk")
      error = assert_raises(PackageCheck::Failure) { check(dir).deliver([junk]) }

      assert_equal "#{junk} is not a gem: package metadata is missing in #{junk}", error.message
    end
  end

  # Runs Ruby with the guard and returns what it printed but its report of
  # the libraries it loaded, and how it ended.
  def run_guarded(dir, *)
    guard = write(dir, "guard.rb", PackageCheck.guard(ROOT))
    output, status = Open3.capture2e(PackageCheck::UNBUNDLED, RbConfig.ruby, "-r", guard, *, chdir: dir)
    [NativeFormat.host.printed(output), status]
  end

  if LINUX
    # On Linux, where nothing like DYLD_PRINT_LIBRARIES reports what a run
    # loaded, the guard reports each shared object the run mapped.
    def test_on_linux_the_guard_reports_the_libraries_the_run_mapped
      in_tree do |dir|
        guard = write(dir, "guard.rb", PackageCheck.guard(ROOT, format: ELF))
        output, status = Open3.capture2e(PackageCheck::UNBUNDLED, RbConfig.ruby, "-r", guard, "-e", "require 'zlib'",
          chdir: dir)

        assert_predicate status, :success?, output
        assert ELF.loaded(output).any? { |path| path.end_with?("/zlib.so") }, output
      end
    end
  end

  def test_the_guard_fails_a_run_that_loads_from_the_repositorys_lib
    in_tree do |dir|
      output, status = run_guarded(dir, "-I", File.join(ROOT, "lib"), "-e", 'require "lota/version"')

      refute_predicate status, :success?
      assert_includes output, "lota-package-check: lota loaded from nowhere\n"
      assert_includes output, "loaded files from the repository's lib/: #{File.join(ROOT, 'lib/lota/version.rb')}"
    end
  end

  def test_the_guard_reports_where_lota_loaded_from
    in_tree do |dir|
      lota = write(dir, "gem/lib/lota.rb")
      output, status = run_guarded(dir, "-I", File.dirname(lota), "-e", 'require "lota"')

      assert_predicate status, :success?, output
      assert_equal "lota-package-check: lota loaded from #{lota}\n", output
    end
  end

  def dyld(*paths)
    paths.map { |path| "dyld[1]: <4E21E109-7AF9-3222-97EA-BFD99EAEEC19> #{path}\n" }.join
  end

  def test_nothing_is_outside_when_lota_its_bundle_and_frameworks_load_from_the_gem_home
    in_tree do |home|
      gem = "#{home}/gems/lota-0.0.0-arm64-darwin/lib"
      output = dyld("/usr/lib/libSystem.B.dylib", "/System/Library/Frameworks/Metal.framework/Versions/A/Metal",
        "#{gem}/lota/native.bundle", "#{gem}/lota/frameworks/SDL3.framework/Versions/A/SDL3") +
        "lota-package-check: lota loaded from #{gem}/lota.rb\n"

      assert_empty PackageCheck.outside(output, home, format: MACHO)
    end
  end

  def test_lota_its_bundle_or_a_framework_from_anywhere_else_is_outside
    in_tree do |home|
      output = dyld("#{ROOT}/lib/lota/native.bundle", "/vendor/SDL3.framework/Versions/A/SDL3") +
        "lota-package-check: lota loaded from #{ROOT}/lib/lota.rb\n"

      assert_equal [
        "Lota from #{ROOT}/lib/lota.rb",
        "/vendor/SDL3.framework/Versions/A/SDL3",
        "#{ROOT}/lib/lota/native.bundle",
], PackageCheck.outside(output, home, format: MACHO)
    end
  end

  def test_a_run_the_guard_and_dyld_say_nothing_about_is_outside
    in_tree do |home|
      assert_equal ["Lota from nowhere the guard reported", "no library of LÖVE's at all", "no lota/native bundle at all"],
        PackageCheck.outside("", home, format: MACHO)
    end
  end

  def mapped(*paths)
    paths.map { |path| "lota-package-check: mapped #{path}\n" }.join
  end

  # On Linux the system's libraries, and Ruby's own, may load from where
  # they are; every other library must load from the installed gem.
  def test_on_linux_nothing_is_outside_when_every_library_but_the_systems_and_rubys_loads_from_the_gem_home
    in_tree do |home|
      gem = "#{home}/gems/lota-0.0.0-aarch64-linux-gnu/lib"
      output = mapped("/usr/lib/aarch64-linux-gnu/libc.so.6", "/lib/aarch64-linux-gnu/libz.so.1.2.11",
        File.join(RbConfig::CONFIG["rubyarchdir"], "monitor.so"), "#{gem}/lota/native.so",
        "#{gem}/lota/libraries/libSDL3.so.0") + "lota-package-check: lota loaded from #{gem}/lota.rb\n"

      assert_empty PackageCheck.outside(output, home, format: ELF)
    end
  end

  def test_on_linux_a_library_from_anywhere_else_is_outside
    in_tree do |home|
      output = mapped("#{ROOT}/lib/lota/native.so", "#{ROOT}/tmp/dependencies/installdir/lib/libSDL3.so.0.4.10") +
        "lota-package-check: lota loaded from #{ROOT}/lib/lota.rb\n"

      assert_equal [
        "Lota from #{ROOT}/lib/lota.rb",
        "#{ROOT}/tmp/dependencies/installdir/lib/libSDL3.so.0.4.10",
        "#{ROOT}/lib/lota/native.so",
], PackageCheck.outside(output, home, format: ELF)
    end
  end

  def test_a_tool_that_fails_or_is_missing_raises
    error = assert_raises(NativeFormat::Failure) { NativeFormat.run!("ruby", "-e", "abort 'no'") }
    assert_includes error.message, "ruby -e abort 'no' failed:\nno"

    error = assert_raises(NativeFormat::Failure) { NativeFormat.run!("lota-no-such-tool") }
    assert_includes error.message, "lota-no-such-tool is not installed"
  end
end
