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
  NOTICES = { "NOTICES/love.txt" => "vendor/love/license.txt", "NOTICES/rice.txt" => "COPYING.rice" }.freeze
  FRAMEWORK_NOTICES = { "SDL3.framework" => "Versions/A/Resources/License.txt" }.freeze

  # The rice notice comes from the rice gem; the test gives it a stand-in
  # inside the repository, which NativeGem copies as it would the real one.
  def self.native_gem(work, framework_notices: FRAMEWORK_NOTICES)
    rice = File.join(work, "COPYING.rice")
    File.write(rice, "Rice's license\n")
    NativeGem.new(root: ROOT, gemspec: "lota.gemspec", bundle: BUNDLE,
      notices: NOTICES.merge("NOTICES/rice.txt" => rice), framework_notices:)
  end

  # The built gem's specification and the directory it unpacked to.
  def self.built
    @built ||= begin
      work = File.realpath(Dir.mktmpdir("lota-native-gem-test"))
      Minitest.after_run { FileUtils.rm_rf(work) }
      package = Gem::Package.new(native_gem(work).build(work))
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

  def test_it_ships_the_source_gems_files_with_the_bundle_frameworks_and_notices
    source = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).files

    assert_empty source - spec.files
    assert_includes spec.files, BUNDLE
    assert_includes spec.files, "#{SDL3}/SDL3"
    assert_includes spec.files, "#{SDL3}/_CodeSignature/CodeResources"
    assert_includes spec.files, "#{SDL3}/Resources/Info.plist"
    assert_equal %w[NOTICES/SDL3.txt NOTICES/love.txt NOTICES/rice.txt], spec.files.grep(%r{\ANOTICES/}).sort
  end

  def test_notices_are_copies_of_their_sources
    assert_equal File.read(File.join(ROOT, "vendor/love/license.txt")), File.read(File.join(unpacked, "NOTICES/love.txt"))
    assert_equal "Rice's license\n", File.read(File.join(unpacked, "NOTICES/rice.txt"))
    assert_equal File.read(File.join(unpacked, SDL3, "Resources/License.txt")),
      File.read(File.join(unpacked, "NOTICES/SDL3.txt"))
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
    assert_equal ["frameworks/SDL3.framework"], PackageCheck.rpath_dependencies(bundle)
  end

  def test_every_signature_verifies_strictly_once_unpacked
    [BUNDLE, SDL3].each do |path|
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
      native = NativeGem.new(root: ROOT, gemspec: relative, bundle: BUNDLE, notices: NOTICES.merge(
        "NOTICES/rice.txt" => write(work, "COPYING.rice", "Rice's license\n")
      ), framework_notices: FRAMEWORK_NOTICES)
      error = assert_raises(PackageCheck::Failure) { native.build(work) }

      assert_includes error.message, "arm64-darwin.gem built with warnings:\nWARNING:  no homepage specified"
    end
  end

  def test_a_framework_without_a_notice_stops_the_build
    in_tree do |work|
      error = assert_raises(PackageCheck::Failure) { self.class.native_gem(work, framework_notices: {}).build(work) }

      assert_includes error.message, "SDL3.framework has no license notice"
    end
  end
end
