# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "open3"
require "tmpdir"

# LÖVE's Linux build, as LÖVE's own Linux CI runs it
# (vendor/love/.github/workflows/main.yml, the Linux job):
# love2d/love-appimage-source's Makefile, pinned at
# vendor/love-appimage-source, which downloads each of LÖVE's dependencies
# at the version it names, builds them from source into its installdir,
# then builds love against them there. Lota's engine links those libraries
# (ext/lota/engine/dependencies_linux.cmake), and the parity harness runs
# that love as its reference (Plan 001), so both run the same SDL, OpenAL
# Soft, and FreeType, as on macOS both load love-apple-dependencies'.
#
# The Makefile downloads as it builds. Lota keeps the two apart, so that
# the gate never needs the network:
#
# - #fetch runs only the Makefile's download rules, in +sources+
#   (vendor/sources/linux, which git ignores), as rake sources:fetch keeps
#   the source archives the precompiled gem carries.
# - #dependencies copies what #fetch downloaded into +root+
#   (tmp/dependencies) and runs the rules that build each library there.
# - #love exports vendor/love's commit into +root+ under the name the
#   Makefile gives its clone of LÖVE, love2d-<commit>, as LÖVE's CI checks
#   LÖVE out there (its "Checkout LÖVE" step), and runs the rule that
#   builds love.
#
# Two things differ from LÖVE's CI, neither in what is compiled: LÖVE is
# vendor/love's commit, rather than a fresh clone; and the steps that pack
# love into an AppImage are left out, since the harness runs love from the
# installdir, as the AppImage's own AppRun runs it (love.sh). Everything
# builds with the CMake the Makefile downloads, 3.30.4, as on LÖVE's CI;
# CMake 4's FindZLIB, for one, cannot read the relative ZLIB_ROOT the
# Makefile gives LÖVE's configure.
#
# A step is skipped when what it made was made from the same Makefile,
# recipe (this file), and compiler, and for love the same commit of LÖVE.
class LinuxBuild
  # Raised when a step fails; its output is in the log.
  class Failure < StandardError; end

  # What the Makefile downloads, by the variable that names each, with the
  # file its download rule makes, from the variable's value: CMake's
  # installer, and each dependency's release.
  DOWNLOADS = {
    "CMAKE_VERSION" => "cmake_install.sh",
    "SDL3_PATH" => "%s/CMakeLists.txt",
    "LIBOGG_FILE" => "%s.tar.gz",
    "LIBVORBIS_FILE" => "%s.tar.gz",
    "LIBTHEORA_FILE" => "%s.tar.gz",
    "ZLIB_PATH" => "%s/configure",
    "OPENAL_PATH" => "%s/CMakeLists.txt",
    "BZIP2_FILE" => "%s.tar.gz",
    "FT_FILE" => "%s.tar.gz",
    "HB_PATH" => "%s/CMakeLists.txt",
    "LIBMODPLUG_FILE" => "%s.tar.gz",
    "LUAJIT_PATH" => "%s/Makefile",
  }.freeze

  # The libraries love links, the prerequisites of the Makefile's rule
  # that configures it: each of LÖVE's dependencies, and LuaJIT, which
  # only love links.
  LIBRARIES = %w[luajit-5.1 modplug freetype openal z theora vorbis ogg SDL3 harfbuzz]
    .map { |name| "installdir/lib/lib#{name}.so" }.freeze

  # The rule that builds love.
  LOVE = "installdir/bin/love"

  # [makefile] love-appimage-source's Makefile, in its checkout.
  # [sources] Where #fetch downloads (vendor/sources/linux).
  # [root] Where the build goes (tmp/dependencies).
  # [out] Where progress goes; +nil+ means wherever $stdout points.
  def initialize(makefile:, sources:, root:, out: nil)
    @makefile = File.expand_path(makefile)
    @sources = File.expand_path(sources)
    @root = File.expand_path(root)
    @out = out
  end

  # love-appimage-source's Makefile.
  def makefile
    @makefile
  end

  # The installdir, which holds every library and love.
  def installdir
    File.join(@root, "installdir")
  end

  # The love executable #love builds.
  def executable
    File.join(@root, LOVE)
  end

  # The build's log.
  def log
    File.join(@root, "build.log")
  end

  # The files the Makefile's download rules make, relative to where they
  # run, each the first part of one: a directory a clone makes, or an
  # archive or installer.
  def downloads
    values = variables(*DOWNLOADS.keys)
    DOWNLOADS.map { |name, rule| rule.include?("%s") ? format(rule, values.fetch(name)) : rule }
  end

  # How many times #fetch tries the downloads: their hosts, such as
  # SourceForge, fail now and then, which LÖVE's CI rides out by running
  # them again (its "Get Dependencies for AppImage" step).
  ATTEMPTS = 5

  # Downloads what the Makefile builds from into +sources+, unless it is
  # there for this Makefile.
  def fetch
    stamp = File.join(@sources, "stamp")
    if File.exist?(stamp) && File.read(stamp) == fetch_stamp
      say "✅ LÖVE's Linux dependencies are downloaded: #{@sources}"
      return
    end

    FileUtils.rm_rf(@sources)
    FileUtils.mkdir_p(@sources)
    attempt { make(@sources, File.join(@sources, "fetch.log"), *downloads) }
    File.write(stamp, fetch_stamp)
    say "✅ Downloaded LÖVE's Linux dependencies: #{@sources}"
  end

  # The stamp #dependencies writes, whose time is when they were built.
  def dependencies_stamp
    stamp_file("dependencies")
  end

  # Builds every library love links into installdir, from what #fetch
  # downloaded, unless it is current. Raises Failure if a step fails, or
  # if #fetch has not run.
  def dependencies
    if current?("dependencies")
      say "✅ LÖVE's Linux dependencies are current: #{installdir}"
      return installdir
    end

    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    copy_downloads
    make(@root, log, *LIBRARIES)
    File.write(stamp_file("dependencies"), stamp)
    say "✅ Built LÖVE's Linux dependencies: #{installdir}"
    installdir
  end

  # Builds love from the commit the git checkout +love+ is at, against
  # the dependencies, unless it is current, and returns its executable.
  def love(love)
    dependencies
    commit = git(love, "rev-parse", "HEAD")
    if current?("love", commit)
      say "✅ The reference love is current: #{executable}"
      return executable
    end

    FileUtils.rm_f(executable)
    export(love, File.join(@root, "love2d-#{commit}"))
    make(@root, log, LOVE, "LOVE_BRANCH=#{commit}")
    File.write(stamp_file("love"), stamp(commit))
    say "✅ Built the reference love: #{executable}"
    executable
  end

  # What a step's result depends on: the Makefile, this recipe, the
  # compiler, and anything +more+.
  def stamp(*more)
    [
      "makefile #{Digest::SHA256.file(@makefile).hexdigest}",
      "recipe #{Digest::SHA256.file(__FILE__).hexdigest}",
      "compiler #{capture('cc', '--version').lines.first&.strip}",
      *more,
    ].join("\n")
  end

  # The values of the Makefile's +names+, as it sets them, read through a
  # second makefile with a rule that prints one.
  def variables(*names)
    Dir.mktmpdir("lota-linux-build") do |dir|
      printer = File.join(dir, "print.mk")
      File.write(printer, "lota-print-%:\n\t@echo '$*=$($*)'\n")
      output = capture("make", "--no-print-directory", "-s", "-f", @makefile, "-f", printer,
        *names.map { |name| "lota-print-#{name}" }, chdir: dir)
      output.lines(chomp: true).to_h { |line| line.split("=", 2) }
    end
  end

  # Runs the block until it does not fail, ATTEMPTS times at most. A
  # download the Makefile left half made, such as a clone, is made again,
  # since make removes nothing it failed to make, so each attempt starts
  # without what the last one left.
  private def attempt
    tries = 0
    begin
      yield
    rescue Failure
      tries += 1
      raise if tries >= ATTEMPTS

      say "Retrying the downloads (#{tries} of #{ATTEMPTS - 1})"
      Dir.children(@sources).each { |name| FileUtils.rm_rf(File.join(@sources, name)) unless name.end_with?(".log") }
      retry
    end
  end

  # What the downloads depend on: the Makefile, and which of its downloads
  # #fetch runs.
  private def fetch_stamp
    "makefile #{Digest::SHA256.file(@makefile).hexdigest}\ndownloads #{downloads.join(' ')}"
  end

  private def stamp_file(step)
    File.join(@root, "#{step}.stamp")
  end

  private def current?(step, *more)
    file = stamp_file(step)
    File.exist?(file) && File.read(file) == stamp(*more)
  end

  # Copies each download #fetch made into +root+, where the Makefile then
  # finds it made and downloads nothing.
  private def copy_downloads
    downloads.map { |download| download.split("/").first }.uniq.each do |name|
      source = File.join(@sources, name)
      raise Failure, "#{source} is missing; run bundle exec rake sources:fetch" unless File.exist?(source)

      FileUtils.cp_r(source, @root, preserve: true)
    end
  end

  # The commit +love+ is at, as files, never its working tree.
  private def export(love, target)
    FileUtils.rm_rf(target)
    FileUtils.mkdir_p(target)
    archive, status = Open3.capture2("git", "-C", love, "archive", "HEAD", binmode: true)
    raise Failure, "git archive failed in #{love}" unless status.success?

    _, error, status = Open3.capture3("tar", "-x", "-C", target, stdin_data: archive, binmode: true)
    raise Failure, "tar failed: #{error}" unless status.success?
  end

  # Runs the Makefile's +targets+ in +dir+, logging to +log+.
  private def make(dir, log, *targets)
    command = ["make", "-f", @makefile, *targets]
    say "Running make #{targets.join(' ')} in #{dir} (log: #{log})"
    File.open(log, "a") do |file|
      file.puts("$ #{command.join(' ')}")
      Open3.popen2e(*command, chdir: dir) do |stdin, output, wait|
        stdin.close
        IO.copy_stream(output, file)
        next if wait.value.success?

        file.flush
        raise Failure, "make #{targets.join(' ')} failed; the end of #{log}:\n#{File.readlines(log).last(40).join}"
      end
    end
  end

  private def git(dir, *)
    capture("git", "-C", dir, *)
  end

  private def capture(*command, chdir: Dir.pwd)
    output, status = Open3.capture2(*command, chdir:)
    raise Failure, "#{command.join(' ')} failed" unless status.success?

    output.strip
  end

  private def say(message)
    (@out || $stdout).puts(message)
  end
end
