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

  # The provenance of every commit is checked first, and always, since it
  # takes one git log and is the check its author mends first.
  def test_a_change_to_a_task_has_its_provenance_checked_and_is_linted_unit_tested_licensed_and_checked_red_before_green
    assert_equal ["provenance[#{RANGE}]", "rubocop", "test:unit", "reuse:lint", "red_before_green:unit[#{RANGE}]"],
      names(%w[tasks/gate.rake])
    assert_equal %w[tasks/gate.rake], check(%w[tasks/gate.rake]).steps[1].files
  end

  def test_a_change_to_typed_code_or_its_signatures_is_type_checked_too
    assert_includes names(%w[lib/lota.rb]), "steep"
    assert_includes names(%w[sig/lota.rbs]), "steep"
    assert_includes names(%w[Steepfile]), "steep"
    assert_includes names(%w[rbs_exceptions.rb]), "steep"
    assert_includes names(%w[Gemfile.lock]), "steep"
    refute_includes names(%w[tasks/gate.rake]), "steep"
  end

  def test_a_change_to_rubocops_settings_lotas_cops_or_the_gems_lints_every_file_git_knows
    assert_equal KNOWN, check(%w[.rubocop.yml]).steps[1].files
    assert_equal KNOWN, check(%w[lib/lota/rubocop.rb]).steps[1].files
    assert_equal KNOWN, check(%w[lib/lota/rubocop/cop.rb]).steps[1].files
    assert_equal KNOWN, check(%w[Gemfile.lock]).steps[1].files
  end

  # RuboCop given no file inspects every file under the folder, untracked
  # ones too, so with nothing for it, it does not run; the rest still do.
  def test_a_change_to_no_file_git_knows_runs_no_rubocop_but_still_the_unit_tests_and_licensing
    rest = ["provenance[#{RANGE}]", "test:unit", "reuse:lint", "red_before_green:unit[#{RANGE}]"]
    assert_equal rest, names(%w[scratch/out.txt])
    assert_equal rest, names([])
  end

  def test_the_checks_run_in_order_and_stop_at_the_first_that_fails
    out = StringIO.new
    ran = []

    passed = check(%w[tasks/gate.rake]).run(out:, clock: [0.0, 1.5].cycle) do |step|
      ran << step.name
      step.name != "test:unit"
    end

    refute passed
    assert_equal ["provenance[#{RANGE}]", "rubocop", "test:unit"], ran
    assert_includes out.string, "push_check: rubocop (1 files)\npush_check: rubocop passed in 1.5s\n"
    assert_includes out.string, "push_check: test:unit failed in 1.5s"
  end

  CPP = "cpp:changed[#{RANGE}]"

  # The gate's clang-format, NOLINT, and clang-tidy checks refuse what
  # the push brings to Lota's C++, written or generated, before it lands:
  # on 2026-11-19 a generator change made clang-tidy fail on the
  # generated bindings, and an edit to native_test.cpp failed
  # clang-format, both after the push.
  def test_a_change_to_lotas_cpp_or_what_writes_or_checks_it_and_nothing_else_gets_the_cpp_checks_last
    %w[
      ext/lota/native/generated/audio.cpp
      ext/lota/native/generated/bindings.hpp
      ext/lota/native_test/native_test.cpp
      ext/lota/native/binding.hpp
      ext/lota/native_test/offline.mm
      tasks/bindings/generator.rb
      ext/.clang-tidy
      ext/.clang-format
      cpp_exceptions.rb
      tasks/cpp_gates.rb
      tasks/cpp.rake
      tasks/lint.rb
    ].each do |path|
      assert_equal CPP, names([path]).last, path
    end
    refute_includes names(%w[lib/lota.rb tasks/gate.rake ext/lota/extconf.rb README.md]), CPP
  end

  # The hook asks mise for the C++ tools only when a push needs them, so
  # a push that changes no C++ waits for no C++ toolchain.
  def test_only_the_cpp_checks_ask_for_the_cpp_tools
    steps = check(%w[ext/lota/native/audio.cpp lib/lota.rb]).steps
    assert_equal %w[cmake ninja pipx:clang-format pipx:clang-tidy], steps.last.tools
    assert(steps[0...-1].all? { |step| step.tools.empty? })
  end

  def test_under_the_hooks_mise_a_step_with_tools_runs_in_a_mise_that_has_them
    step = check(%w[ext/lota/native/audio.cpp]).steps.last
    env = { "LOTA_UNDER_MISE" => "1", "MISE_ENABLE_TOOLS" => "ruby,uv" }

    assert_equal [
      { "MISE_ENABLE_TOOLS" => "ruby,uv,cmake,ninja,pipx:clang-format,pipx:clang-tidy" },
      ["mise", "x", "--", "bundle", "exec", "rake", CPP],
], PushCheck.command(step, env)
    assert_nil PushCheck.command(step, {})
    assert_nil PushCheck.command(check([]).steps.first, env)
  end
end
