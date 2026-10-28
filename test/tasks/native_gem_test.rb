# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/native_gem"
require "digest"
require "stringio"
require "rubygems/package"

# NativeGem builds the precompiled gem from rake compile's bundle and the
# frameworks it loads. Building takes a few seconds, so the gem is built
# once and every test reads it.
class NativeGemTest < Minitest::Test
  include TreeHelper

  BUNDLE = "lib/lota/native.#{RbConfig::CONFIG['DLEXT']}".freeze

  # The platform the gem is built on, which it is built for.
  LINUX = RUBY_PLATFORM.include?("linux")
  FORMAT = NativeFormat.host

  SDL3 = "lib/lota/frameworks/SDL3.framework/Versions/A"
  FRAMEWORKS = %w[
    SDL3.framework
    freetype.framework
    harfbuzz.framework
    OpenAL-Soft.framework
    libmodplug.framework
    vorbis.framework
    ogg.framework
].freeze

  # On Linux, the libraries the bundle needs, then what they need: SDL3
  # for the window and events, FreeType and HarfBuzz for text, OpenAL Soft
  # to play sound, libmodplug and libvorbisfile to decode it, and zlib,
  # then libvorbis and libogg, which libvorbisfile needs.
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

  # What the gem carries the bundle's dependencies as, and OpenAL Soft's
  # and FreeType's names among them.
  CARRIED = LINUX ? LIBRARIES : FRAMEWORKS
  OPENAL = LINUX ? "libopenal.so.1" : "OpenAL-Soft.framework"
  FREETYPE = LINUX ? "libfreetype.so.6" : "freetype.framework"
  DIRECTORY = "lib/lota/#{FORMAT.directory}".freeze

  # The repository's own record, read afresh, so a test may take an entry
  # out of it.
  def self.licensing
    Licensing.load(File.join(ROOT, "ext/lota/licenses.rb"))
  end

  # A NativeGem of rake compile's bundle, as rake package:native builds it.
  def self.native_gem(gemspec: "lota.gemspec", licensing: self.licensing)
    NativeGem.new(root: ROOT, gemspec:, bundle: BUNDLE, build: "tmp/engine/build", licensing:,
      licenses: %w[LICENSES ext/lota/licenses],
      dependencies: LINUX ? "tmp/dependencies/installdir" : "vendor/love-apple-dependencies")
  end

  # The built gem's specification and the directory it unpacked to.
  def self.built
    @built ||= begin
      work = File.realpath(Dir.mktmpdir("lota-native-gem-test"))
      Minitest.after_run { FileUtils.rm_rf(work) }
      package = Gem::Package.new(native_gem.build(work))
      unpacked = File.join(work, "unpacked")
      package.extract_files(unpacked)
      [package.spec, unpacked]
    end
  end

  def spec = self.class.built.first
  def unpacked = self.class.built.last

  def codesign_verify(path)
    Open3.capture2e("codesign", "--verify", "--strict", "--verbose=2", path)
  end

  # Apple Silicon on macOS; on Linux, this machine's processor with glibc,
  # which RubyGems does not match on musl.
  def test_it_is_a_platform_gem_for_this_machine_and_this_rubys_minor_version
    platform = LINUX ? "#{RbConfig::CONFIG['host_cpu']}-linux-gnu" : "arm64-darwin"

    assert_equal Gem::Platform.new(platform), spec.platform
    assert_equal "lota-#{spec.version}-#{platform}.gem", spec.file_name
    assert_equal Gem::Requirement.new(">= 4.0.1", "< 4.1.dev"), spec.required_ruby_version
    assert spec.platform =~ Gem::Platform.local
    refute spec.platform =~ Gem::Platform.new("#{RbConfig::CONFIG['host_cpu']}-linux-musl") if LINUX
  end

  # gem install compiles nothing, and so needs neither Rice nor CMake.
  def test_it_has_no_extension_to_compile_and_no_runtime_dependency
    assert_empty spec.extensions
    assert_empty spec.runtime_dependencies
  end

  def test_it_ships_the_source_gems_files_with_the_bundle_frameworks_and_licensing
    source = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).files

    assert_empty source.grep_v(%r{\ALICENSES/}) - spec.files
    assert_includes spec.files, BUNDLE
    assert_includes spec.files, "REUSE.toml"
    if LINUX
      assert_equal LIBRARIES.map { |name| "#{DIRECTORY}/#{name}" }.sort, spec.files.grep(%r{\A#{DIRECTORY}/}).sort
    else
      FRAMEWORKS.each { |name| assert_includes spec.files, "lib/lota/frameworks/#{name}/Versions/A/Resources/Info.plist" }
      assert_includes spec.files, "#{SDL3}/SDL3"
      assert_includes spec.files, "#{SDL3}/_CodeSignature/CodeResources"
    end
    assert_empty spec.files.grep(%r{\ANOTICES/})
  end

  # The REUSE tool, run on the unpacked gem, finds every file's copyright
  # and license, and a text for each license and no other.
  def test_the_gem_is_reuse_compliant
    output, status = Open3.capture2e("reuse", "--root", unpacked, "lint")

    assert status.success?, output
  end

  # LICENSES holds what the gem's files use: the licenses of the
  # frameworks and bundled libraries, from ext/lota/licenses, but not the
  # repository's CC0-1.0, which on macOS only files the gem leaves out use;
  # on Linux, SDL's dlmalloc is under it too. Each platform's libraries
  # bring their own: libm's SunPro and bzip2's on Linux, and on macOS the
  # Unicode license HarfBuzz 6.0.0's data was under.
  def test_the_gem_ships_the_license_texts_its_files_use_and_no_other
    licenses = spec.files.grep(%r{\ALICENSES/}).map { |path| File.basename(path, ".txt") }

    assert_includes licenses, "FTL"
    assert_includes licenses, "MIT-Modern-Variant"
    assert_includes licenses, "Bison-exception-2.2"
    assert_includes licenses, "LicenseRef-NVIDIA-Software-2002"
    assert_includes licenses, "LicenseRef-LZMA-SDK-Public-Domain"
    assert_includes licenses, "Unlicense"
    assert_includes licenses, "AGPL-3.0-or-later"
    assert_includes licenses, "MIT-0"
    assert_includes licenses, "LicenseRef-libmodplug-Public-Domain"
    %w[TU-Berlin-1.0 MIT-open-group ISC LicenseRef-libmodplug-MikMod].each { |id| assert_includes licenses, id }
    if LINUX
      %w[CC0-1.0 SunPro HPND-sell-variant bzip2-1.0.6 Unicode-3.0].each { |id| assert_includes licenses, id }
    else
      assert_includes licenses, "Unicode-DFS-2016"
      %w[CC0-1.0 SunPro bzip2-1.0.6].each { |id| refute_includes licenses, id }
    end
    assert_equal File.read(File.join(ROOT, "ext/lota/licenses/LICENSE-FTL.txt")),
      File.read(File.join(unpacked, "LICENSES/FTL.txt"))
    assert_equal File.read(File.join(ROOT, "LICENSES/Zlib.txt")), File.read(File.join(unpacked, "LICENSES/Zlib.txt"))
  end

  # The gem's REUSE.toml is the repository's, then the record's
  # annotations: the bundle's, with the works the linker put in it, each
  # framework's, and OpenAL Soft's source archive's. Every work the bundle
  # carries has its license recorded, so none is pending.
  def test_the_reuse_toml_annotates_the_bundle_and_each_framework
    toml = File.read(File.join(unpacked, "REUSE.toml"))

    assert toml.start_with?(File.read(File.join(ROOT, "REUSE.toml")))
    assert_includes toml, %(path = "#{BUNDLE}")
    CARRIED.each { |name| assert_includes toml, %(path = "#{FORMAT.annotation("#{DIRECTORY}/#{name}")}") }
    assert_includes toml, %("2005-2021 Lode Vandevenne")
    assert_includes toml, %("2006-2026 LOVE Development Team")
    assert_includes toml, %("OFL-1.1")
    assert_includes toml, %("GPL-3.0-or-later WITH Bison-exception-2.2")
    assert_includes toml, %("Unlicense OR MIT-0")
    assert_includes toml, %(path = "sources/openal-soft-1.24.3.tar.bz2")
    assert_includes toml, %("2012-2013 Boolsheet")
    assert_empty toml.lines.grep(/\A#   /)
  end

  # OpenAL Soft's license, the GNU Library General Public License, asks
  # for the library's source with its object code (section 4), so the gem
  # carries the release's archive, the one the record names by its
  # SHA-256, and the licenses of everything in it.
  def test_the_gem_carries_openal_softs_source_with_its_framework
    archive = File.join(unpacked, "sources/openal-soft-1.24.3.tar.bz2")
    licenses = spec.files.grep(%r{\ALICENSES/}).map { |path| File.basename(path, ".txt") }

    assert_includes spec.files,
      LINUX ? "#{DIRECTORY}/libopenal.so.1" : "lib/lota/frameworks/OpenAL-Soft.framework/Versions/A/OpenAL-Soft"
    assert_equal "cb5e6197a1c0da0edcf2a81024953cc8fa8545c3b9474e48c852af709d587892",
      Digest::SHA256.file(archive).hexdigest
    %w[LGPL-2.0-or-later GPL-2.0-or-later Python-2.0 LicenseRef-PFFFT].each { |id| assert_includes licenses, id }
  end

  # The package check finds OpenAL Soft's framework, its annotation, and
  # its source archive in the gem, and fails a gem whose archive is gone
  # or is another.
  def test_the_package_check_verifies_the_source_archive_the_gem_carries
    target = PackageCheck::Target.new(name: "lota", dir: ".", packaged: [], native_packaged: [],
      extension: "lib/lota/native", native: self.class.native_gem, refusal: "", smoke: "", games: [])
    out = StringIO.new
    check = PackageCheck.new(root: ROOT, gems: [target], out:)
    check.__send__(:verify_sources, target, unpacked)
    assert_includes out.string, "carries its source sources/openal-soft-1.24.3.tar.bz2"

    in_tree do |work|
      copy = File.join(work, "gem")
      FileUtils.cp_r(unpacked, copy)
      File.write(File.join(copy, "sources/openal-soft-1.24.3.tar.bz2"), "another")
      error = assert_raises(PackageCheck::Failure) { check.__send__(:verify_sources, target, copy) }
      assert_includes error.message, "whose SHA-256 is not the cb5e6197"

      File.delete(File.join(copy, "sources/openal-soft-1.24.3.tar.bz2"))
      error = assert_raises(PackageCheck::Failure) { check.__send__(:verify_sources, target, copy) }
      assert_includes error.message, "lacks sources/openal-soft-1.24.3.tar.bz2"
    end
  end

  # The build checks the archive it copies, so one that is not the
  # release recorded, or none at all, stops it.
  def test_a_source_archive_that_is_missing_or_not_the_one_recorded_stops_the_build
    licensing = self.class.licensing
    recorded = licensing.frameworks.fetch(OPENAL)
    in_tree do |work|
      wrong = File.join(work, "openal.tar.bz2")
      File.write(wrong, "not the release")
      relative = Pathname.new(wrong).relative_path_from(ROOT).to_s
      licensing.frameworks[OPENAL] = recorded.with(source: recorded.source.with(path: relative))
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(licensing:).build(work) }
      assert_includes error.message, "#{relative} has SHA-256 #{Digest::SHA256.file(wrong).hexdigest}"

      File.delete(wrong)
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(licensing:).build(work) }
      assert_includes error.message, "#{relative} is missing; run bundle exec rake sources:fetch"
    end
  end

  if LINUX
    # RubyGems warns on every symlink it packages, so each library ships as
    # a file named for the soname it is needed by, with its own rpath at
    # its directory, where the others are, and, as LÖVE's AppImage ships
    # them, without its debugging information.
    def test_each_library_ships_as_a_file_pointing_at_the_others_without_debugging_information
      LIBRARIES.each do |name|
        library = File.join(unpacked, DIRECTORY, name)

        refute File.symlink?(library), name
        assert_equal ["$ORIGIN"], FORMAT.runpath(library), name
        refute_includes run!(unpacked, "readelf", "--section-headers", library), ".debug_info", name
      end
    end

    def test_the_bundle_loads_its_libraries_from_inside_the_gem
      bundle = File.join(unpacked, BUNDLE)

      assert_equal ["$ORIGIN/libraries"], FORMAT.runpath(bundle)
      assert_equal LIBRARIES.map { |name| "libraries/#{name}" }, FORMAT.dependencies(bundle)
      assert_empty FORMAT.escapes(bundle, unpacked)
    end
  else
    # RubyGems warns on every symlink it packages, so the framework ships
    # as the one version directory its install name names, with no headers.
    def test_the_framework_ships_without_symlinks_headers_or_intel_code
      framework = File.join(unpacked, "lib/lota/frameworks/SDL3.framework")

      assert_empty Dir.glob("**/*", File::FNM_DOTMATCH, base: framework).select { |path|
        File.symlink?(File.join(framework, path))
      }
      assert_empty spec.files.grep(%r{\Alib/lota/frameworks/.*(Headers|CMake)})
      assert_equal "arm64\n", run!(unpacked, "lipo", "-archs", "#{SDL3}/SDL3")
    end

    def test_the_bundle_loads_its_frameworks_from_inside_the_gem
      bundle = File.join(unpacked, BUNDLE)
      rpaths = FORMAT.otool("-l", bundle).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten

      assert_equal ["@loader_path/frameworks"], rpaths
      assert_equal FRAMEWORKS.map { |name| "frameworks/#{name}" }, FORMAT.dependencies(bundle)
    end

    def test_every_signature_verifies_strictly_once_unpacked
      [BUNDLE, *FRAMEWORKS.map { |name| "lib/lota/frameworks/#{name}/Versions/A" }].each do |path|
        output, status = codesign_verify(File.join(unpacked, path))

        assert status.success?, output
      end
    end
  end

  # Gem::Package.build builds a gemspec it warns about, so the build has
  # to stop on the warning itself. The gemspec is Lota's without its
  # homepage.
  def test_a_warning_stops_the_build
    in_tree do |work|
      gemspec = write(work, "warned.gemspec", <<~RUBY)
        Gem::Specification.load(#{File.join(ROOT, 'lota.gemspec').inspect}).dup.tap { |spec| spec.homepage = nil }
      RUBY
      relative = Pathname.new(gemspec).relative_path_from(ROOT).to_s
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(gemspec: relative).build(work) }

      assert_includes error.message, "#{FORMAT.platform}.gem built with warnings:\nWARNING:  no homepage specified"
    end
  end

  def test_a_framework_the_record_lacks_stops_the_build
    licensing = self.class.licensing
    licensing.frameworks.delete(FREETYPE)
    in_tree do |work|
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(licensing:).build(work) }

      assert_includes error.message, "#{FREETYPE} has no recorded license"
    end
  end

  # LodePNG is compiled into the bundle, so a record without it names its
  # files.
  def test_a_bundled_library_the_record_lacks_stops_the_build
    licensing = self.class.licensing
    licensing.works.reject! { |work| work.name == "LodePNG" }
    in_tree do |work|
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(licensing:).build(work) }

      assert_includes error.message, "the bundle compiles files no entry in"
      assert_includes error.message, File.join(ROOT, "vendor/love/src/libraries/lodepng/lodepng.h")
    end
  end
end
