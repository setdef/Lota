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
# frameworks it loads.
#
# Fast mode (the default gate) unpacks the precompiled gem and loads it
# from there. Full mode installs it into an empty GEM_HOME that sees no
# other installed gem, then runs the lota executable RubyGems wrote: lota
# --version, and lota run on a game that opens a window.
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
  # [game] The Game that full mode runs with lota run.
  class Target < Data.define(:name, :dir, :packaged, :native_packaged, :extension, :native, :refusal, :smoke, :game)
    # The gemspec file name.
    def gemspec
      "#{name}.gemspec"
    end

    # Path of the compiled extension inside the gem.
    def extension_file
      "#{extension}.#{RbConfig::CONFIG['DLEXT']}"
    end
  end

  # A game folder for lota run: its files (name to source), the arguments
  # it runs with, and the output and exit status it ends with.
  class Game < Data.define(:files, :arguments, :output, :status); end

  # The directory a framework's signature covers, the version its @rpath
  # install name names (NativeGem::VERSION).
  FRAMEWORK_VERSION = "Versions/A"

  # Raised when a check fails; the message says what to fix.
  class Failure < StandardError; end

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

  # Installs each precompiled gem into an empty GEM_HOME, then runs its
  # executable and its smoke script from there.
  def full
    Dir.mktmpdir("lota-package") do |work|
      work = File.realpath(work)
      home = File.join(work, "gems")
      env = isolated_env(home)
      @gems.each { |gem| install(gem, build_native(gem, work), env, work) }
      installed = @gems.to_h { |gem| [gem, Dir.glob(File.join(home, "gems", "#{gem.name}-*")).first] }
      installed.each do |gem, dir|
        verify_native(gem, dir, where: "installed")
        run_executable(gem, home, env, work)
      end
      smoke(env:, load_paths: [], gem_dirs: installed)
    end
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
    run!(UNBUNDLED, Gem.ruby, "-S", "gem", "build", gem.gemspec, "--output", output, chdir: File.join(@root, gem.dir))
    output
  end

  private def build_native(gem, work)
    package = gem.native.build(File.join(work, "native", gem.name))
    verify_files(gem, unpack(package, work), gem.packaged + gem.native_packaged)
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

  private def verify_files(gem, dir, allowed)
    packaged = contents(dir)
    unexpected = self.class.unexpected_files(allowed, packaged)
    missing = self.class.missing_files(working_tree(gem), packaged)
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
  # --version, then lota run on the target's game, with dyld reporting
  # what it loads.
  private def run_executable(gem, home, env, work)
    lota = File.join(home, "bin", gem.name)
    version = run!(env, Gem.ruby, lota, "--version", chdir: work)
    @out.puts "✅ #{gem.name} --version: #{version.strip}"

    folder = File.join(work, "game")
    FileUtils.mkdir_p(folder)
    gem.game.files.each { |name, source| File.write(File.join(folder, name), source) }
    output, status = Open3.capture2e(env.merge("DYLD_PRINT_LIBRARIES" => "1"), Gem.ruby, lota, "run", folder,
      *gem.game.arguments, chdir: work)
    verify_game(gem, home, output, status)
  end

  private def verify_game(gem, home, output, status)
    loaded = self.class.dyld_loaded(output)
    printed = output.lines.grep_v(/^dyld\[\d+\]: /).join
    unless status.exitstatus == gem.game.status && printed == gem.game.output
      raise Failure, "lota run exited #{status.inspect}, expected #{gem.game.status}, and printed:\n#{printed}"
    end

    # macOS's own frameworks load from /System; any other comes with the gem.
    frameworks = loaded.grep(%r{\.framework/}).reject { |path| path.start_with?("/System/") }
    outside = frameworks.reject { |path| path.start_with?(File.join(File.realpath(home), "")) }
    raise Failure, "lota run loaded no framework from the gem" if frameworks.empty?
    raise Failure, "lota run loaded frameworks from outside the gem:\n#{list(outside)}" if outside.any?

    @out.puts "✅ lota run: exited #{status.exitstatus}, with #{frameworks.map { |path| File.basename(path) }.join(', ')} " \
      "loaded from the installed gem"
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
