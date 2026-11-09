# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "stringio"
require_relative "licensing"
require_relative "native_format"
require_relative "package_check"
require_relative "source_archive"

# Builds Lota's precompiled gem for the platform it runs on: Apple Silicon
# macOS (arm64-darwin), Linux with glibc on x86_64 or arm64
# (x86_64-linux-gnu, aarch64-linux-gnu), or Windows with RubyInstaller's
# UCRT Ruby on x64 or ARM64 (x64-mingw-ucrt, aarch64-mingw-ucrt).
#
# The source gem cannot build Lota's extension once installed: the build
# needs LÖVE's sources and its dependencies (love-apple-dependencies'
# frameworks, or on Linux and Windows the libraries `rake dependencies`
# builds), which
# do not ship. So Lota ships what rake compile built, as rake-compiler's
# native gems do: the gem's platform is the build's, it has no extension
# to compile, and the compiled bundle sits where require "lota/native"
# finds it. gem install copies files and builds nothing, so it needs
# neither Rice nor CMake.
#
# The bundle loads LÖVE's libraries through rpaths relative to itself,
# which rake compile's bundle points into vendor/ or tmp/. The gem carries
# each library the bundle loads, and what those load, in a directory of
# its own beside the bundle, and the bundle's rpaths are replaced by one
# into that directory, each in its platform's terms (NativeFormat):
#
# - On macOS, the frameworks go in lib/lota/frameworks
#   (@loader_path/frameworks), each as the one version directory its
#   install name names (Versions/A), without the symlinks around it, on
#   which RubyGems warns, without its headers, with only its arm64 code,
#   and without the rpaths that point outside the gem, such as vorbis's
#   /Library/Frameworks, where a framework installed on the Mac would
#   shadow the gem's own. Changing a Mach-O file invalidates its code
#   signature, and SDL3's signature in love-apple-dependencies seals a
#   file its checkout lacks (LICENSE.txt, checked out as License.txt), so
#   the bundle and every framework are signed again ad hoc, as
#   love-apple-dependencies signs them, and verified with codesign
#   --verify --strict.
# - On Linux, the libraries go in lib/lota/libraries ($ORIGIN/libraries),
#   each as a file named for the soname it is needed by, without its
#   debugging information, and with its own rpath pointed at that
#   directory ($ORIGIN), as LÖVE's AppImage carries them. Only glibc's and
#   GCC's C++ runtime libraries that the manylinux policy allows come from
#   the system (NativeFormat::ELF::SYSTEM).
# - On Windows, which has no rpath, the DLLs, SDL3.dll and OpenAL32.dll,
#   go in lib/lota/libraries, and the preloader (lib/lota/preload.so),
#   which loads them by their absolute paths before the bundle loads, goes
#   beside the bundle as its companion; every other library LÖVE links is
#   in the bundle, and its archive is recorded with the bundle's works. Each is
#   staged without its debugging information. Only Windows' own DLLs and
#   Ruby's come from the system (NativeFormat::PE::SYSTEM).
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
#
# A library whose license asks for its source code with its object code,
# as OpenAL Soft's does, carries the archive of that source in the gem's
# sources/, from where rake sources:fetch keeps it, checked against the
# SHA-256 the record gives; the build stops without it.
#
# An app that lota fuse builds ships the gem, and its notices
# (Lota::Notices) name what the gem carries, so the gem carries their
# manifest, Licensing::NOTICES: the works the bundle carries and each
# library beside it, from the same record and the same linker's map as
# its REUSE.toml, so each platform's notices name its own gem's contents.
class NativeGem
  # The record of who wrote what the gem carries.
  attr_reader :licensing

  # How the platform holds compiled code (NativeFormat).
  attr_reader :format

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
  # [format] The NativeFormat of the platform the bundle was built on.
  # [dependencies] Where LÖVE's dependencies' headers are, relative to
  #   +root+, which the bundle compiled against but does not carry: a
  #   directory, or a list of directories and files (#outside).
  def initialize(root:, gemspec:, bundle:, build:, licensing:, licenses:, format: NativeFormat.host,
    dependencies: "vendor/love-apple-dependencies"
  )
    @root = root
    @gemspec = gemspec
    @bundle = bundle
    @build = build
    @licensing = licensing
    @licenses = licenses
    @format = format
    @dependencies = dependencies
  end

  # The platform of the gem it builds.
  def platform
    @format.platform
  end

  # Where the gem carries the libraries the bundle loads, relative to the
  # gem.
  def library_dir
    File.join(File.dirname(@bundle), @format.directory)
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
    libraries = library_sources
    works = bundled_works(@bundle)
    companions = self.companions.to_h { |companion| [companion, bundled_works(companion)] }
    stage = File.join(work, "stage")
    FileUtils.rm_rf(stage)
    spec = source_spec
    files = spec.files.reject { |file| file.start_with?("#{LICENSES}/") }
    files.each { |file| copy(File.join(@root, file), File.join(stage, file)) }
    companions.each_key { |companion| copy(File.join(@root, companion), File.join(stage, companion)) }
    files += stage_bundle(stage) + companions.keys
    files += libraries.flat_map { |_, source| formatted { @format.stage_library(stage, library_dir, source) } }
    files += stage_sources(stage, libraries.keys)
    files += stage_notices(stage, works, companions, libraries.keys)
    files += stage_licensing(stage, works, companions, libraries.keys)
    package(native_spec(spec, files), stage, work)
  end

  # The extensions the gem carries beside the bundle, relative to the gem:
  # on Windows the preloader, which loads the bundle's DLLs first
  # (NativeFormat::PE).
  def companions
    formatted { @format.companions(@bundle) }.map { |name| File.join(File.dirname(@bundle), name) }
  end

  # The Ruby requirement: the source gem's, below the next minor version
  # of the Ruby whose ABI the bundle was compiled for (this one), as
  # rake-compiler bounds its native gems.
  def self.required_ruby_version(source)
    major, minor = RbConfig::CONFIG.values_at("MAJOR", "MINOR").map(&:to_i)
    Gem::Requirement.new(*source.requirements.map { |op, version| "#{op} #{version}" }, "< #{major}.#{minor + 1}.dev")
  end

  # Each library the bundle loads, frameworks on macOS, by name, with its
  # path in the repository. Fails on one the record lacks.
  private def library_sources
    bundle = File.join(@root, @bundle)
    formatted { @format.dependencies(bundle) }.to_h do |relative|
      name = File.basename(relative)
      recorded { @licensing.framework_for(name) }
      [name, File.expand_path(relative, File.dirname(bundle))]
    end
  end

  private def formatted
    yield
  rescue NativeFormat::Failure => e
    raise PackageCheck::Failure, e.message
  end

  # The works the extension +extension+ (the bundle, or a companion)
  # carries, from the linker's map of the one the build linked, which must
  # be the one rake compile copied. Fails on a file the record lacks.
  private def bundled_works(extension)
    built = File.join(@root, @build, extension)
    unless File.file?(built) && FileUtils.compare_file(built, File.join(@root, extension))
      raise PackageCheck::Failure, "#{extension} is not #{File.join(@build, extension)}; run rake compile"
    end

    linked = LinkedFiles.read(map: built.sub(/\.[^.]+\z/, ".map"), build: File.join(@root, @build),
      libraries: dependency_directories + formatted { @format.library_directories })
    recorded { @licensing.bundled(linked, root: @root, outside:) }
  rescue LinkedFiles::Failure => e
    raise PackageCheck::Failure, e.message
  end

  # What the bundle reads that is not code it carries, so the record need
  # not cover it: the toolchain's and the SDK's headers and runtime (on
  # Linux, the system's compiler and glibc's, under /usr; on Windows, the
  # MSYS2 environment's, with Ruby's import library), Ruby's headers,
  # which every extension compiles against, and the libraries' headers,
  # whose code ships in the libraries the bundle loads, each recorded on
  # its own. The maintainer confirmed this scope. Each of +@dependencies+
  # is a directory, whose files are all outside, or a file, such as
  # OpenAL Soft's or SDL's import library on Windows, whose stubs call
  # into the DLL the gem carries.
  private def outside
    dirs = [*formatted { @format.toolchain }, RbConfig::CONFIG.fetch("rubyhdrdir")].map { |dir| File.join(dir, "") }
    dirs + Array(@dependencies).map do |path|
      full = File.join(@root, path)
      File.file?(full) ? full : File.join(full, "")
    end
  end

  # The directories of +@dependencies+, where the linker found the
  # libraries LÖVE's dependencies built, which a map that names a library
  # without its directory means before any of the toolchain's of the same
  # name, such as an SDL an MSYS2 installed.
  private def dependency_directories
    Array(@dependencies).map do |path|
      full = File.join(@root, path)
      File.file?(full) ? File.dirname(full) : full
    end.uniq
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
    formatted { @format.stage_bundle(bundle) }
    [@bundle]
  end

  # Copies the source archive of each of +frameworks+ that records one
  # into the gem's sources/, after checking it is the archive recorded.
  private def stage_sources(stage, frameworks)
    @licensing.sources(frameworks).map do |source|
      archive = SourceArchive.new(source, root: @root)
      archive.verify!
      target = File.join(Licensing::SOURCES, source.name)
      copy(archive.path, File.join(stage, target))
      target
    end
  rescue SourceArchive::Failure => e
    raise PackageCheck::Failure, e.message
  end

  # Writes the manifest of what the gem carries, from which lota fuse
  # writes an app's notices (Licensing#notices), as Licensing::NOTICES.
  private def stage_notices(stage, works, companions, frameworks)
    manifest = @licensing.notices(bundle: @bundle, works:, companions:,
      frameworks: frameworks.to_h { |name| [name, File.join(library_dir, name)] })
    File.write(File.join(stage, Licensing::NOTICES), "#{JSON.pretty_generate(manifest)}\n")
    [Licensing::NOTICES]
  end

  # The REUSE.toml annotation of the notices manifest, which the build
  # writes from ext/lota/licenses.rb, so it is under that file's license.
  # The words of credit it quotes, as FreeType's, are not its own notices
  # of copyright, so the annotation overrides what REUSE would read in it.
  NOTICES_ANNOTATION = <<~TOML
    [[annotations]]
    path = "#{Licensing::NOTICES}"
    precedence = "override"
    SPDX-FileCopyrightText = "2026 setdef <kerrick@setdef.com>"
    SPDX-License-Identifier = "AGPL-3.0-or-later"
  TOML

  # Writes the gem's REUSE.toml and LICENSES/, and checks the gem with
  # the REUSE tool. Every license text goes in first, and the ones no file
  # uses come out, so what remains is exactly what REUSE asks for.
  private def stage_licensing(stage, works, companions, frameworks)
    annotations = @licensing.annotations(bundle: @bundle, works:, companions:, frameworks: frameworks.to_h do |name|
      [name, @format.annotation(File.join(library_dir, name))]
    end)
    File.write(File.join(stage, REUSE_TOML), "#{File.read(File.join(@root, REUSE_TOML))}\n#{annotations}\n#{NOTICES_ANNOTATION}")
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

  # The REUSE tool's report on the directory +dir+.
  private def reuse_lint(dir)
    output, = Open3.capture2("reuse", "--root", dir, "lint", "--json")
    JSON.parse(output)
  rescue JSON::ParserError, Errno::ENOENT => e
    raise PackageCheck::Failure, "reuse lint did not report on #{dir} (#{e.message}); bin/setup installs reuse"
  end

  private def native_spec(source, files)
    source.dup.tap do |spec|
      spec.platform = Gem::Platform.new(platform)
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

  private def copy(source, target)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(source, target, preserve: true)
  end
end
