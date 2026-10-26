# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

# Checks that each gem works once packaged, not just in the repository.
#
# The repository hides packaging mistakes. A file the gemspec forgets still
# loads from the working tree, and a bundle whose rpaths point into vendor/
# still finds its frameworks there, so the gem works in development and
# breaks once installed. This check builds each gem, then proves the
# package on its own: its files, its signatures, and scripts that load it
# in fresh processes that cannot see the repository.
#
# Each gem comes twice. The source gem cannot build once installed, since
# it ships no LÖVE sources, so the check installs it and expects gem
# install to stop with the message that names the precompiled gem. The
# precompiled gem (NativeGem) carries the compiled bundle and the
# frameworks it loads, and the REUSE record of who wrote them under which
# licenses.
#
# Fast mode unpacks the precompiled gem, checks its licensing with the
# REUSE tool, and loads it from there. Delivery
# takes a precompiled gem already built, by rake package:native here or by
# CI's gate job on another runner, installs it into an empty GEM_HOME that
# sees no other installed gem, then runs the lota executable RubyGems
# wrote: lota --version, and lota run on each of the target's games, with
# Lota loaded only from the installed gem.
#
# gem build and Gem::Package.build still build a gemspec they warn about,
# such as one with no homepage, so every check fails on a warning either
# prints.
class PackageCheck
  # One gem to check.
  #
  # [name] Gem name.
  # [dir] Directory holding the gemspec, relative to the repository.
  # [packaged] Paths the source gem ships, relative to +dir+; anything else
  #   in the package is a development file that leaked in.
  # [native_packaged] Paths only the precompiled gem adds outside
  #   +packaged+.
  # [extension] Path of the compiled extension inside the gem, without its
  #   file extension.
  # [native] The NativeGem that builds the precompiled gem.
  # [refusal] Text the source gem's gem install stops with.
  # [smoke] Ruby source that exercises the gem. ARGV[0] is the gem's
  #   directory.
  # [games] The Games that delivery runs with lota run.
  class Target < Data.define(:name, :dir, :packaged, :native_packaged, :extension, :native, :refusal, :smoke, :games)
    # The gemspec file name.
    def gemspec
      "#{name}.gemspec"
    end

    # Path of the compiled extension inside the gem.
    def extension_file
      "#{extension}.#{RbConfig::CONFIG['DLEXT']}"
    end
  end

  # A game for lota run.
  #
  # [name] What the check calls it.
  # [folder] The game's folder, relative to the repository, or nil for one
  #   the check writes from +files+.
  # [files] Each file's name to its source, when +folder+ is nil.
  # [gems] The gems the game requires besides Lota, which the check
  #   installs beside it from the .gem files this machine installed them
  #   from, with what they depend on.
  # [arguments] What lota run passes the game.
  # [output] What the game prints, matched against everything but dyld's
  #   lines.
  # [status] The exit status it ends with.
  class Game < Data.define(:name, :folder, :files, :gems, :arguments, :output, :status); end

  # The directory a framework's signature covers, the version its @rpath
  # install name names (NativeGem::VERSION).
  FRAMEWORK_VERSION = "Versions/A"

  # Raised when a check fails; the message says what to fix.
  class Failure < StandardError; end

  # How RubyGems starts each warning it prints (Gem::StreamUI#alert_warning).
  WARNING = /^WARNING: /

  # How lota run's guard (#guard) reports where Lota loaded from.
  LOADED_FROM = /^lota-package-check: lota loaded from (.+)$/

  # Unsets what Bundler and the repository put in a child's environment.
  UNBUNDLED = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB]
    .to_h { |name| [name, nil] }.freeze

  # Loads every Ruby file the package ships, so a require between packaged
  # files that names a file the package lacks fails here.
  REQUIRE_ALL = <<~RUBY
    spec_dir = ARGV.fetch(0)
    Dir.glob("lib/**/*.rb", base: spec_dir).sort.each do |file|
      next if file.end_with?("/version.rb")

      require File.join(spec_dir, file)
    end
  RUBY

  # Fails when a smoke script loaded anything from the repository instead
  # of the package. ARGV[1] is the repository root.
  ISOLATED = <<~'RUBY'
    roots = [ARGV.fetch(1), File.realpath(ARGV.fetch(1))].map { |root| "#{root}/" }
    leaked = $LOADED_FEATURES.select { |feature| feature.start_with?(*roots) }
    abort "loaded from the repository instead of the package: #{leaked.join(", ")}" if leaked.any?
  RUBY

  # [root] The repository root.
  # [gems] The gems to check, in dependency order.
  # [out] Where progress goes.
  def initialize(root:, gems:, out: $stdout)
    @root = root
    @gems = gems
    @out = out
  end

  # Checks that each source gem stops at install, then builds, unpacks,
  # and smoke-tests each precompiled gem.
  def fast
    Dir.mktmpdir("lota-package") do |work|
      work = File.realpath(work)
      @gems.each { |gem| refuse_source(gem, work) }
      unpacked = @gems.to_h { |gem| [gem, unpack(build_native(gem, work), work)] }
      unpacked.each { |gem, dir| verify_native(gem, dir) }
      smoke(env: isolated_env(File.join(work, "gems")), load_paths: unpacked.values.map { |dir| File.join(dir, "lib") },
        gem_dirs: unpacked)
    end
  end

  # Installs each precompiled gem, from the .gem +files+ already built,
  # into an empty GEM_HOME, then runs its executable and its smoke script
  # from there. Each package is checked for missing and development files
  # first, as a build here is.
  def deliver(files)
    packages = precompiled(files)
    Dir.mktmpdir("lota-package") do |work|
      work = File.realpath(work)
      home = File.join(work, "gems")
      env = isolated_env(home)
      @gems.each do |gem|
        verify_files(gem, unpack(packages.fetch(gem), work), gem.packaged + gem.native_packaged,
          assembled: gem.native.assembled)
        install(gem, packages.fetch(gem), env, work)
      end
      installed = @gems.to_h { |gem| [gem, Dir.glob(File.join(home, "gems", "#{gem.name}-*")).first] }
      installed.each do |gem, dir|
        verify_native(gem, dir, where: "installed")
        run_executable(gem, home, env, work)
      end
      smoke(env:, load_paths: [], gem_dirs: installed)
    end
  end

  # The warnings in what RubyGems printed while building a gem, one line
  # each.
  def self.warnings(output)
    output.lines.grep(WARNING).map(&:chomp)
  end

  # Packaged paths that fall outside +allowed+.
  def self.unexpected_files(allowed, contents)
    contents.reject do |path|
      allowed.any? { |prefix| path == prefix || path.start_with?("#{prefix.chomp('/')}/") }
    end
  end

  # Working-tree files that the package lacks.
  def self.missing_files(working_tree, contents)
    working_tree - contents
  end

  # What the compiled +bundle+ loads through its relative rpaths
  # (<tt>@loader_path/...</tt>), each as a path relative to the bundle's
  # directory: the framework directory for a framework, the file itself for
  # anything else. A copy of the bundle loads only with each of these at the
  # same place relative to it. Libraries no rpath resolves, such as the
  # sanitizer runtime that DYLD_INSERT_LIBRARIES loads, are left out.
  def self.rpath_dependencies(bundle)
    directory = File.dirname(bundle)
    rpath_libraries(bundle).filter_map do |name|
      found = relative_rpaths(bundle).find { |rpath| File.exist?(File.join(directory, rpath, name)) } or next
      File.join(found, name[%r{\A[^/]+\.framework}] || name)
    end
  end

  # Why +bundle+ would not load from inside +gem_dir+ alone: each rpath
  # that is not relative to the bundle, and each library it loads through
  # @rpath that no rpath resolves inside +gem_dir+.
  def self.escapes(bundle, gem_dir)
    rpaths = otool("-l", bundle).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten
    inside = File.join(File.realpath(gem_dir), "")
    absolute = rpaths.reject { |rpath| rpath.start_with?("@loader_path/") }.map { |rpath| "rpath #{rpath}" }
    unresolved = rpath_libraries(bundle).reject do |name|
      relative_rpaths(bundle).any? do |rpath|
        path = File.join(File.dirname(bundle), rpath, name)
        File.exist?(path) && File.realpath(path).start_with?(inside)
      end
    end
    absolute + unresolved.map { |name| "@rpath/#{name} resolves outside #{gem_dir}" }
  end

  # The files dyld reports loading, from output printed with
  # DYLD_PRINT_LIBRARIES set.
  def self.dyld_loaded(output)
    output.scan(/^dyld\[\d+\]: <[\h-]+> (.+)$/).flatten
  end

  # A script lota run loads first (ruby -r), which, as the game exits,
  # prints where lota.rb loaded from, and fails the run if anything loaded
  # from +root+'s lib/, where rake compile also puts the bundle. A game in
  # the repository loads its own files from there, so the rest of the
  # repository may load.
  def self.guard(root)
    libs = [root, File.realpath(root)].uniq.map { |dir| File.join(dir, "lib", "") }
    <<~RUBY
      at_exit do
        lota = $LOADED_FEATURES.find { |feature| feature.end_with?("/lota.rb") }
        puts "lota-package-check: lota loaded from \#{lota || "nowhere"}"
        leaked = $LOADED_FEATURES.select { |feature| feature.start_with?(*#{libs.inspect}) }
        abort "lota run loaded files from the repository's lib/: \#{leaked.join(", ")}" if leaked.any?
      end
    RUBY
  end

  # What lota run's +output+ shows loaded from outside the GEM_HOME
  # +home+: Lota itself, as the guard reports it, and the bundle and each
  # framework that is not macOS's own (from /System), as dyld reports
  # them. A run that loaded no framework at all is reported too.
  def self.outside(output, home)
    installed = File.join(File.realpath(home), "")
    lota = output[LOADED_FROM, 1] || "nowhere the guard reported"
    loaded = dyld_loaded(output)
    frameworks = loaded.grep(%r{\.framework/}).reject { |path| path.start_with?("/System/") }
    native = loaded.grep(%r{/lota/native\.bundle\z})
    problems = (["Lota from #{lota}"] if !lota.start_with?(installed)).to_a
    problems << "no framework at all" if frameworks.empty?
    problems << "no lota/native bundle at all" if native.empty?
    problems + (frameworks + native).reject { |path| path.start_with?(installed) }
  end

  # Runs otool, which macOS's command-line tools provide.
  def self.otool(*arguments)
    output, status = Open3.capture2e("otool", *arguments)
    raise Failure, "otool #{arguments.join(' ')} failed:\n#{output}" unless status.success?

    output
  end

  # The names +bundle+ loads through @rpath.
  private_class_method def self.rpath_libraries(bundle)
    libraries = otool("-L", bundle).lines.drop(1).map { |line| line.split.first }
    libraries.filter_map { |library| library.delete_prefix("@rpath/") if library.start_with?("@rpath/") }
  end

  private_class_method def self.relative_rpaths(bundle)
    otool("-l", bundle).scan(%r{^\s+path @loader_path/(\S+) \(offset \d+\)$}).flatten
  end

  private def build(gem, work)
    output = File.join(work, "#{gem.name}.gem")
    printed = run!(UNBUNDLED, Gem.ruby, "-S", "gem", "build", gem.gemspec, "--output", output,
      chdir: File.join(@root, gem.dir))
    warnings = self.class.warnings(printed)
    raise Failure, "gem build #{gem.gemspec} warned:\n#{warnings.join("\n")}" if warnings.any?

    output
  end

  # Each gem's package in +files+, which must hold a precompiled gem for
  # every gem and nothing else.
  private def precompiled(files)
    specs = files.to_h { |file| [File.expand_path(file), spec_of(file)] }
    unknown = specs.reject { |_, spec| @gems.any? { |gem| gem.name == spec.name } }.keys
    raise Failure, "not gems this repository publishes:\n#{list(unknown)}" if unknown.any?

    @gems.to_h do |gem|
      file, spec = specs.find { |_, given| given.name == gem.name }
      raise Failure, "no precompiled gem given for #{gem.name}" unless file
      raise Failure, "#{File.basename(file)} is #{gem.name}'s source gem; give its precompiled gem" if
        spec.platform == Gem::Platform::RUBY

      [gem, file]
    end
  end

  private def spec_of(file)
    Gem::Package.new(file).spec
  rescue Gem::Package::Error => e
    raise Failure, "#{file} is not a gem: #{e.message}"
  end

  private def build_native(gem, work)
    package = gem.native.build(File.join(work, "native", gem.name))
    unpacked = unpack(package, work)
    verify_files(gem, unpacked, gem.packaged + gem.native_packaged, assembled: gem.native.assembled)
    verify_licensing(gem, unpacked)
    package
  end

  # Installs the source gem into an empty GEM_HOME, which has to stop
  # with +refusal+ before it compiles anything.
  private def refuse_source(gem, work)
    package = build(gem, work)
    verify_files(gem, unpack(package, work), gem.packaged)
    env = isolated_env(File.join(work, "source-gems"))
    output, status = Open3.capture2e(env, Gem.ruby, "-S", "gem", "install", "--norc", "--local", "--no-document",
      "--install-dir", env.fetch("GEM_HOME"), package, chdir: work)
    raise Failure, "#{gem.name}'s source gem installed; it ships no LÖVE sources to build from" if status.success?
    raise Failure, "#{gem.name}'s source gem did not stop with its message:\n#{output}" unless
      output.include?(gem.refusal)

    @out.puts "✅ #{gem.name} (source): gem install stops, naming the precompiled gem"
  end

  private def install(gem, package, env, work)
    @out.puts "Installing #{File.basename(package)} into an empty GEM_HOME..."
    run!(env, Gem.ruby, "-S", "gem", "install", "--norc", "--local", "--no-document", "--install-dir",
      env.fetch("GEM_HOME"), package, chdir: work)
    @out.puts "✅ #{gem.name}: installed #{File.basename(package)}"
  end

  private def unpack(package, work)
    dir = File.join(work, "unpacked", File.basename(package, ".gem"))
    Gem::Package.new(package).extract_files(dir)
    dir
  end

  private def contents(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).reject { |path| File.directory?(File.join(dir, path)) }
  end

  # Fails when the package at +dir+ ships a path outside +allowed+, or
  # lacks a file of the working tree's, except under +assembled+, which
  # the package builds for itself.
  private def verify_files(gem, dir, allowed, assembled: [])
    packaged = contents(dir)
    unexpected = self.class.unexpected_files(allowed, packaged)
    tree = working_tree(gem).reject { |path| assembled.any? { |prefix| path.start_with?("#{prefix}/") } }
    missing = self.class.missing_files(tree, packaged)
    problems = []
    problems << "ships development files:\n#{list(unexpected)}" if unexpected.any?
    problems << "lacks files the repository loads (git add them, or add them to spec.files):\n#{list(missing)}" if missing.any?
    raise Failure, "#{File.basename(dir)} #{problems.join("\n")}" if problems.any?

    @out.puts "✅ #{File.basename(dir)}: #{packaged.size} files, none missing, no development files"
  end

  # Tracked and untracked (not ignored) files under the packaged paths. An
  # untracked file is the usual way to lose one: it loads from the working
  # tree, but spec.files comes from git ls-files.
  private def working_tree(gem)
    dir = File.join(@root, gem.dir)
    listed, status = Open3.capture2("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
      *gem.packaged, chdir: dir)
    raise Failure, "git ls-files failed in #{dir}" unless status.success?

    listed.split("\x0").select { |path| File.file?(File.join(dir, path)) }
  end

  # The unpacked package at +dir+ is a REUSE project the REUSE tool calls
  # compliant (REUSE Specification 3.3): every file has its copyright and
  # license, the frameworks and the bundle by the annotations NativeGem
  # wrote, and LICENSES/ holds each license's text, and no other.
  private def verify_licensing(gem, dir)
    output, status = Open3.capture2e("reuse", "--root", dir, "lint")
    raise Failure, "#{File.basename(dir)} is not REUSE compliant:\n#{output}" unless status.success?

    @out.puts "✅ #{gem.name}: REUSE compliant, #{Dir.glob('LICENSES/*.txt', base: dir).size} license texts"
  rescue Errno::ENOENT
    raise Failure, "reuse is not on PATH; bin/setup installs it"
  end

  # The bundle and each framework it loads, in +dir+, load from +dir+
  # alone and pass strict signature verification.
  private def verify_native(gem, dir, where: "unpacked")
    bundle = File.join(dir, gem.extension_file)
    raise Failure, "#{gem.name} ships no #{gem.extension_file}" unless File.file?(bundle)

    escapes = self.class.escapes(bundle, dir)
    raise Failure, "#{gem.extension_file} would load from outside the gem:\n#{list(escapes)}" if escapes.any?

    signed = [bundle] + self.class.rpath_dependencies(bundle).map do |framework|
      File.join(File.expand_path(framework, File.dirname(bundle)), FRAMEWORK_VERSION)
    end
    signed.each { |path| run!({}, "codesign", "--verify", "--strict", "--verbose=2", path, chdir: dir) }
    @out.puts "✅ #{gem.name}: #{signed.size} signatures verify, every framework loads from the #{where} gem"
  end

  # Runs the installed executable as a player's shell would: lota
  # --version, then lota run on each of the target's games, with dyld
  # reporting what it loads.
  private def run_executable(gem, home, env, work)
    lota = File.join(home, "bin", gem.name)
    version = run!(env, Gem.ruby, lota, "--version", chdir: work)
    @out.puts "✅ #{gem.name} --version: #{version.strip}"

    guard = guard(work)
    gem.games.each do |game|
      install_dependencies(game, env, work)
      output, status = Open3.capture2e(env.merge("DYLD_PRINT_LIBRARIES" => "1"), Gem.ruby, "-r", guard, lota, "run",
        game_folder(game, work), *game.arguments, chdir: work)
      verify_game(game, home, output, status)
    end
  end

  private def game_folder(game, work)
    return File.join(@root, game.folder) if game.folder

    folder = File.join(work, "games", game.name)
    FileUtils.mkdir_p(folder)
    game.files.each { |name, source| File.write(File.join(folder, name), source) }
    folder
  end

  private def guard(work)
    path = File.join(work, "guard.rb")
    File.write(path, self.class.guard(@root))
    path
  end

  # Installs the gems +game+ requires, and what they depend on, into the
  # GEM_HOME Lota went into. gem install's resolver does not see Ruby's
  # default gems from an isolated GEM_PATH, though require does, so each
  # package installs without resolving, and a dependency a default gem
  # satisfies is left to the default gem; the game's run proves the set
  # loads.
  private def install_dependencies(game, env, work)
    return if game.gems.empty?

    packages = dependency_packages(game.gems).values
    run!(env, Gem.ruby, "-S", "gem", "install", "--norc", "--local", "--no-document", "--ignore-dependencies",
      "--install-dir", env.fetch("GEM_HOME"), *packages, chdir: work)
    @out.puts "✅ #{game.name}: installed #{packages.map { |package| File.basename(package) }.join(', ')}"
  end

  # Each gem +names+ needs, and each it depends on that no default gem of
  # this Ruby satisfies, by name, with the .gem file this machine installed
  # it from.
  private def dependency_packages(names, packages = {})
    names.each do |name|
      next if packages.key?(name)

      spec = Gem::Specification.find_by_name(name)
      raise Failure, "#{spec.full_name} is installed without its .gem file, #{spec.cache_file}" unless
        File.file?(spec.cache_file)

      packages[name] = spec.cache_file
      needed = spec.runtime_dependencies.reject { |dependency| default_gem?(dependency) }
      dependency_packages(needed.map(&:name), packages)
    end
    packages
  end

  # Whether a gem that comes with this Ruby satisfies +dependency+, so
  # every Ruby has it and nothing needs installing.
  private def default_gem?(dependency)
    Dir.glob(File.join(Gem.default_specifications_dir, "#{dependency.name}-*.gemspec")).any? do |file|
      spec = Gem::Specification.load(file)
      spec&.name == dependency.name && dependency.requirement.satisfied_by?(spec.version)
    end
  end

  private def verify_game(game, home, output, status)
    printed = output.lines.grep_v(/^dyld\[\d+\]: /).grep_v(LOADED_FROM).join
    unless status.exitstatus == game.status && game.output.match?(printed)
      raise Failure, "lota run #{game.name} exited #{status.inspect}, expected #{game.status}, and printed:\n#{printed}"
    end

    outside = self.class.outside(output, home)
    raise Failure, "lota run #{game.name} loaded from outside the installed gem:\n#{list(outside)}" if outside.any?

    frameworks = self.class.dyld_loaded(output).grep(%r{\.framework/}).reject { |path| path.start_with?("/System/") }
    @out.puts "✅ lota run #{game.name}: exited #{status.exitstatus}, with Lota and " \
      "#{frameworks.map { |path| File.basename(path) }.join(', ')} loaded from the installed gem"
  end

  # Runs each gem's smoke script in a process that sees only the packages.
  private def smoke(env:, load_paths:, gem_dirs:)
    includes = load_paths.flat_map { |path| ["-I", path] }
    gem_dirs.each do |gem, dir|
      root = File.expand_path(@root)
      run!(env, Gem.ruby, *includes, "-e", REQUIRE_ALL + ISOLATED, dir, root, chdir: Dir.tmpdir)
      output = run!(env, Gem.ruby, *includes, "-e", gem.smoke + ISOLATED, dir, root, chdir: Dir.tmpdir)
      @out.puts "✅ #{gem.name}: #{output.strip}"
    end
  end

  # An environment with no Bundler, no repository load path, and a gem
  # directory of its own that is the only one RubyGems sees: Ruby's default
  # gems still load, but no gem this machine installed does.
  private def isolated_env(home)
    UNBUNDLED.merge("GEM_HOME" => home, "GEM_PATH" => home)
  end

  private def run!(env, *command, chdir:)
    output, status = Open3.capture2e(env, *command, chdir:)
    raise Failure, "#{command.join(' ')} failed in #{chdir}:\n#{output}" unless status.success?

    output
  end

  private def list(paths)
    paths.sort.map { |path| "  #{path}" }.join("\n")
  end
end
