# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "red_before_green"

# The test files whose tests red_before_green checks: test:ruby's, and the
# parity harness's unit tests (PARITY_UNITS in tasks/test.rake). Tests in
# test/sanitizers need the sanitized build, and the parity games the
# reference love, so they go unchecked.
def red_before_green_suites = TEST_SUITES.fetch(:ruby) + PARITY_UNITS

# The commits red_before_green checks when given none: those not yet on
# origin's trunk, or else HEAD alone.
def red_before_green_range
  unpushed, status = Open3.capture2e("git", "rev-list", "origin/trunk..HEAD")
  (status.success? && !unpushed.empty?) ? "origin/trunk..HEAD" : "HEAD^..HEAD"
end

# Checks the commits of +range+ with +checker+, and fails unless each
# passes.
def red_before_green(checker, range)
  failed = checker.check_range(range).reject(&:passed?)
  return puts("red_before_green: every test checked was seen failing first") if failed.empty?

  abort "red_before_green: #{failed.size} commit(s) add or change a test that passes against the parent, " \
    "or have a malformed #{RedBeforeGreen::TRAILER} trailer; make each test fail without its change, or, " \
    "for a commit that changes no behavior, add the trailer #{RedBeforeGreen::TRAILER}: none (reason)"
end

desc "Check that each test the commits of RANGE (default: the unpushed ones) add or change fails against " \
  "each commit's parent's lib/ and ext/"
task :red_before_green, [:range] => :compile do |_task, args|
  red_before_green(RedBeforeGreen.new(root: Dir.pwd, suites: red_before_green_suites,
    compile: %w[bundle exec rake compile]), args[:range] || red_before_green_range)
end

namespace :red_before_green do
  # The pre-push hook's part (rake push_check): the unit tests load no
  # native code, so it builds nothing and runs alike on every system,
  # and the trailers of every commit are checked too. CI's pre-push tier
  # runs red_before_green over every commit pushed to trunk.
  desc "Check, as red_before_green does but building nothing, the unit tests the commits of RANGE add or change"
  task :unit, [:range] do |_task, args|
    red_before_green(RedBeforeGreen.new(root: Dir.pwd, suites: UNIT_TESTS, compile: nil, prelude: UNIT_PRELUDE,
      outside: "not a unit test, so CI's pre-push tier checks it (rake red_before_green)"),
      args[:range] || red_before_green_range)
  end
end
