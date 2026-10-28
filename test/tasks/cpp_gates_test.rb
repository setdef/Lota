# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "stringio"
require_relative "../../tasks/cmake_build"
require_relative "../../tasks/cpp_gates"
require_relative "../../tasks/lint"

# Each gate runs against the repository's real configuration, on a good
# file and a deliberately bad one, so weakening a configuration or a gate
# fails here.
class CppGatesTest < Minitest::Test
  include TreeHelper

  # Each test builds its own tree and passes absolute paths, so the CMake
  # and clang runs can overlap.
  parallelize_me!

  STYLE = File.join(ROOT, "ext/.clang-format")
  TIDY = File.join(ROOT, "ext/.clang-tidy")
  PLATFORM = File.join(ROOT, "ext/lota/cmake/Platform.cmake")
  WARNINGS = File.join(ROOT, "ext/lota/cmake/LotaWarnings.cmake")

  GOOD = <<~CPP
    #include <cstdio>

    int main() {
      std::puts("ok");
      return 0;
    }
  CPP

  # clang-tidy: a null dereference (clang-analyzer) through a literal 0
  # (modernize-use-nullptr).
  UNTIDY = <<~CPP
    int main() {
      int *pointer = 0;
      return *pointer;
    }
  CPP

  # clang-format: everything on one line, with stray spaces.
  UNFORMATTED = "int  main( ){return 0;}\n"

  # -Wextra: an unused parameter.
  WARNS = "int probe(int unused) { return 0; }\n"

  def files(root) = CppGates::Files.new(root:)

  def test_files_lists_only_staged_c_and_cpp_under_ext
    in_tree do |root|
      %w[ext/a.cpp ext/b.hpp ext/c.mm ext/d.c ext/e.h ext/notes.txt ext/CMakeLists.txt src/f.cpp].each do |path|
        write(root, path)
      end
      git_stage(root)
      write(root, "ext/unstaged.cpp")

      assert_equal(%w[ext/a.cpp ext/b.hpp ext/c.mm ext/d.c ext/e.h].map { |path| File.join(root, path) }, files(root).all)
      assert_equal(%w[ext/a.cpp ext/c.mm ext/d.c].map { |path| File.join(root, path) }, files(root).sources)
      assert_equal File.join(root, "ext"), files(root).ext
    end
  end

  def test_files_on_a_platform_leaves_out_another_platforms_sources
    in_tree do |root|
      %w[ext/a.cpp ext/b_linux.cpp ext/c.mm ext/d.m ext/e_linux.hpp].each { |path| write(root, path) }
      git_stage(root)

      macos = CppGates::Files.new(root:, platform: "macos")
      linux = CppGates::Files.new(root:, platform: "linux")
      assert_equal(%w[ext/a.cpp ext/c.mm ext/d.m].map { |path| File.join(root, path) }, macos.sources)
      assert_equal(%w[ext/a.cpp ext/b_linux.cpp].map { |path| File.join(root, path) }, linux.sources)
      assert_equal macos.all, linux.all
    end
  end

  def test_files_skips_a_staged_file_deleted_from_the_tree
    in_tree do |root|
      write(root, "ext/gone.cpp")
      git_stage(root)
      File.delete(File.join(root, "ext/gone.cpp"))

      assert_empty files(root).all
    end
  end

  def test_files_raises_outside_a_git_repository
    in_tree do |root|
      error = assert_raises(ArgumentError) { files(root).all }
      assert_includes error.message, "not a git repository"
    end
  end

  def test_format_passes_with_no_files
    result = CppGates::Format.new(files: [], style: STYLE).check

    assert_predicate result, :ok?
    assert_equal 0, result.checked
  end

  def test_format_passes_a_formatted_file
    in_tree do |root|
      result = CppGates::Format.new(files: [write(root, "ext/good.cpp", GOOD)], style: STYLE).check

      assert_predicate result, :ok?
      assert_equal 1, result.checked
    end
  end

  def test_format_fails_an_unformatted_file
    in_tree do |root|
      bad = write(root, "ext/bad.cpp", UNFORMATTED)
      result = CppGates::Format.new(files: [bad], style: STYLE).check

      refute_predicate result, :ok?
      assert_includes result.problems.join, "bad.cpp:1"
      assert_includes result.problems.join, "-Wclang-format-violations"
      assert_equal UNFORMATTED, File.read(bad)
    end
  end

  def test_format_fix_rewrites_the_file
    in_tree do |root|
      bad = write(root, "ext/bad.cpp", UNFORMATTED)
      result = CppGates::Format.new(files: [bad], style: STYLE).fix

      assert_predicate result, :ok?
      assert_equal "int main() { return 0; }\n", File.read(bad)
    end
  end

  # A CMake project set up as ext/lota's is, that compiles +source+ with
  # Lota's warning flags and finds headers under vendor/, and the
  # CMakeBuild for it.
  def project(root, source)
    write(root, "CMakeLists.txt", <<~CMAKE)
      cmake_minimum_required(VERSION 3.25)
      include(#{PLATFORM})
      project(probe CXX)
      set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
      include(#{WARNINGS})
      add_library(probe STATIC ext/probe.cpp)
      target_include_directories(probe PRIVATE vendor)
      lota_strict_warnings(probe)
    CMAKE
    write(root, "ext/probe.cpp", source)
    CMakeBuild.new(source: root, build: File.join(root, "build"), args: %w[-G Ninja], out: StringIO.new)
  end

  def tidy(root, cmake, files: [File.join(root, "ext/probe.cpp")])
    CppGates::Tidy.new(files:, config: TIDY, compile_commands: cmake.compile_commands, headers: File.join(root, "ext"))
  end

  def test_tidy_passes_with_no_files
    in_tree do |root|
      cmake = project(root, GOOD)
      cmake.configure
      result = tidy(root, cmake, files: []).check

      assert_predicate result, :ok?
      assert_equal 0, result.checked
    end
  end

  def test_tidy_fails_without_a_compilation_database
    in_tree do |root|
      result = tidy(root, project(root, GOOD)).check

      refute_predicate result, :ok?
      assert_match(/compile_commands\.json is missing; configure the build first/, result.problems.join)
    end
  end

  def test_tidy_fails_a_source_the_build_does_not_compile
    in_tree do |root|
      cmake = project(root, GOOD)
      cmake.configure
      stray = write(root, "ext/stray.cpp", GOOD)
      result = tidy(root, cmake, files: [stray]).check

      refute_predicate result, :ok?
      assert_equal ["#{stray} is not in #{cmake.compile_commands}"], result.problems
    end
  end

  def test_tidy_passes_a_clean_file
    in_tree do |root|
      cmake = project(root, GOOD)
      cmake.configure
      result = tidy(root, cmake).check

      assert result.ok?, result.problems.join
      assert_equal 1, result.checked
    end
  end

  def test_tidy_fails_a_file_with_warnings
    in_tree do |root|
      cmake = project(root, UNTIDY)
      cmake.configure
      result = tidy(root, cmake).check

      refute_predicate result, :ok?
      assert_includes result.problems.join, "error: use nullptr [modernize-use-nullptr,-warnings-as-errors]"
      assert_includes result.problems.join, "[clang-analyzer-core.NullDereference,-warnings-as-errors]"
    end
  end

  # Each source gets a clang-tidy of its own, several at once, and every
  # source that fails is reported, in the order given.
  def test_tidy_checks_each_source_and_reports_every_failure_in_order
    in_tree do |root|
      cmake = project(root, UNTIDY)
      write(root, "ext/clean.cpp", GOOD)
      write(root, "ext/second.cpp", UNTIDY.sub("main", "second"))
      File.write(File.join(root, "CMakeLists.txt"),
        File.read(File.join(root, "CMakeLists.txt")).sub("ext/probe.cpp)", "ext/probe.cpp ext/clean.cpp ext/second.cpp)"))
      cmake.configure
      sources = %w[probe clean second].map { |name| File.join(root, "ext/#{name}.cpp") }
      result = CppGates::Tidy.new(files: sources, config: TIDY, compile_commands: cmake.compile_commands,
        headers: File.join(root, "ext"), jobs: 2).check

      assert_equal 3, result.checked
      assert_equal 2, result.problems.size
      assert_includes result.problems.first, "probe.cpp:2:"
      assert_includes result.problems.last, "second.cpp:2:"
      refute_includes result.problems.join, "clean.cpp"
    end
  end

  def test_tidy_checks_headers_under_ext_only
    in_tree do |root|
      write(root, "ext/probe.hpp", "inline int *probe() { return 0; }\n")
      write(root, "vendor/other.hpp", "inline int *other() { return 0; }\n")
      cmake = project(root, "#include \"probe.hpp\"\n#include <other.hpp>\n" \
        "int main() { return (probe() == other()) ? 1 : 0; }\n")
      cmake.configure
      problems = tidy(root, cmake).check.problems.join

      assert_includes problems, "ext/probe.hpp:1:30: error: use nullptr"
      refute_includes problems, "other.hpp"
    end
  end

  def test_strict_warnings_build_a_clean_file
    in_tree do |root|
      cmake = project(root, "int probe(int used) { return used; }\n")
      cmake.configure
      cmake.build

      assert_path_exists File.join(root, "build", "libprobe.a")
    end
  end

  def test_strict_warnings_fail_the_build_on_a_warning
    in_tree do |root|
      cmake = project(root, WARNS)
      out = StringIO.new
      cmake.instance_variable_set(:@out, out)
      cmake.configure

      assert_raises(CMakeBuild::Failure) { cmake.build }
      # Clang's words, and GCC's, which quotes with ‘ and ’ in a UTF-8 locale.
      assert_match(/error: unused parameter [‘']unused[’'] \[-Werror(,-W|=)unused-parameter\]/, out.string)
    end
  end
end

# cpp:no_nolint reads paths relative to the repository, so these tests
# change directory and run one at a time.
class CppNoNolintTest < Minitest::Test
  include TreeHelper

  def test_no_nolint_finds_nolint_outside_exceptions
    in_tree do |root|
      write(root, "ext/lota/a.cpp", "int a = 0; // NOLINT\n")
      write(root, "ext/lota/b.hpp", "// NOLINTNEXTLINE(readability-magic-numbers)\nint b = 7;\n")
      write(root, "ext/lota/c.txt", "NOLINT\n")
      write(root, "vendor/d.cpp", "// NOLINT\n")
      exceptions = write(root, "cpp_exceptions.rb", "")

      found = Dir.chdir(root) { Lint.load(exceptions).violations(glob: CppGates::NOLINT_GLOB, pattern: CppGates::NOLINT) }
      expected = [
        "  ext/lota/a.cpp:1: int a = 0; // NOLINT",
        "  ext/lota/b.hpp:1: // NOLINTNEXTLINE(readability-magic-numbers)",
      ]
      assert_equal expected, found.sort
    end
  end

  def test_no_nolint_allows_an_approved_exception
    in_tree do |root|
      write(root, "ext/lota/a.cpp", "int a = 0; // NOLINT\n")
      exceptions = write(root, "cpp_exceptions.rb", "allow 'ext/lota/a.cpp', line: 1, reason: 'test'\n")

      found = Dir.chdir(root) { Lint.load(exceptions).violations(glob: CppGates::NOLINT_GLOB, pattern: CppGates::NOLINT) }
      assert_empty found
    end
  end
end
