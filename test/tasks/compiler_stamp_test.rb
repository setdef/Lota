# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/compiler_stamp"
require "stringio"

# CompilerStamp records the compilers that built tmp/, and removes tmp/
# once when they change, in a real folder.
class CompilerStampTest < Minitest::Test
  include TreeHelper

  GCC13 = "CC /usr/bin/gcc-13 gcc (Ubuntu 13.3.0) 13.3.0\nCXX /usr/bin/g++-13 g++ (Ubuntu 13.3.0) 13.3.0\n"
  GCC15 = "CC /usr/bin/gcc-15 gcc (Ubuntu 15.2.0) 15.2.0\nCXX /usr/bin/g++-15 g++ (Ubuntu 15.2.0) 15.2.0\n"

  def refresh(tmp, compilers)
    out = StringIO.new
    [CompilerStamp.new(tmp:, compilers:, out:).refresh, out.string]
  end

  def test_a_tree_with_no_record_keeps_what_it_built_and_gets_one
    in_tree do |dir|
      tmp = File.join(dir, "tmp")
      built = write(tmp, "dependencies/dependencies.stamp", "built")

      assert_equal :recorded, refresh(tmp, GCC13).first
      assert_path_exists built
      assert_equal GCC13, File.read(File.join(tmp, CompilerStamp::FILE))
    end
  end

  def test_the_same_compilers_keep_the_tree
    in_tree do |dir|
      tmp = File.join(dir, "tmp")
      refresh(tmp, GCC13)
      built = write(tmp, "engine/CMakeCache.txt", "cache")

      assert_equal [:kept, ""], refresh(tmp, GCC13)
      assert_path_exists built
    end
  end

  def test_other_compilers_remove_the_tree_once
    in_tree do |dir|
      tmp = File.join(dir, "tmp")
      refresh(tmp, GCC13)
      built = write(tmp, "engine/CMakeCache.txt", "cache")

      outcome, said = refresh(tmp, GCC15)

      assert_equal :removed, outcome
      assert_includes said, "built with other compilers"
      refute_path_exists built
      assert_equal GCC15, File.read(File.join(tmp, CompilerStamp::FILE))
      assert_equal :kept, refresh(tmp, GCC15).first
    end
  end

  def test_the_description_names_each_compiler_where_it_is_and_its_version
    in_tree do |dir|
      gcc = write(dir, "bin/gcc")
      which = -> (name) { { "gcc" => gcc, "c++" => nil }[name] }
      version = -> (command) { "version of #{command.join(' ')}" }

      described = CompilerStamp.describe({ "CC" => "gcc -m64" }, which:, version:)

      assert_equal "CC #{File.realpath(gcc)} version of #{gcc} -m64\nCXX missing\n", described
    end
  end

  def test_the_version_is_the_first_line_a_real_compiler_prints
    assert_match(/\d+\.\d+/, CompilerStamp.version(["ruby"]))
    assert_equal "", CompilerStamp.version(["/nonexistent/cc"])
  end
end
