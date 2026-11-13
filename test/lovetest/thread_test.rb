# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../native/native_helper"

# Runs Lövetest's love.thread tests, translated in tests/thread.rb, in a
# Ruby of their own, since their threads are Ractors (tests/thread.rb).
# test/native/lota_run_test.rb runs them again through lota run.
class ThreadLovetestTest < Minitest::Test
  include NativeHelper

  def test_lovetests_thread_tests_pass_in_a_ruby_of_their_own
    # Ruby 4.1 runs RUBYOPT's -rbundler/setup only after the command line's
    # -r (Feature #21951), so Bundler is set up before the test helper,
    # which loads Minitest.
    setup = ENV["BUNDLER_SETUP"] ? ["-r#{ENV['BUNDLER_SETUP']}"] : []
    output, status = ruby_of_its_own(*setup, "-r", File.expand_path("../test_helper", __dir__),
      File.expand_path("tests/thread.rb", __dir__))

    assert_predicate status, :success?, output
    assert_match(/^5 runs, 26 assertions, 0 failures, 0 errors, 0 skips$/, output)
    refute_match(/warning/i, output)
  end
end
