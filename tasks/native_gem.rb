# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "stringio"
require_relative "licensing"
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
# The gem is a REUSE project (REUSE Specification 3.3), as the
# repository is: its REUSE.toml is the repository's, with an annotation
# for the bundle and one for each framework, which Licensing writes from
# ext/lota/licenses.rb, and its LICENSES/ holds the text of every license
# those annotations and its other files use, and no other. A license only
# the gem uses has its text in ext/lota/licenses, since the repository
# alone would leave it unused. The bundle's annotation covers the works
# the linker put in it (LinkedFiles): Lota's own code, LÖVE's, Rice's
# headers, and each library LÖVE bundles that the bundle carries. A
# framework, or a file the bundle compiled, that the record lacks stops
# the build, and so does a gem the REUSE tool does not call compliant.
class NativeGem
  # The platform the bundle is built for.
  PLATFORM = "arm64-darwin"

  # Where the frameworks go in the gem, relative to the bundle.
  FRAMEWORKS = "frameworks"

  # The framework version directory a @rpath install name names.
  VERSION = PackageCheck::FRAMEWORK_VERSION

  # Development files in a framework's version directory.
  DEVELOPMENT = %w[Headers Resources/CMake].freeze

  # Where the gem's license texts go, as REUSE asks.
  LICENSES = "LICENSES"

  # What the gem's files are licensed under, as REUSE reads it.
  REUSE_TOML = "REUSE.toml"

  # [root] The repository root.
  # [gemspec] The source gem's gemspec, relative to +root+.
  # [bundle] rake compile's bundle, relative to +root+; it ships at the
  #   same path.
  # [build] The CMake build that linked the bundle, relative to +root+,
  #   where it is at the same path, with the linker's map beside it.
  # [licensing] The Licensing record of what the gem carries.
  # [licenses] Directories of license texts, relative to +root+: LICENSES
  #   and ext/lota/licenses, whose LICENSE-<identifier>.txt files the gem
  #   ships as LICENSES/<identifier>.txt.
  def initialize(root:, gemspec:, bundle:, build:, licensing:, licenses:)
    @root = root
    @gemspec = gemspec
    @bundle = bundle
    @build = build
    @licensing = licensing
    @licenses = licenses
  end

  # The paths the gem builds for itself rather than copying from the
  # source gem: its license texts, chosen by what its files use, so it
  # may leave out a text the repository ships.
  def assembled
    [LICENSES]
  end

  # Builds the gem in a staging directory under +work+ and returns the
  # path of the .gem file, also under +work+.
  def build(work)
    frameworks = framework_sources
    works = bundled_works
    stage = File.join(work, "stage")
    FileUtils.rm_rf(stage)
    spec = source_spec
    files = spec.files.reject { |file| file.start_with?("#{LICENSES}/") }
    files.each { |file| copy(File.join(@root, file), File.join(stage, file)) }
    files += stage_bundle(stage)
    files += frameworks.flat_map { |name, source| stage_framework(stage, name, source) }
    files += stage_licensing(stage, works, frameworks.keys)
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
  # repository. Fails on one the record lacks.
  private def framework_sources
    bundle = File.join(@root, @bundle)
    PackageCheck.rpath_dependencies(bundle).to_h do |relative|
      name = File.basename(relative)
      recorded { @licensing.framework_for(name) }
      [name, File.expand_path(relative, File.dirname(bundle))]
    end
  end

  # The works the bundle carries, from the linker's map of the bundle the
  # build linked, which must be the one rake compile copied. Fails on a
  # file the record lacks.
  private def bundled_works
    built = File.join(@root, @build, @bundle)
    unless File.file?(built) && FileUtils.compare_file(built, File.join(@root, @bundle))
      raise PackageCheck::Failure, "#{@bundle} is not #{File.join(@build, @bundle)}; run rake compile"
    end

    linked = LinkedFiles.read(map: built.sub(/\.[^.]+\z/, ".map"), build: File.join(@root, @build))
    recorded { @licensing.bundled(linked, root: @root, outside:) }
  rescue LinkedFiles::Failure => e
    raise PackageCheck::Failure, e.message
  end

  # What the bundle reads that is not code it carries, so the record need
  # not cover it: the toolchain's and the SDK's headers and runtime, Ruby's
  # headers, which every extension compiles against, and the frameworks'
  # headers, whose code ships in the frameworks the bundle loads, each
  # recorded on its own. The maintainer confirmed this scope.
  private def outside
    developer, status = Open3.capture2e("xcode-select", "--print-path")
    raise PackageCheck::Failure, "xcode-select --print-path failed:\n#{developer}" unless status.success?

    [developer.strip, RbConfig::CONFIG.fetch("rubyhdrdir"), File.join(@root, "vendor/love-apple-dependencies")]
      .map { |dir| File.join(dir, "") }
  end

  private def recorded
    yield
  rescue Licensing::Unrecorded => e
    raise PackageCheck::Failure, e.message
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

  # Writes the gem's REUSE.toml and LICENSES/, and checks the gem with
  # the REUSE tool. Every license text goes in first, and the ones no file
  # uses come out, so what remains is exactly what REUSE asks for.
  private def stage_licensing(stage, works, frameworks)
    annotations = @licensing.annotations(bundle: @bundle, works:, framework_dir:, frameworks:)
    File.write(File.join(stage, REUSE_TOML), "#{File.read(File.join(@root, REUSE_TOML))}\n#{annotations}")
    texts = license_texts
    texts.each { |identifier, source| copy(source, File.join(stage, LICENSES, "#{identifier}.txt")) }
    used = reuse_lint(stage).fetch("summary").fetch("used_licenses")
    (texts.keys - used).each { |identifier| File.delete(File.join(stage, LICENSES, "#{identifier}.txt")) }
    unless reuse_lint(stage).dig("summary", "compliant")
      raise PackageCheck::Failure, "the gem is not REUSE compliant:\n#{Open3.capture2e('reuse', '--root', stage, 'lint').first}"
    end

    [REUSE_TOML] + (texts.keys & used).sort.map { |identifier| "#{LICENSES}/#{identifier}.txt" }
  end

  # Each license text in +@licenses+, by its SPDX identifier.
  private def license_texts
    @licenses.each_with_object({}) do |dir, texts|
      Dir.glob("*.txt", base: File.join(@root, dir)).each do |name|
        texts[File.basename(name, ".txt").delete_prefix("LICENSE-")] = File.join(@root, dir, name)
      end
    end
  end

  private def framework_dir
    File.join(File.dirname(@bundle), FRAMEWORKS)
  end

  # The REUSE tool's report on the directory +dir+.
  private def reuse_lint(dir)
    output, = Open3.capture2("reuse", "--root", dir, "lint", "--json")
    JSON.parse(output)
  rescue JSON::ParserError, Errno::ENOENT => e
    raise PackageCheck::Failure, "reuse lint did not report on #{dir} (#{e.message}); bin/setup installs reuse"
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
