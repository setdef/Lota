# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's love.graphics tests, translated in tests/graphics.rb, in
# the test suite's own process. test/native/lota_run_test.rb runs them
# again through lota run.
require_relative "../test_helper"
require_relative "tests/graphics"
