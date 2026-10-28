# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "stringio"
require_relative "../../tasks/cmake_build"

class CMakeBuildTest < Minitest::Test
  include TreeHelper

  # Each test evaluates its own tree, so the CMake runs can overlap.
  parallelize_me!

  def project(root, source)
    write(root, "src/CMakeLists.txt", <<~CMAKE)
      cmake_minimum_required(VERSION 3.25)
      project(probe CXX)
      set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
      add_library(probe STATIC probe.cpp)
    CMAKE
    write(root, "src/probe.cpp", source)
    out = StringIO.new
    [CMakeBuild.new(source: File.join(root, "src"), build: File.join(root, "build"), args: %w[-G Ninja], out:), out]
  end

  def test_configure_writes_the_compilation_database
    in_tree do |root|
      cmake, out = project(root, "int probe() { return 1; }\n")
      cmake.configure

      assert_equal File.join(root, "build", "compile_commands.json"), cmake.compile_commands
      assert_path_exists cmake.compile_commands
      assert_includes out.string, "Build files have been written to"
    end
  end

  def test_build_compiles_the_project
    in_tree do |root|
      cmake, out = project(root, "int probe() { return 1; }\n")
      cmake.configure
      cmake.build

      assert_path_exists File.join(root, "build", "libprobe.a")
      assert_includes out.string, "Linking CXX static library libprobe.a"
    end
  end

  def test_build_raises_after_printing_the_compiler_error
    in_tree do |root|
      cmake, out = project(root, "int probe() { return undeclared; }\n")
      cmake.configure

      error = assert_raises(CMakeBuild::Failure) { cmake.build }
      assert_match(/\Acmake --build .*build failed \(its output is above\)\z/, error.message)
      # Clang's words, and GCC's, which quotes with ‘ and ’ in a UTF-8 locale.
      assert_match(/use of undeclared identifier 'undeclared'|[‘']undeclared[’'] was not declared in this scope/,
        out.string)
    end
  end

  def test_configure_raises_when_cmake_fails
    in_tree do |root|
      cmake, out = project(root, "")
      write(root, "src/CMakeLists.txt", "message(FATAL_ERROR \"broken project\")\n")

      assert_raises(CMakeBuild::Failure) { cmake.configure }
      assert_includes out.string, "broken project"
    end
  end
end
