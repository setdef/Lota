# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

desc "Run all tests"
task test: %w[test:ruby]

namespace :test do
  Minitest::TestTask.create(:ruby) do |t|
    t.test_globs = ["test/**/*_test.rb"]
  end
end
