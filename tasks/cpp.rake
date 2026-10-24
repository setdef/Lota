# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "cpp_gates"
require_relative "lint"

CPP_FILES = CppGates::Files.new(root: ".")

# Prints a gate's Result, and aborts the run if it failed.
def cpp_gate!(name, result)
  abort "❌ #{name} failed:\n#{result.problems.join("\n")}" unless result.ok?

  puts "✅ #{name}: #{result.checked} files, no problems"
end

namespace :cpp do
  desc "Check Lota's own C++ layout with clang-format"
  task :format do
    cpp_gate!("cpp:format", CppGates::Format.new(files: CPP_FILES.all, style: "ext/.clang-format").check)
  end

  namespace :format do
    desc "Rewrite Lota's own C++ with clang-format"
    task :fix do
      cpp_gate!("cpp:format:fix", CppGates::Format.new(files: CPP_FILES.all, style: "ext/.clang-format").fix)
    end
  end

  desc "Check Lota's own C++ with clang-tidy, every warning an error"
  task tidy: "engine:configure" do
    tidy = CppGates::Tidy.new(files: CPP_FILES.sources, config: "ext/.clang-tidy",
      compile_commands: ENGINE.compile_commands, headers: CPP_FILES.ext)
    cpp_gate!("cpp:tidy", tidy.check)
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
