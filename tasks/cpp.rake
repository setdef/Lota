# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require_relative "cpp_gates"
require_relative "engine_sources"
require_relative "lint"
require_relative "push_check"

# clang-tidy checks the sources the host's build compiles.
CPP_FILES = CppGates::Files.new(root: ".", platform: EngineSources.platform(RbConfig::CONFIG["host_os"]))

# The clang-format check of +files+' sources and headers, as cpp:format and
# cpp:format:fix run it, with Lota's style.
def cpp_format(files = CPP_FILES)
  CppGates::Format.new(files: files.all, style: "ext/.clang-format")
end

# The clang-tidy check of +sources+, by default all of +files+' sources, as
# cpp:tidy runs it, with Lota's settings and the engine build's
# compilation database.
def cpp_tidy(files = CPP_FILES, sources: files.sources)
  CppGates::Tidy.new(files: sources, config: "ext/.clang-tidy", compile_commands: ENGINE.compile_commands,
    headers: files.ext)
end

# The clang-tidy check of the sources only this platform compiles, as
# cpp:tidy:platform runs it.
def cpp_tidy_platform(files = CPP_FILES)
  cpp_tidy(files, sources: files.own_sources)
end

# Prints a gate's Result, and aborts the run if it failed.
def cpp_gate!(name, result)
  abort "❌ #{name} failed:\n#{result.problems.join("\n")}" unless result.ok?

  puts "✅ #{name}: #{result.checked} files, no problems"
end

namespace :cpp do
  desc "Check Lota's own C++ layout with clang-format"
  task :format do
    cpp_gate!("cpp:format", cpp_format.check)
  end

  namespace :format do
    desc "Rewrite Lota's own C++ with clang-format"
    task :fix do
      cpp_gate!("cpp:format:fix", cpp_format.fix)
    end
  end

  desc "Check Lota's own C++ with clang-tidy, every warning an error"
  task tidy: "engine:configure" do
    cpp_gate!("cpp:tidy", cpp_tidy.check)
  end

  namespace :tidy do
    # The pre-push tier runs this rather than cpp:tidy, which takes
    # minutes: the sources only this platform compiles are the ones a
    # gate on another platform cannot read, such as Objective-C++, which
    # Linux's gate leaves to macOS's.
    desc "Check with clang-tidy the C++ only this platform compiles"
    task platform: "engine:configure" do
      cpp_gate!("cpp:tidy:platform", cpp_tidy_platform.check)
    end
  end

  desc "Forbid NOLINT in Lota's own C++ except approved exceptions"
  task :no_nolint do
    Lint.load(File.expand_path("../cpp_exceptions.rb", __dir__)).enforce!(
      glob: CppGates::NOLINT_GLOB, pattern: CppGates::NOLINT, covers: CppGates.method(:covered),
      violation_name: "NOLINT in C++ files"
    )
  end
end

# The submodule the engine's configure reads LÖVE's prebuilt or buildable
# libraries from, on the platforms clang-tidy reads a build on; the
# pre-push hook fetches only vendor/love.
CPP_DEPENDENCY_SUBMODULES = {
"macos" => "vendor/love-apple-dependencies",
"linux" => "vendor/love-appimage-source",
}.freeze

namespace :cpp do
  # What the pre-push hook runs for a push that changes Lota's C++ or
  # what writes or checks it (PushCheck::CPP): the gate's NOLINT and
  # clang-format checks, then clang-tidy over the sources the commits of
  # RANGE reach (CppGates.tidied), with the engine configured first for
  # its compilation database. clang-tidy reads a Linux or macOS build, as
  # the gate does, so on Windows it says what it leaves to CI's gate.
  desc "Run the gate's C++ checks over what the commits of RANGE (default: the unpushed ones) change"
  task :changed, [:range] do |_task, args|
    range = args[:range] || red_before_green_range
    Rake::Task["cpp:no_nolint"].invoke
    Rake::Task["cpp:format"].invoke
    sources = CppGates.tidied(changed: PushCheck.changes(Dir.pwd, range), sources: CPP_FILES.sources, root: Dir.pwd)
    next puts("✅ cpp:changed: no source for clang-tidy to read") if sources.empty?

    submodule = CPP_DEPENDENCY_SUBMODULES[ENGINE_PLATFORM]
    unless submodule
      next puts("⚠️ cpp:changed: clang-tidy reads a Linux or macOS build, as the gate does; " \
        "#{sources.size} sources are left to CI's gate")
    end

    sh "git", "submodule", "update", "--init", submodule unless File.exist?(File.join(submodule, ".git"))
    Rake::Task["sources:fetch"].invoke
    Rake::Task["engine:configure"].invoke
    cpp_gate!("cpp:tidy (#{sources.size} sources)", cpp_tidy(sources:).check)
  end
end

desc "Run every C++ gate"
task cpp: %w[cpp:format cpp:no_nolint cpp:tidy]
