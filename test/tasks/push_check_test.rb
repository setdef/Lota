# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/push_check"
require "stringio"

# PushCheck decides which checks a push gets from the paths its commits
# change, and runs them in order, stopping at the first that fails.
class PushCheckTest < Minitest::Test
  RANGE = "aaa..bbb"
  KNOWN = %w[lib/lota.rb lib/lota/rubocop.rb sig/lota.rbs tasks/gate.rake README.md].freeze

  def check(changed) = PushCheck.new(range: RANGE, changed:, known: KNOWN)

  def names(changed) = check(changed).steps.map(&:name)

  def test_a_change_to_a_task_is_linted_unit_tested_licensed_and_checked_red_before_green
    assert_equal ["rubocop", "test:unit", "reuse:lint", "red_before_green:unit[#{RANGE}]"], names(%w[tasks/gate.rake])
    assert_equal %w[tasks/gate.rake], check(%w[tasks/gate.rake]).steps.first.files
  end

  def test_a_change_to_typed_code_or_its_signatures_is_type_checked_too
    assert_includes names(%w[lib/lota.rb]), "steep"
    assert_includes names(%w[sig/lota.rbs]), "steep"
    assert_includes names(%w[Steepfile]), "steep"
    refute_includes names(%w[tasks/gate.rake]), "steep"
  end

  def test_a_change_to_rubocops_settings_or_lotas_cops_lints_every_file_git_knows
    assert_equal KNOWN, check(%w[.rubocop.yml]).steps.first.files
    assert_equal KNOWN, check(%w[lib/lota/rubocop.rb]).steps.first.files
  end

  # RuboCop given no file inspects every file under the folder, untracked
  # ones too, so with nothing for it, it does not run; the rest still do.
  def test_a_change_to_no_file_git_knows_runs_no_rubocop_but_still_the_unit_tests_and_licensing
    assert_equal ["test:unit", "reuse:lint", "red_before_green:unit[#{RANGE}]"], names(%w[scratch/out.txt])
    assert_equal ["test:unit", "reuse:lint", "red_before_green:unit[#{RANGE}]"], names([])
  end

  def test_the_checks_run_in_order_and_stop_at_the_first_that_fails
    out = StringIO.new
    ran = []

    passed = check(%w[tasks/gate.rake]).run(out:, clock: [0.0, 1.5].cycle) do |step|
      ran << step.name
      step.name != "test:unit"
    end

    refute passed
    assert_equal %w[rubocop test:unit], ran
    assert_includes out.string, "push_check: rubocop (1 files)\npush_check: rubocop passed in 1.5s\n"
    assert_includes out.string, "push_check: test:unit failed in 1.5s"
  end
end
