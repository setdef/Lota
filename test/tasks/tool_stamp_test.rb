# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/tool_stamp"

# ToolStamp records the programs extconf.rb names to CMake, in a real
# folder, and rewrites the record only when one of them is another, so
# that the extension's Makefiles, which depend on it, are configured
# again then.
class ToolStampTest < Minitest::Test
  include TreeHelper

  OLD_MISE = "/home/agent/.local/share/mise/installs"
  NEW_MISE = "/home/agent/workspaces/lota/mise/0123456789abcdef/installs"
  RUBY = "#{OLD_MISE}/ruby/4.1.0-preview1/bin/ruby".freeze

  # The description with +mise+'s cmake and ninja.
  def tools(mise, ruby: RUBY, env: {})
    paths = {
      "cmake" => "#{mise}/cmake/4.3.2/bin/cmake",
      "ninja" => "#{mise}/ninja/1.13.2/ninja",
      "ccache" => "#{mise}/ccache/4.14.2/ccache",
    }
    ToolStamp.describe(ruby:, which: paths.method(:[]), env:)
  end

  NO_LAUNCHERS = %w[C CXX OBJC OBJCXX].map { |language| "CMAKE_#{language}_COMPILER_LAUNCHER none\n" }.join.freeze

  def test_it_describes_the_ruby_and_the_cmake_and_ninja_on_path
    assert_equal "ruby #{RUBY}\ncmake #{OLD_MISE}/cmake/4.3.2/bin/cmake\nninja #{OLD_MISE}/ninja/1.13.2/ninja\n" \
      "#{NO_LAUNCHERS}", tools(OLD_MISE)
    assert_equal "ruby #{RUBY}\ncmake missing\nninja missing\n#{NO_LAUNCHERS}",
      ToolStamp.describe(ruby: RUBY, which: -> (_) {}, env: {})
  end

  # CMake's compiler launchers come from the environment, by path or by
  # name, and extconf.rb names each of them to CMake.
  def test_it_describes_each_compiler_launcher_the_environment_names
    launcher = "#{OLD_MISE}/ccache/4.14.2/ccache"
    described = tools(OLD_MISE, env: {
      "CMAKE_C_COMPILER_LAUNCHER" => launcher,
      "CMAKE_CXX_COMPILER_LAUNCHER" => "ccache",
      "CMAKE_OBJC_COMPILER_LAUNCHER" => "",
    })

    assert_includes described, "CMAKE_C_COMPILER_LAUNCHER #{launcher}\n"
    assert_includes described, "CMAKE_CXX_COMPILER_LAUNCHER #{launcher}\n"
    assert_includes described, "CMAKE_OBJC_COMPILER_LAUNCHER none\n"
    assert_includes tools(OLD_MISE, env: { "CMAKE_C_COMPILER_LAUNCHER" => "nonesuch" }),
      "CMAKE_C_COMPILER_LAUNCHER nonesuch\n"
  end

  def test_a_tree_with_no_record_gets_one
    in_tree do |dir|
      stamp = ToolStamp.new(tmp: File.join(dir, "tmp"), tools: tools(OLD_MISE))

      assert_equal :recorded, stamp.refresh
      assert_equal tools(OLD_MISE), File.read(stamp.path)
    end
  end

  def test_the_same_programs_keep_the_record_as_it_was
    in_tree do |dir|
      stamp = ToolStamp.new(tmp: File.join(dir, "tmp"), tools: tools(OLD_MISE))
      stamp.refresh
      File.utime(Time.at(0), Time.at(0), stamp.path)

      assert_equal :kept, stamp.refresh
      assert_equal Time.at(0), File.mtime(stamp.path)
    end
  end

  # The Makefile configured with the old programs is then older than the
  # record, so rake runs extconf.rb again.
  def test_a_ruby_a_ninja_or_a_ccache_that_moved_rewrites_the_record
    launcher = { "CMAKE_CXX_COMPILER_LAUNCHER" => "#{OLD_MISE}/ccache/4.14.2/ccache" }
    moved_launcher = { "CMAKE_CXX_COMPILER_LAUNCHER" => "#{NEW_MISE}/ccache/4.14.2/ccache" }
    [
      tools(OLD_MISE, ruby: RUBY.sub(OLD_MISE, NEW_MISE), env: launcher),
      tools(NEW_MISE, env: launcher),
      tools(OLD_MISE, env: moved_launcher),
      tools(OLD_MISE),
    ].each do |moved|
      in_tree do |dir|
        tmp = File.join(dir, "tmp")
        ToolStamp.new(tmp:, tools: tools(OLD_MISE, env: launcher)).refresh
        makefile = write(tmp, "x86_64-linux/lota/native/4.1.0/Makefile", "configured with the old programs")
        File.utime(Time.at(0), Time.at(0), File.join(tmp, ToolStamp::FILE))
        File.utime(Time.at(1), Time.at(1), makefile)
        stamp = ToolStamp.new(tmp:, tools: moved)

        assert_equal :recorded, stamp.refresh
        assert_equal moved, File.read(stamp.path)
        assert_operator File.mtime(stamp.path), :>, File.mtime(makefile)
      end
    end
  end
end
