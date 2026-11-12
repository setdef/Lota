# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

# Which test files a test task runs. TEST, as Rake's own TestTask reads
# it, names files or globs, separated by commas, to run in place of the
# task's own; Minitest's TestTask, which Lota's test tasks are, never
# reads it, so without this rake test TEST=one_test.rb would run every
# test. A name that matches no file stops the task, rather than run
# nothing and pass.
module TestFiles
  def self.of(globs, env: ENV)
    named = env.fetch("TEST", "").split(",")
    return Dir[*globs].sort if named.empty?

    missing = named.select { |name| Dir[name].empty? }
    raise ArgumentError, "TEST names no test file: #{missing.join(', ')}" unless missing.empty?

    Dir[*named].sort
  end

  # A Minitest::TestTask that runs the files TEST names, when it names
  # any. It reads TEST when it runs, not when the Rakefile loads.
  class Task < Minitest::TestTask
    def make_test_cmd(**option)
      super(**option, path: option.fetch(:path) { TestFiles.of(test_globs) })
    end
  end
end
