# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"
require "json"
require "open3"

# The gates for Lota's own C++.
#
# No one reviews the native code line by line (AGENTS.md, Provenance), so
# these gates do: clang-format for layout and clang-tidy, with every warning
# an error, for everything else. They read only Lota's own files under
# ext/, never vendor/, whose code is LÖVE's (ADR 001, section 1). A gate
# with no files to check passes, so the gates run from the first commit,
# before Lota has any C++ of its own.
module CppGates
  # Extensions of the files the gates read.
  SOURCES = %w[.c .cc .cpp .cxx .m .mm].freeze
  HEADERS = %w[.h .hh .hpp .hxx].freeze

  # What cpp:no_nolint forbids, and where it looks, relative to the
  # repository.
  NOLINT = /NOLINT/
  NOLINT_GLOB = "ext/**/*{#{(SOURCES + HEADERS).join(',')}}".freeze

  # A gate's outcome: what it checked, and what it found.
  class Result < Data.define(:checked, :problems)
    # Whether the gate passes.
    def ok?
      problems.empty?
    end
  end

  # Lota's own C and C++ files: those git tracks under ext/, so a new
  # file counts once it is staged.
  class Files
    # [root] The repository root.
    # [platform] The platform the build compiles for, as EngineSources
    #   names it, or nil for every platform's sources.
    def initialize(root:, platform: nil)
      @root = File.expand_path(root)
      @platform = platform
    end

    # The platform the source at +path+ is compiled on alone, or nil for a
    # source every platform compiles: Objective-C and Objective-C++ on
    # macOS, and a source named for Linux (<tt>dialogs_linux.cpp</tt>) on
    # Linux.
    def self.platform_of(path)
      return "macos" if %w[.m .mm].include?(File.extname(path))

      "linux" if File.basename(path, ".*").end_with?("_linux")
    end

    # Every source and header, as absolute paths.
    def all
      @all ||= tracked.select { |path| (SOURCES + HEADERS).include?(File.extname(path)) }
    end

    # The sources alone, those the platform's build compiles; clang-tidy
    # reaches headers through them, and reads how to compile each from
    # the build, so another platform's source is checked on that platform.
    def sources
      all.select { |path| SOURCES.include?(File.extname(path)) && compiled_here?(path) }
    end

    private def compiled_here?(path)
      @platform.nil? || [nil, @platform].include?(self.class.platform_of(path))
    end

    # The directory the files live under.
    def ext
      File.join(@root, "ext")
    end

    private def tracked
      listed, error, status = Open3.capture3("git", "ls-files", "-z", "--", "ext", chdir: @root)
      raise ArgumentError, "git ls-files failed in #{@root}: #{error}" unless status.success?

      listed.split("\x0").map { |path| File.join(@root, path) }.select { |path| File.file?(path) }
    end
  end

  # Checks layout with clang-format, which reports every file that differs
  # from what it would write.
  class Format
    # [files] The files to check.
    # [style] The .clang-format file to check against.
    def initialize(files:, style:)
      @files = files
      @style = File.expand_path(style)
    end

    # The Result of checking every file.
    def check
      run("--dry-run", "-Werror")
    end

    # Rewrites every file in place, then checks again.
    def fix
      run("-i")
      check
    end

    private def run(*mode)
      return Result.new(checked: 0, problems: []) if @files.empty?

      output, status = Open3.capture2e("clang-format", *mode, "--style=file:#{@style}", *@files)
      Result.new(checked: @files.size, problems: status.success? ? [] : [output])
    end
  end

  # Checks with clang-tidy, using the compiler flags from CMake's
  # compile_commands.json, and treats every warning as an error.
  #
  # Each source gets a clang-tidy of its own, +jobs+ at a time. One
  # clang-tidy given every source checks them one after another on one
  # core, and each of Lota's sources parses Rice's headers, which takes
  # seconds, so the gate took minutes; run-clang-tidy.py, which LLVM ships
  # beside clang-tidy, parallelizes the same way. A header's warning is
  # found once for each source that includes it, as it was when one
  # clang-tidy checked them all.
  class Tidy
    # [files] The sources to check.
    # [config] The .clang-tidy file to check against.
    # [compile_commands] The compilation database CMake wrote.
    # [headers] Headers under this directory are checked too.
    # [jobs] How many clang-tidy processes run at once.
    def initialize(files:, config:, compile_commands:, headers:, jobs: Etc.nprocessors)
      @files = files
      @config = File.expand_path(config)
      @compile_commands = File.expand_path(compile_commands)
      @headers = File.expand_path(headers)
      @jobs = jobs
    end

    # The Result of checking every source.
    def check
      unless File.exist?(@compile_commands)
        return Result.new(checked: 0, problems: ["#{@compile_commands} is missing; configure the build first"])
      end

      unbuilt = @files - compiled
      return Result.new(checked: 0, problems: unbuilt.map { |path| "#{path} is not in #{@compile_commands}" }) if unbuilt.any?

      run
    end

    # Checks every source, +jobs+ at a time, and reports the output of
    # each that failed, in the order of +files+.
    private def run
      queue = Queue.new
      @files.each_with_index { |file, index| queue << [file, index] }
      queue.close
      outputs = Array.new(@files.size)
      Array.new([@jobs, @files.size].min) do
        Thread.new do
          while (file, index = queue.pop)
            outputs[index] = tidy(file)
          end
        end
      end.each(&:join)
      Result.new(checked: @files.size, problems: outputs.compact)
    end

    # clang-tidy's output for +file+, or nil when it found nothing.
    private def tidy(file)
      output, status = Open3.capture2e("clang-tidy", "--quiet", "-p", File.dirname(@compile_commands),
        "--config-file=#{@config}", "--warnings-as-errors=*", "--header-filter=^#{Regexp.escape(@headers)}/", file)
      status.success? ? nil : output
    end

    # The absolute paths of the files the database compiles.
    private def compiled
      JSON.parse(File.read(@compile_commands)).map do |entry|
        File.expand_path(entry.fetch("file"), entry.fetch("directory"))
      end
    end
  end
end
