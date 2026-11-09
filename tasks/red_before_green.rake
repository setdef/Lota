# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "red_before_green"

# The commits red_before_green checks when given none: those not yet on
# origin's trunk, or else HEAD alone.
def red_before_green_range
  unpushed, status = Open3.capture2e("git", "rev-list", "origin/trunk..HEAD")
  (status.success? && !unpushed.empty?) ? "origin/trunk..HEAD" : "HEAD^..HEAD"
end

desc "Check that each test the commits of RANGE (default: the unpushed ones) add or change fails against " \
  "each commit's parent's lib/ and ext/"
task :red_before_green, [:range] => :compile do |_task, args|
  checker = RedBeforeGreen.new(root: Dir.pwd, suites: TEST_SUITES.fetch(:ruby), compile: %w[bundle exec rake compile])
  reports = checker.check_range(args[:range] || red_before_green_range)
  failed = reports.reject(&:passed?)
  next puts("red_before_green: every test checked was seen failing first") if failed.empty?

  abort "red_before_green: #{failed.size} commit(s) add or change a test that passes against the parent, " \
    "or have a malformed #{RedBeforeGreen::TRAILER} trailer; make each test fail without its change, or, " \
    "for a commit that changes no behavior, add the trailer #{RedBeforeGreen::TRAILER}: none (reason)"
end
