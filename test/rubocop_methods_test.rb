# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/rubocop"

# The methods Lota/RuleFourCondition knows return an Array are methods
# Lota has. Many are bound from the engine, so this loads Lota with its
# extension, and is an integration test; RubocopTest runs the cop itself.
class RubocopMethodsTest < Minitest::Test
  def test_the_listed_methods_are_module_functions_that_exist_in_lota
    RuboCop::Cop::Lota::RULE_FOUR_METHODS.each do |scope, names|
      mod = Object.const_get(scope)

      names.each { |name| assert_respond_to mod, name, "#{scope}.#{name}" }
    end
    assert_includes RuboCop::Cop::Lota::RULE_FOUR_METHODS.fetch("Lota::Mouse"), "position"
  end
end
