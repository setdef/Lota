# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

# What each suite runs. test/sanitizers holds the tests that deliberately
# corrupt memory, which only the sanitized build may run; every other test
# runs in test:ruby. test/native and test/lovetest, the translated Lövetest
# tests, run in both, so the window and the renderer run under the
# sanitizers too.
TEST_SUITES = {
  ruby: %w[test/*_test.rb test/native/**/*_test.rb test/lovetest/**/*_test.rb test/tasks/**/*_test.rb],
  native: %w[test/native/**/*_test.rb test/lovetest/**/*_test.rb test/sanitizers/**/*_test.rb],
}.freeze

# test:ruby includes a test that runs test:native (test/tasks/rake_tasks_test.rb),
# so rake test runs both.
desc "Run all tests, test:native among them"
task test: %w[test:ruby]

namespace :test do
  Minitest::TestTask.create(:ruby) do |t|
    t.test_globs = TEST_SUITES.fetch(:ruby)
  end
  task ruby: :compile

  desc "Run the native tests against Lota::Native built with ASan and UBSan"
  task native: %w[compile compile:sanitized] do
    sh(*SANITIZED.command(Dir[*TEST_SUITES.fetch(:native)].sort, load_path: %w[lib test]))
  end
end
