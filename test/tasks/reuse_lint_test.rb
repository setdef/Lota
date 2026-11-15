# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/reuse_lint"

# ReuseLint runs the REUSE tool, the real one bin/setup installs, over the
# files git knows in a small repository, as AGENTS.md says rake tasks see
# files: tracked or staged, and nothing else.
class ReuseLintTest < Minitest::Test
  include TreeHelper

  HEADER = "# SPDX-FileCopyrightText: 2026 Sample Game\n# SPDX-License-Identifier: CC0-1.0\n"

  # A repository whose one file complies, committed.
  def project(dir)
    write(dir, "LICENSES/CC0-1.0.txt", "Creative Commons Legal Code\n")
    write(dir, "game.rb", HEADER)
    run!(dir, "git", "init", "--quiet", "--initial-branch=trunk")
    run!(dir, "git", "add", "--all")
    run!(dir, "git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "-m", "first")
  end

  def test_a_file_git_does_not_know_is_left_out
    in_tree do |dir|
      project(dir)
      write(dir, "scratch/out.txt", "left by another run\n")

      report = ReuseLint.new(dir).check

      assert_predicate report, :compliant?
      assert_empty report.missing
    end
  end

  def test_a_staged_file_with_no_header_fails
    in_tree do |dir|
      project(dir)
      write(dir, "level.txt", "no header\n")
      run!(dir, "git", "add", "level.txt")

      report = ReuseLint.new(dir).check

      refute_predicate report, :compliant?
      assert_equal ["level.txt"], report.missing
      assert_includes report.problems, "missing_licensing_info: level.txt"
    end
  end

  # A tracked file is checked as it is in the working tree, as reuse lint
  # checks it, not as the last commit has it.
  def test_a_tracked_file_whose_header_is_taken_out_fails
    in_tree do |dir|
      project(dir)
      write(dir, "game.rb", "puts 1\n")

      assert_equal ["game.rb"], ReuseLint.new(dir).check.missing
    end
  end

  def test_a_license_no_known_file_uses_is_unused_though_a_stray_file_uses_it
    in_tree do |dir|
      project(dir)
      write(dir, "LICENSES/MIT.txt", "MIT License\n")
      run!(dir, "git", "add", "LICENSES/MIT.txt")
      write(dir, "stray.rb", "# SPDX-FileCopyrightText: 2026 Sample Game\n# SPDX-License-Identifier: MIT\n")

      assert_includes ReuseLint.new(dir).check.problems, "unused_licenses: MIT"
    end
  end
end
