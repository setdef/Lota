# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/test_files"
require "rake"

# A test task's run is a process of its own, and when a signal ends it,
# as the kernel's out-of-memory killer ends a process, the task's failure
# names the signal, which is the one fact left to tell why the run's
# output stopped.
class TestFilesRunTest < Minitest::Test
  include TreeHelper

  def failure_of(test)
    previous = Rake.application
    Rake.application = Rake::Application.new
    TestFiles::Task.create(:probe) { |t| t.test_globs = %w[test/*_test.rb] }
    outer = ENV.delete("TEST")
    in_tree do |root|
      write(root, "test/probe_test.rb", test)
      Dir.chdir(root) { assert_raises(RuntimeError) { Rake::Task[:probe].invoke }.message }
    end
  ensure
    ENV["TEST"] = outer
    Rake.application = previous
  end

  def test_a_run_a_signal_ends_names_the_signal
    skip "Windows ends a process with no signal" if Gem.win_platform?

    assert_match(/\ACommand was ended by SIGKILL \(signal 9\): \[.* -e .*probe_test\.rb.*\]\z/,
      failure_of("Process.kill(:KILL, Process.pid)\n"))
  end
end
