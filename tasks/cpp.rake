# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require_relative "cpp_gates"
require_relative "engine_sources"
require_relative "lint"

# clang-tidy checks the sources the host's build compiles.
CPP_FILES = CppGates::Files.new(root: ".", platform: EngineSources.platform(RbConfig::CONFIG["host_os"]))

# The clang-format check of +files+' sources and headers, as cpp:format and
# cpp:format:fix run it, with Lota's style.
def cpp_format(files = CPP_FILES)
  CppGates::Format.new(files: files.all, style: "ext/.clang-format")
end

# The clang-tidy check of +files+' sources, as cpp:tidy runs it, with
# Lota's settings and the engine build's compilation database.
def cpp_tidy(files = CPP_FILES)
  CppGates::Tidy.new(files: files.sources, config: "ext/.clang-tidy", compile_commands: ENGINE.compile_commands,
    headers: files.ext)
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

  desc "Forbid NOLINT in Lota's own C++ except approved exceptions"
  task :no_nolint do
    Lint.load(File.expand_path("../cpp_exceptions.rb", __dir__)).enforce!(
      glob: CppGates::NOLINT_GLOB, pattern: CppGates::NOLINT, violation_name: "NOLINT in C++ files"
    )
  end
end

desc "Run every C++ gate"
task cpp: %w[cpp:format cpp:no_nolint cpp:tidy]
