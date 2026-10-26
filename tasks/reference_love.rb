# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "open3"
require "shellwords"
require "yaml"

# The reference love: LÖVE's own executable, with Lua, built from
# vendor/love at the pinned commit, which the parity harness runs a game in
# to learn what Lota must show (Plan 001, "What correct means").
#
# It is built the way LÖVE's own CI builds its macOS app
# (vendor/love/.github/workflows/main.yml, the macOS job): the
# dependencies from love-apple-dependencies in platform/xcode, then the
# job's own "Build" and "Export Archive" commands, read from that workflow
# so that a new pin builds as LÖVE's CI then does. LÖVE's Xcode project is
# the build LÖVE supports on macOS; its CMakeLists.txt says CMake is not
# (CMakeLists.txt:35-38), and needs settings the project has added by hand
# to work at all (Plan 001, spike 3).
#
# Three things differ from LÖVE's CI, none of them in what is compiled:
#
# - The build happens in an export of vendor/love's commit under +root+,
#   so vendor/love is never changed, and the dependencies are copied from
#   vendor/love-apple-dependencies, the commit Lota links, where CI moves
#   them from a fresh clone of its main branch.
# - xcodebuild keeps its intermediate files under +root+ (-derivedDataPath)
#   rather than in ~/Library/Developer, and writes its log there.
# - The deployment target is DEPLOYMENT_TARGET, where LÖVE's project asks
#   for 10.15, because Xcode 27 refuses anything older than 12.0.
#
# When ccache is on the PATH, xcodebuild compiles through it, as Lota's
# CMake builds do on CI: CC and CXX name scripts that run Xcode's own clang
# and clang++ through ccache, LD and LDPLUSPLUS name the compilers
# themselves, so linking is unchanged, and the index store, which ccache
# cannot cache and only Xcode's editor reads, is off. LÖVE's project
# builds with clang modules, which ccache caches only in its depend mode
# with modules sloppiness (ccache's manual, "C++ modules"), so the scripts
# turn both on. They also turn on time_macros sloppiness, which ccache
# 4.14 reads as leave to ignore the time Xcode's -fbuild-session-file was
# written (src/ccache/argprocessing.cpp:1511-1514), as well as __DATE__,
# __TIME__, and __TIMESTAMP__, none of which LÖVE's sources use: Xcode
# writes that file anew in every build, so ccache would otherwise never
# find an object again.
#
# A build is skipped when the executable exists and was built from the same
# commits, Xcode, and recipe (this file).
class ReferenceLove
  # Raised when a build step fails; its output is in the log.
  class Failure < StandardError; end

  # The workflow and job whose steps the build follows.
  WORKFLOW = ".github/workflows/main.yml"
  JOB = "macOS"

  # The oldest macOS Xcode 27 builds for.
  DEPLOYMENT_TARGET = "12.0"

  # [love] The LÖVE checkout, a git repository (vendor/love).
  # [dependencies] The love-apple-dependencies checkout.
  # [root] Where the build goes (tmp/reference).
  # [out] Where progress goes; +nil+ means wherever $stdout points.
  def initialize(love:, dependencies:, root:, out: nil)
    @love = File.expand_path(love)
    @dependencies = File.expand_path(dependencies)
    @root = File.expand_path(root)
    @out = out
  end

  # The exported LÖVE source tree the build runs in.
  def source
    File.join(@root, "src")
  end

  # The love executable the build makes: the "Export Archive" step's
  # -exportPath, holding love.app.
  def executable
    File.join(source, option(ci_step("Export Archive"), "-exportPath"), "love.app/Contents/MacOS/love")
  end

  # The build's log.
  def log
    File.join(@root, "build.log")
  end

  # Builds the reference love unless it is current, and returns its
  # executable. Raises Failure if a step fails.
  def build
    if current?
      say "✅ The reference love is current: #{executable}"
      return executable
    end

    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    export_source
    copy_dependencies
    commands.each { |command| run(command) }
    File.write(stamp_file, stamp)
    say "✅ Built the reference love: #{executable}"
    executable
  end

  # The commands that build it, in order, each an Array of arguments run in
  # source: the CI job's "Build" step with this build's settings added, then
  # its "Export Archive" step.
  def commands
    [ci_step("Build") + settings, ci_step("Export Archive")]
  end

  # The build settings and options added to the "Build" step.
  def settings
    [
      "-derivedDataPath",
      File.join(@root, "derived"),
      "MACOSX_DEPLOYMENT_TARGET=#{DEPLOYMENT_TARGET}",
      *compiler_settings,
]
  end

  # The words of the CI job's step +name+, which must be one xcodebuild
  # command.
  def ci_step(name)
    # Its Linux job sets DISPLAY: :99, which YAML reads as a Symbol.
    workflow = YAML.safe_load_file(File.join(@love, WORKFLOW), permitted_classes: [Symbol])
    steps = workflow.dig("jobs", JOB, "steps")
    step = steps.find { |candidate| candidate["name"] == name } or raise Failure, "#{WORKFLOW} has no #{name} step"
    words = Shellwords.split(step.fetch("run"))
    raise Failure, "#{WORKFLOW}'s #{name} step is not one xcodebuild command" unless words.first == "xcodebuild"

    words
  end

  # Whether the executable exists and was built from what would build it
  # now.
  def current?
    File.exist?(executable) && File.exist?(stamp_file) && File.read(stamp_file) == stamp
  end

  # What the build depends on: both commits, Xcode, and this recipe.
  def stamp
    [
      "love #{git(@love, 'rev-parse', 'HEAD')}",
      "dependencies #{git(@dependencies, 'rev-parse', 'HEAD')}",
      capture("xcodebuild", "-version"),
      "recipe #{Digest::SHA256.file(__FILE__).hexdigest}",
      "ccache #{!ccache.nil?}",
    ].join("\n")
  end

  # The CC, CXX, LD, and LDPLUSPLUS settings that compile through ccache,
  # with the index store off, or none without ccache.
  def compiler_settings
    return [] unless ccache

    clang = capture("xcrun", "--find", "clang")
    clangxx = capture("xcrun", "--find", "clang++")
    [
      "CC=#{wrapper('clang', clang)}",
      "CXX=#{wrapper('clang++', clangxx)}",
      "LD=#{clang}",
      "LDPLUSPLUS=#{clangxx}",
      "COMPILER_INDEX_STORE_ENABLE=NO",
    ]
  end

  # The ccache executable on the PATH, or +nil+.
  def ccache
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "ccache") }
      .find { |path| File.executable?(path) }
  end

  private def stamp_file
    File.join(@root, "stamp")
  end

  # A script named +name+ that runs +compiler+ through ccache.
  private def wrapper(name, compiler)
    path = File.join(@root, "bin", name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~SH)
      #!/bin/sh
      CCACHE_DEPEND=1 CCACHE_SLOPPINESS="${CCACHE_SLOPPINESS:+$CCACHE_SLOPPINESS,}modules,time_macros" \\
        exec #{Shellwords.escape(ccache)} #{Shellwords.escape(compiler)} "$@"
    SH
    File.chmod(0o755, path)
    path
  end

  # The commit vendor/love is at, as files, never its working tree.
  private def export_source
    FileUtils.mkdir_p(source)
    archive, status = Open3.capture2("git", "-C", @love, "archive", "HEAD", binmode: true)
    raise Failure, "git archive failed in #{@love}" unless status.success?

    _, error, status = Open3.capture3("tar", "-x", "-C", source, stdin_data: archive, binmode: true)
    raise Failure, "tar failed: #{error}" unless status.success?
  end

  # The CI job's "Move Dependencies" step (main.yml:444-447), copying.
  private def copy_dependencies
    FileUtils.cp_r(File.join(@dependencies, "macOS/Frameworks"), File.join(source, "platform/xcode/macosx"))
    FileUtils.cp_r(File.join(@dependencies, "shared"), File.join(source, "platform/xcode"))
  end

  # The value after +flag+ in +words+.
  private def option(words, flag)
    index = words.index(flag) or raise Failure, "#{words.join(' ')} has no #{flag}"
    words.fetch(index + 1)
  end

  private def run(command)
    say "Running #{command.first(3).join(' ')} ... in #{source} (log: #{log})"
    File.open(log, "a") do |file|
      file.puts("$ #{Shellwords.join(command)}")
      Open3.popen2e(*command, chdir: source) do |stdin, output, wait|
        stdin.close
        IO.copy_stream(output, file)
        next if wait.value.success?

        file.flush
        tail = File.readlines(log).last(40).join
        raise Failure, "#{command.first(3).join(' ')} failed; the end of #{log}:\n#{tail}"
      end
    end
  end

  private def git(dir, *)
    capture("git", "-C", dir, *)
  end

  private def capture(*command)
    output, status = Open3.capture2(*command)
    raise Failure, "#{command.join(' ')} failed" unless status.success?

    output.strip
  end

  private def say(message)
    (@out || $stdout).puts(message)
  end
end
