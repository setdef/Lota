# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/rubocop"

# Lota/RuleFourCondition, the RuboCop cop for rule 4 of
# doc/contributors/design/translation.md, which a game turns on with
# <tt>require: lota/rubocop</tt>. Each test runs the cop over real source
# with RuboCop's own commissioner, as <tt>rubocop</tt> does.
class RubocopTest < Minitest::Test
  def offenses(source)
    processed = RuboCop::ProcessedSource.new(source, 4.0)
    cop = RuboCop::Cop::Lota::RuleFourCondition.new
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  def assert_flagged(source, count = 1)
    found = offenses(source)

    assert_equal count, found.size, "expected #{count} offense(s) in #{source.inspect}"
    assert(found.all? { |offense| offense.message.include?("returns an Array") })
  end

  def test_each_kind_of_condition_is_flagged
    [
      "if Lota::Mouse.position; end",
      "x = 1 unless Lota::Mouse.position",
      "while Lota::Mouse.position; end",
      "begin; end until Lota::Mouse.position",
      "Lota::Mouse.position ? 1 : 2",
      "if (Lota::Mouse.position); end",
      "if x; elsif Lota::Mouse.position; end",
      "!Lota::Mouse.position",
      "not Lota::Mouse.position",
      "Lota::Mouse.position && go",
      "Lota::Mouse.position || go",
      "if ok && Lota::Mouse.position; end",
      "if !(ok || Lota::Mouse.position); end",
    ].each { |source| assert_flagged(source) }
  end

  def test_a_module_is_found_by_its_constant_or_through_lota
    [
      "::Lota::Mouse.position",
      "Lota::Mouse.position",
      "lota.mouse.position",
      "Lota.mouse.position",
    ].each { |call| assert_flagged("if #{call}; end") }
  end

  def test_the_message_names_the_method
    assert_equal ["Lota::Mouse.position returns an Array, which is always true; test its first result."],
      offenses("if lota.mouse.position; end").map { |offense| offense.message.delete_prefix("Lota/RuleFourCondition: ") }
  end

  def test_the_first_result_and_a_destructuring_are_not_flagged
    [
      "if Lota::Mouse.position.first; end",
      "saved, message = Lota::Mouse.position",
      "result = Lota::Mouse.position",
      "Lota::Mouse.position",
      "go(Lota::Mouse.position)",
      "ok && Lota::Mouse.position",
      "if Lota::Mouse.position == [true]; end",
    ].each do |source|
      assert_empty offenses(source), source
    end
  end

  def test_a_receiver_whose_type_is_unknown_is_not_flagged
    [
      "if file.position; end",
      "if Other::Mouse.position; end",
      "if lota.nothing.position; end",
      "if other.mouse.position; end",
      "if position; end",
    ].each do |source|
      assert_empty offenses(source), source
    end
  end

  def test_a_function_that_returns_one_value_is_not_flagged
    assert_empty offenses("if Lota::Mouse.x; end")
    assert_empty offenses("if Lota::Timer.time; end")
  end

  def test_every_listed_method_is_flagged_in_its_module
    RuboCop::Cop::Lota::RULE_FOUR_METHODS.each do |scope, names|
      names.each { |name| assert_flagged("if #{scope}.#{name}; end") }
    end
  end

  def test_requiring_it_enables_the_cop_by_default
    config = RuboCop::ConfigLoader.default_configuration

    assert config.for_cop("Lota/RuleFourCondition")["Enabled"]
    assert_includes RuboCop::Cop::Registry.global.names, "Lota/RuleFourCondition"
  end
end
