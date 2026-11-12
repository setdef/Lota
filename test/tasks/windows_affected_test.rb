# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/windows_affected"
require "stringio"

# WindowsAffected answers whether a range of commits can change Lota on
# Windows, from the paths it changes and the lines it adds or removes.
class WindowsAffectedTest < Minitest::Test
  include TreeHelper

  def verdict(changes) = WindowsAffected.verdict(changes)

  def test_each_path_clause_fires_and_names_the_path
    {
      "ext/lota/native.cpp" => "ext/",
      "Gemfile" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "Gemfile.lock" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "lota.gemspec" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "mise.toml" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "tasks/windows_build.rb" => "tasks/windows*",
      ".github/windows_prepush.sh" => ".github/windows*",
      "test/native/windows_paths_test.rb" => "test/native/windows*",
      "bin/windows-shell" => "a path matching windows|mingw|win32|\\.dll",
      "lib/lota/MinGW_notes.rb" => "a path matching windows|mingw|win32|\\.dll",
      "test/fixtures/openal32.DLL" => "a path matching windows|mingw|win32|\\.dll",
    }.each do |path, clause|
      assert_equal WindowsAffected::Verdict.new(clause:, path:), verdict({ path => [] }), path
    end
    assert_nil verdict({ "doc/contributors/Windows.md" => [] }), "a path naming Windows fires only outside prose"
  end

  def test_a_changed_line_naming_windows_fires
    assert_equal WindowsAffected::Verdict.new(clause: "a changed line matching windows|mingw|win32|\\.dll",
      path: "lib/lota/boot.rb"), verdict({ "README.md" => ["plain"], "lib/lota/boot.rb" => ["if Gem.WIN32"] })
  end

  # Prose can name Windows without changing how Lota builds or runs there,
  # so its names fire nothing; a path clause still does.
  def test_prose_that_names_windows_does_not_fire
    assert_nil verdict({
      "doc/contributors/adr/014.md" => ["the Windows installer"],
      "doc/contributors/windows.md" => [],
      "README.md" => ["on Windows, run"],
      "README.rdoc" => ["MinGW"],
      "CHANGELOG.md" => ["Fixed: a DLL"],
      "LICENSES/Zlib.txt" => ["win32"],
    })
    assert_equal ".github/windows*", verdict({ ".github/windows_checks.md" => [] }).clause
    assert_equal "lib/lota/boot.rb", verdict({ "doc/a.md" => ["Windows"], "lib/lota/boot.rb" => ["mingw"] }).path
  end

  def test_a_change_that_names_nothing_of_windows_does_not_fire
    assert_nil verdict({ "lib/lota/graphics.rb" => ["def draw", "end"], "test/extension_test.rb" => [] })
    assert_nil verdict({})
  end

  def test_a_path_clause_comes_before_a_changed_line
    assert_equal "ext/", verdict({ "lib/lota/boot.rb" => ["mingw"], "ext/lota/a.cpp" => [] }).clause
  end

  def test_the_verdict_reads_as_its_clause_and_path
    assert_equal "ext/ (ext/lota/a.cpp)", WindowsAffected::Verdict.new(clause: "ext/", path: "ext/lota/a.cpp").to_s
  end

  def test_the_answer_exits_0_with_the_reason_when_windows_is_affected
    out = StringIO.new

    assert_equal 0, WindowsAffected.answer(WindowsAffected::Verdict.new(clause: "ext/", path: "ext/a.cpp"), "a..b", out:)
    assert_equal "windows:affected: a..b can change Lota on Windows: ext/ (ext/a.cpp)\n", out.string
  end

  def test_the_answer_exits_1_when_it_is_not
    out = StringIO.new

    assert_equal 1, WindowsAffected.answer(nil, "a..b", out:)
    assert_equal "windows:affected: a..b cannot change Lota on Windows\n", out.string
  end

  # The changes of a range in a real repository: each path the commits
  # change since they left OLD, with the lines they add or remove, so a
  # commit on OLD's side alone counts for nothing.
  def test_changes_are_what_the_range_adds_since_it_left_old
    in_tree do |dir|
      write(dir, "lib/a.rb", "one\n")
      write(dir, "README.md", "hello\n")
      git_stage(dir)
      commit(dir, "base")
      run!(dir, "git", "branch", "old")
      write(dir, "lib/a.rb", "one\nWin32 only\n")
      File.delete(File.join(dir, "README.md"))
      run!(dir, "git", "add", "--all")
      commit(dir, "new")
      run!(dir, "git", "tag", "new")
      run!(dir, "git", "checkout", "--quiet", "old")
      write(dir, "ext/elsewhere.cpp", "x\n")
      run!(dir, "git", "add", "--all")
      commit(dir, "elsewhere")

      changes = WindowsAffected.changes(dir, "old..new")

      assert_equal({ "lib/a.rb" => ["Win32 only"], "README.md" => ["hello"] }, changes)
      assert_equal "lib/a.rb", verdict(changes).path
    end
  end

  def test_a_range_git_cannot_read_raises
    in_tree do |dir|
      git_stage(dir)
      error = assert_raises(WindowsAffected::Failure) { WindowsAffected.changes(dir, "nothing..here") }

      assert_includes error.message, "nothing..here"
    end
  end

  def commit(dir, message)
    run!(dir, "git", "-c", "user.name=Sample", "-c", "user.email=sample@example.com",
      "commit", "--quiet", "--allow-empty", "-m", message)
  end
end
