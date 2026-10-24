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
# loads from the working tree, so the gem works in development and breaks
# once installed. This check builds each gem with gem build, then proves
# the package on its own: its files, and a smoke script that loads it in a
# fresh process that cannot see the repository.
#
# Fast mode (the default gate) unpacks each gem and loads it with the
# native extension the repository already compiled. Full mode installs the
# gems into an empty GEM_HOME, so RubyGems compiles every extension from the
# packaged sources.
class PackageCheck
  # One gem to check.
  #
  # [name] Gem name.
  # [dir] Directory holding the gemspec, relative to the repository.
  # [packaged] Paths the gem ships, relative to +dir+; anything else in the
  #   package is a development file that leaked in.
  # [generated] Globs of git-ignored files the gemspec adds by hand.
  # [extension] Path of the compiled extension inside the gem, without its
  #   file extension, or +nil+.
  # [smoke] Ruby source that exercises the gem. ARGV[0] is the gem's
  #   directory.
  class Target < Data.define(:name, :dir, :packaged, :generated, :extension, :smoke)
    # The gemspec file name.
    def gemspec
      "#{name}.gemspec"
    end

    # Path of the compiled extension inside the gem, or +nil+.
    def extension_file
      "#{extension}.#{RbConfig::CONFIG['DLEXT']}" if extension
    end
  end

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

  # Builds, unpacks, and smoke-tests each gem against the repository's
  # compiled extensions.
  def fast
    Dir.mktmpdir("lota-package") do |work|
      unpacked = @gems.to_h { |gem| [gem, unpack(build(gem, work), work)] }
      unpacked.each do |gem, dir|
        verify_files(gem, dir)
        copy_extension(gem, dir)
      end
      smoke(env: isolated_env(File.join(work, "gems")), load_paths: unpacked.values.map { |dir| File.join(dir, "lib") },
        gem_dirs: unpacked)
    end
  end

  # Installs each gem into an empty GEM_HOME, compiling native extensions
  # from the packaged sources, then smoke-tests the installed gems.
  def full
    Dir.mktmpdir("lota-package") do |work|
      home = File.join(work, "gems")
      packages = @gems.map { |gem| build(gem, work) }
      @gems.zip(packages).each { |gem, package| verify_files(gem, unpack(package, work)) }
      env = isolated_env(home)
      packages.each do |package|
        @out.puts "Installing #{File.basename(package)} (compiling from the packaged sources)..."
        run!(env, Gem.ruby, "-S", "gem", "install", "--local", "--no-document", "--install-dir", home, package,
          chdir: work)
      end
      installed = @gems.to_h { |gem| [gem, Dir.glob(File.join(home, "gems", "#{gem.name}-*")).first] }
      smoke(env:, load_paths: [], gem_dirs: installed)
    end
  end

  # Packaged paths that fall outside the gem's +packaged+ list.
  def self.unexpected_files(gem, contents)
    contents.reject do |path|
      gem.packaged.any? { |allowed| path == allowed || path.start_with?("#{allowed.chomp('/')}/") }
    end
  end

  # Working-tree files that the package lacks.
  def self.missing_files(working_tree, contents)
    working_tree - contents
  end

  private def build(gem, work)
    output = File.join(work, "#{gem.name}.gem")
    run!(UNBUNDLED, Gem.ruby, "-S", "gem", "build", gem.gemspec, "--output", output, chdir: File.join(@root, gem.dir))
    output
  end

  private def unpack(package, work)
    dir = File.join(work, "unpacked", File.basename(package, ".gem"))
    Gem::Package.new(package).extract_files(dir)
    dir
  end

  private def contents(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).reject { |path| File.directory?(File.join(dir, path)) }
  end

  private def verify_files(gem, dir)
    packaged = contents(dir)
    unexpected = self.class.unexpected_files(gem, packaged)
    missing = self.class.missing_files(working_tree(gem), packaged)
    problems = []
    problems << "ships development files:\n#{list(unexpected)}" if unexpected.any?
    problems << "lacks files the repository loads (git add them, or add them to spec.files):\n#{list(missing)}" if missing.any?
    raise Failure, "#{gem.name} #{problems.join("\n")}" if problems.any?

    @out.puts "✅ #{gem.name}: #{packaged.size} files, none missing, no development files"
  end

  # Tracked and untracked (not ignored) files under the packaged paths, plus
  # the generated files the gemspec adds by hand. An untracked file is the
  # usual way to lose one: it loads from the working tree, but spec.files
  # comes from git ls-files.
  private def working_tree(gem)
    dir = File.join(@root, gem.dir)
    listed, status = Open3.capture2("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
      *gem.packaged, chdir: dir)
    raise Failure, "git ls-files failed in #{dir}" unless status.success?

    files = listed.split("\x0").select { |path| File.file?(File.join(dir, path)) }
    files + gem.generated.flat_map { |pattern| Dir.glob(pattern, base: dir) }
  end

  private def copy_extension(gem, dir)
    return unless gem.extension_file

    source = File.join(@root, gem.dir, gem.extension_file)
    raise Failure, "#{gem.name}: #{source} is missing; compile first" unless File.exist?(source)

    FileUtils.mkdir_p(File.dirname(File.join(dir, gem.extension_file)))
    FileUtils.cp(source, File.join(dir, gem.extension_file))
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

  # An environment with no Bundler, no repository load path, and a GEM_HOME
  # of its own. GEM_PATH keeps Ruby's own gem directory for the bundled
  # gems (logger).
  private def isolated_env(home)
    UNBUNDLED.merge("GEM_HOME" => home, "GEM_PATH" => [home, Gem.default_dir].join(File::PATH_SEPARATOR))
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
