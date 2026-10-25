# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/sanitized_build"

class SanitizedBuildTest < Minitest::Test
  include TreeHelper

  parallelize_me!

  # A build tree whose CMake cache names +compiler+.
  def tree(root, compiler)
    write(root, "build/CMakeCache.txt", "CMAKE_C_COMPILER:FILEPATH=/usr/bin/cc\nCMAKE_CXX_COMPILER:FILEPATH=#{compiler}\n")
    SanitizedBuild.new(build: File.join(root, "build"))
  end

  def test_lib_is_where_the_tree_writes_its_extensions
    in_tree do |root|
      assert_equal File.join(root, "build/lib"), tree(root, "/usr/bin/c++").lib
    end
  end

  def test_the_runtime_is_the_one_the_trees_compiler_links
    in_tree do |root|
      runtime = tree(root, "/usr/bin/c++").runtime

      assert_equal "libclang_rt.asan_osx_dynamic.dylib", File.basename(runtime)
      assert_path_exists runtime
    end
  end

  def test_the_environment_inserts_the_runtime_with_rubys_options
    in_tree do |root|
      build = tree(root, "/usr/bin/c++")

      assert_equal({ "DYLD_INSERT_LIBRARIES" => build.runtime, "ASAN_OPTIONS" => "use_sigaltstack=0:strip_env=0" },
        build.environment)
    end
  end

  def test_an_unconfigured_tree_names_what_is_missing
    in_tree do |root|
      error = assert_raises(SanitizedBuild::Failure) { SanitizedBuild.new(build: File.join(root, "build")).runtime }
      assert_equal "#{root}/build/CMakeCache.txt is missing; configure the sanitized build first", error.message
    end
  end

  def test_a_cache_without_a_cxx_compiler_says_so
    in_tree do |root|
      write(root, "build/CMakeCache.txt", "CMAKE_C_COMPILER:FILEPATH=/usr/bin/cc\n")

      error = assert_raises(SanitizedBuild::Failure) { SanitizedBuild.new(build: File.join(root, "build")).compiler }
      assert_equal "#{root}/build/CMakeCache.txt names no C++ compiler", error.message
    end
  end

  # Clang prints the bare file name when it has no such runtime; a
  # compiler that fails is no better.
  def test_a_compiler_without_the_runtime_is_refused
    in_tree do |root|
      echo = write(root, "bin/c++", "#!/bin/sh\necho \"${1#-print-file-name=}\"\n")
      File.chmod(0o755, echo)

      error = assert_raises(SanitizedBuild::Failure) { tree(root, echo).runtime }
      assert_equal "#{echo} has no libclang_rt.asan_osx_dynamic.dylib", error.message
      assert_raises(SanitizedBuild::Failure) { tree(root, "/usr/bin/false").runtime }
    end
  end

  # The command really loads ASan into Ruby: the runtime is among the files
  # the process has mapped (lsof), and DYLD_INSERT_LIBRARIES survives for
  # child processes.
  def test_the_command_runs_tests_in_a_ruby_with_asan_loaded
    in_tree do |root|
      build = tree(root, "/usr/bin/c++")
      probe = write(root, "probe_test.rb", <<~RUBY)
        class ProbeTest < Minitest::Test
          def test_asan_is_loaded
            assert_includes IO.popen(["lsof", "-p", Process.pid.to_s, "-Fn"], &:read), #{build.runtime.dump}
            assert_includes ENV.fetch("DYLD_INSERT_LIBRARIES"), "libclang_rt.asan"
            assert_equal [#{build.lib.dump}, #{File.join(root, 'extra').dump}], $LOAD_PATH.first(2)
          end
        end
      RUBY

      output, status = Open3.capture2e(*build.command([probe], load_path: [File.join(root, "extra")]))
      assert status.success?, output
      assert_includes output, "1 runs, 5 assertions, 0 failures, 0 errors"
    end
  end
end
