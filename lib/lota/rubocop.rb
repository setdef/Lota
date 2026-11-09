# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubocop"
require_relative "rubocop/rule_four_methods"
require_relative "rubocop/rule_four_condition"

# Lota's RuboCop extension, which a game turns on in its +.rubocop.yml+:
#
#   require: lota/rubocop
#
# Requiring it adds the cops of the Lota department and their default
# configuration (rubocop/default.yml) to RuboCop's, as RuboCop's own
# extensions do, so +require+ is all a game writes. See
# RuboCop::Cop::Lota::RuleFourCondition.
RuboCop::ConfigLoader.inject_defaults!(File.join(__dir__.to_s, "rubocop", "default.yml"))
