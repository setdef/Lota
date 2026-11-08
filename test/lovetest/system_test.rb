# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's love.system tests, translated in tests/system.rb, in the test suite's own process.
# test/native/lota_run_test.rb runs them again through lota run.
require_relative "../test_helper"
require_relative "tests/system"
require_relative "../native/native_helper"
require_relative "../native/focus_for_tests"

SystemTest.prepend(FocusForTests)
