# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/native_gem"
require "rubygems/package"

# NativeGem builds the precompiled gem from rake compile's bundle and the
# frameworks it loads. Building takes a few seconds, so the gem is built
# once and every test reads it.
class NativeGemTest < Minitest::Test
  include TreeHelper

  BUNDLE = "lib/lota/native.#{RbConfig::CONFIG['DLEXT']}".freeze
  SDL3 = "lib/lota/frameworks/SDL3.framework/Versions/A"
  FRAMEWORKS = %w[
    SDL3.framework
    freetype.framework
    harfbuzz.framework
    libmodplug.framework
    vorbis.framework
    ogg.framework
].freeze

  # The repository's own record, read afresh, so a test may take an entry
  # out of it.
  def self.licensing
    Licensing.load(File.join(ROOT, "ext/lota/licenses.rb"))
  end

  # A NativeGem of rake compile's bundle, as rake package:native builds it.
  def self.native_gem(gemspec: "lota.gemspec", licensing: self.licensing)
    NativeGem.new(root: ROOT, gemspec:, bundle: BUNDLE, build: "tmp/engine/build", licensing:,
      licenses: %w[LICENSES ext/lota/licenses])
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

  def test_it_is_a_platform_gem_for_apple_silicon_and_this_rubys_minor_version
    assert_equal Gem::Platform.new("arm64-darwin"), spec.platform
    assert_equal "lota-#{spec.version}-arm64-darwin.gem", spec.file_name
    assert_equal Gem::Requirement.new(">= 4.0.1", "< 4.1.dev"), spec.required_ruby_version
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
    FRAMEWORKS.each { |name| assert_includes spec.files, "lib/lota/frameworks/#{name}/Versions/A/Resources/Info.plist" }
    assert_includes spec.files, "#{SDL3}/SDL3"
    assert_includes spec.files, "#{SDL3}/_CodeSignature/CodeResources"
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
  # repository's CC0-1.0 or MIT-0, which only files the gem leaves out use.
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
    refute_includes licenses, "CC0-1.0"
    assert_equal File.read(File.join(ROOT, "ext/lota/licenses/LICENSE-FTL.txt")),
      File.read(File.join(unpacked, "LICENSES/FTL.txt"))
    assert_equal File.read(File.join(ROOT, "LICENSES/Zlib.txt")), File.read(File.join(unpacked, "LICENSES/Zlib.txt"))
  end

  # The gem's REUSE.toml is the repository's, then the record's
  # annotations: the bundle's, with the works the linker put in it, and
  # each framework's. Wuff, whose licensing the maintainer has yet to find
  # out, is the one work it names without a license.
  def test_the_reuse_toml_annotates_the_bundle_and_each_framework
    toml = File.read(File.join(unpacked, "REUSE.toml"))

    assert toml.start_with?(File.read(File.join(ROOT, "REUSE.toml")))
    assert_includes toml, %(path = "#{BUNDLE}")
    FRAMEWORKS.each { |name| assert_includes toml, %(path = "lib/lota/frameworks/#{name}/**") }
    assert_includes toml, %("2005-2021 Lode Vandevenne")
    assert_includes toml, %("2006-2026 LOVE Development Team")
    assert_includes toml, %("OFL-1.1")
    assert_includes toml, %("GPL-3.0-or-later WITH Bison-exception-2.2")
    assert_includes toml, %("Unlicense OR MIT-0")
    pending = toml.lines.grep(/\A#   /).map(&:chomp)
    assert_equal ["#   Wuff: no license or notice of copyright in its files, and none in LÖVE's license.txt"], pending
  end

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
    rpaths = PackageCheck.otool("-l", bundle).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten

    assert_equal ["@loader_path/frameworks"], rpaths
    assert_equal FRAMEWORKS.map { |name| "frameworks/#{name}" }, PackageCheck.rpath_dependencies(bundle)
  end

  def test_every_signature_verifies_strictly_once_unpacked
    [BUNDLE, *FRAMEWORKS.map { |name| "lib/lota/frameworks/#{name}/Versions/A" }].each do |path|
      output, status = codesign_verify(File.join(unpacked, path))

      assert status.success?, output
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

      assert_includes error.message, "arm64-darwin.gem built with warnings:\nWARNING:  no homepage specified"
    end
  end

  def test_a_framework_the_record_lacks_stops_the_build
    licensing = self.class.licensing
    licensing.frameworks.delete("freetype.framework")
    in_tree do |work|
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(licensing:).build(work) }

      assert_includes error.message, "freetype.framework has no recorded license"
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
