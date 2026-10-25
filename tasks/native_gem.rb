# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require "stringio"
require_relative "package_check"

# Builds Lota's precompiled gem for Apple Silicon macOS.
#
# The source gem cannot build Lota's extension once installed: the build
# needs LÖVE's sources and love-apple-dependencies' frameworks, which live
# in vendor/ and do not ship. So Lota ships what rake compile built, as
# rake-compiler's native gems do: the gem's platform is arm64-darwin, it
# has no extension to compile, and the compiled bundle sits where
# require "lota/native" finds it. gem install copies files and builds
# nothing, so it needs neither Rice nor CMake.
#
# The bundle loads LÖVE's frameworks through @rpath, and rake compile's
# bundle points its rpaths into vendor/. The gem carries each framework
# the bundle loads, in lib/lota/frameworks, and the bundle's rpaths are
# replaced by one into that directory (@loader_path/frameworks). Each
# framework ships as the one version directory its install name names
# (Versions/A), without the symlinks around it, on which RubyGems warns,
# without its headers, and with only its arm64 code.
#
# Changing a Mach-O file invalidates its code signature, and SDL3's
# signature in love-apple-dependencies seals a file its checkout lacks
# (LICENSE.txt, checked out as License.txt), so the bundle and every
# framework are signed again ad hoc, as love-apple-dependencies signs
# them, and verified with codesign --verify --strict.
#
# The gem also carries the license notices of what it ships compiled
# (NOTICES): LÖVE's license.txt for the engine and the libraries LÖVE
# bundles, Rice's for the headers the bundle compiled in, and each
# framework's own. A framework with no notice stops the build.
class NativeGem
  # The platform the bundle is built for.
  PLATFORM = "arm64-darwin"

  # Where the frameworks go in the gem, relative to the bundle.
  FRAMEWORKS = "frameworks"

  # The framework version directory a @rpath install name names.
  VERSION = PackageCheck::FRAMEWORK_VERSION

  # Development files in a framework's version directory.
  DEVELOPMENT = %w[Headers Resources/CMake].freeze

  # [root] The repository root.
  # [gemspec] The source gem's gemspec, relative to +root+.
  # [bundle] rake compile's bundle, relative to +root+; it ships at the
  #   same path.
  # [notices] Each notice's path in the gem, to the file it copies
  #   (relative to +root+, or absolute).
  # [framework_notices] Each framework's name, to its license notice
  #   inside it, which ships as NOTICES/<name>.txt.
  def initialize(root:, gemspec:, bundle:, notices:, framework_notices:)
    @root = root
    @gemspec = gemspec
    @bundle = bundle
    @notices = notices
    @framework_notices = framework_notices
  end

  # Builds the gem in a staging directory under +work+ and returns the
  # path of the .gem file, also under +work+.
  def build(work)
    frameworks = framework_sources
    stage = File.join(work, "stage")
    FileUtils.rm_rf(stage)
    spec = source_spec
    files = spec.files.each { |file| copy(File.join(@root, file), File.join(stage, file)) }
    files += stage_bundle(stage)
    files += frameworks.flat_map { |name, source| stage_framework(stage, name, source) }
    files += stage_notices(stage, frameworks)
    package(native_spec(spec, files), stage, work)
  end

  # The Ruby requirement: the source gem's, below the next minor version
  # of the Ruby whose ABI the bundle was compiled for (this one), as
  # rake-compiler bounds its native gems.
  def self.required_ruby_version(source)
    major, minor = RbConfig::CONFIG.values_at("MAJOR", "MINOR").map(&:to_i)
    Gem::Requirement.new(*source.requirements.map { |op, version| "#{op} #{version}" }, "< #{major}.#{minor + 1}.dev")
  end

  # Each framework the bundle loads, by name, with its directory in the
  # repository. Fails on one without a notice.
  private def framework_sources
    bundle = File.join(@root, @bundle)
    PackageCheck.rpath_dependencies(bundle).to_h do |relative|
      name = File.basename(relative)
      raise PackageCheck::Failure, "#{name} has no license notice; add one to the native gem's notices" unless
        @framework_notices.key?(name)

      [name, File.expand_path(relative, File.dirname(bundle))]
    end
  end

  private def source_spec
    Gem::Specification.load(File.join(@root, @gemspec)) or raise PackageCheck::Failure, "#{@gemspec} does not load"
  end

  private def stage_bundle(stage)
    bundle = File.join(stage, @bundle)
    copy(File.join(@root, @bundle), bundle)
    rpaths = PackageCheck.otool("-l", bundle).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten
    run!("install_name_tool", *rpaths.flat_map { |rpath| ["-delete_rpath", rpath] }, "-add_rpath",
      "@loader_path/#{FRAMEWORKS}", bundle)
    sign(bundle)
    [@bundle]
  end

  private def stage_framework(stage, name, source)
    relative = File.join(File.dirname(@bundle), FRAMEWORKS, name, VERSION)
    target = File.join(stage, relative)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp_r(File.join(source, VERSION), target)
    DEVELOPMENT.each { |path| FileUtils.rm_rf(File.join(target, path)) }
    binary = File.join(target, File.basename(name, ".framework"))
    run!("lipo", binary, "-thin", "arm64", "-output", binary) if run!("lipo", "-archs", binary).split.size > 1
    sign(target)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: target).filter_map do |path|
      raise PackageCheck::Failure, "#{name} holds a symlink, #{path}" if File.symlink?(File.join(target, path))

      File.join(relative, path) if File.file?(File.join(target, path))
    end
  end

  private def stage_notices(stage, frameworks)
    notices = @notices.to_h { |path, source| [path, File.expand_path(source, @root)] }
    frameworks.each do |name, source|
      notices["NOTICES/#{File.basename(name, '.framework')}.txt"] = File.join(source, @framework_notices.fetch(name))
    end
    notices.each { |path, source| copy(source, File.join(stage, path)) }
    notices.keys
  end

  private def native_spec(source, files)
    source.dup.tap do |spec|
      spec.platform = Gem::Platform.new(PLATFORM)
      spec.required_ruby_version = self.class.required_ruby_version(source.required_ruby_version)
      spec.extensions = []
      spec.files = files
    end
  end

  # Builds the package as gem build does, keeping what RubyGems prints for
  # a failure, as PackageCheck keeps gem build's output, and failing on a
  # warning, as PackageCheck fails on gem build's.
  private def package(spec, stage, work)
    output = File.join(work, spec.file_name)
    messages = StringIO.new
    Gem::DefaultUserInteraction.use_ui(Gem::StreamUI.new(StringIO.new, messages, messages, false)) do
      Dir.chdir(stage) { Gem::Package.build(spec, false, false, output) }
    end
    warnings = PackageCheck.warnings(messages.string)
    raise PackageCheck::Failure, "#{spec.file_name} built with warnings:\n#{warnings.join("\n")}" if warnings.any?

    output
  rescue Gem::InvalidSpecificationException, Gem::Package::Error => e
    raise PackageCheck::Failure, "#{spec.file_name} did not build: #{e.message}\n#{messages.string}"
  end

  # Signs +path+ ad hoc, replacing any signature, and verifies it as
  # Gatekeeper would.
  private def sign(path)
    run!("codesign", "--force", "--sign", "-", path)
    run!("codesign", "--verify", "--strict", "--verbose=2", path)
  end

  private def copy(source, target)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(source, target, preserve: true)
  end

  private def run!(*command)
    output, status = Open3.capture2e(*command)
    raise PackageCheck::Failure, "#{command.join(' ')} failed:\n#{output}" unless status.success?

    output
  end
end
