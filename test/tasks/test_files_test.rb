# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/test_files"
require_relative "../unit_guard"
require "rake"

# TEST picks the files a test task runs, as Rake's own TestTask documents
# it, and rake test:unit's guard stops a unit test that reaches past Ruby.
class TestFilesTest < Minitest::Test
  include TreeHelper

  def in_test_tree
    in_tree do |root|
      %w[a_test.rb b_test.rb c_test.rb].each { |name| write(root, "test/#{name}") }
      Dir.chdir(root) { yield root }
    end
  end

  def test_without_test_a_task_runs_its_globs
    in_test_tree do
      assert_equal %w[test/a_test.rb test/b_test.rb test/c_test.rb], TestFiles.of(%w[test/*_test.rb], env: {})
      assert_equal %w[test/a_test.rb test/b_test.rb test/c_test.rb], TestFiles.of(%w[test/*_test.rb], env: { "TEST" => "" })
    end
  end

  def test_test_names_files_or_globs_separated_by_commas_in_place_of_the_tasks
    in_test_tree do
      assert_equal %w[test/b_test.rb], TestFiles.of(%w[test/*_test.rb], env: { "TEST" => "test/b_test.rb" })
      assert_equal %w[test/a_test.rb test/c_test.rb],
        TestFiles.of(%w[test/b_test.rb], env: { "TEST" => "test/c_test.rb,test/a*_test.rb" })
    end
  end

  def test_a_name_that_matches_no_file_stops_the_task
    in_test_tree do
      error = assert_raises(ArgumentError) { TestFiles.of(%w[test/*_test.rb], env: { "TEST" => "test/a_test.rb,test/gone_test.rb" }) }
      assert_equal "TEST names no test file: test/gone_test.rb", error.message
    end
  end

  # The command a task runs requires exactly the files TEST names, read
  # as the task runs, so one Rakefile serves every TEST.
  def test_the_command_requires_only_the_files_test_names
    previous = Rake.application
    Rake.application = Rake::Application.new
    task = TestFiles::Task.create(:probe) { |t| t.test_globs = %w[test/*_test.rb] }
    outer = ENV.delete("TEST")
    in_test_tree do
      everything = task.make_test_cmd
      ENV["TEST"] = "test/b_test.rb"
      one = task.make_test_cmd

      assert_equal %w[test/a_test.rb test/b_test.rb test/c_test.rb], everything.scan(%r{test/\w+_test\.rb}).sort
      assert_equal %w[test/b_test.rb], one.scan(%r{test/\w+_test\.rb})
    end
  ensure
    ENV["TEST"] = outer
    Rake.application = previous
  end

  # A test run refuses the message boxes no one can answer: on Linux and
  # macOS it loads liblota_dialogs into every program, after a sanitizer's
  # runtime.
  def test_a_linux_run_preloads_the_library_that_refuses_dialogs_after_a_sanitizers_runtime
    in_tree do |root|
      library = write(root, "liblota_dialogs.so")

      assert_equal({ "LD_PRELOAD" => library }, TestFiles.environment(env: {}, library:, platform: "x86_64-linux"))
      assert_equal({ "LD_PRELOAD" => "libasan.so #{library}" },
        TestFiles.environment(env: { "LD_PRELOAD" => "libasan.so" }, library:, platform: "x86_64-linux"))
      assert_equal({ "DYLD_INSERT_LIBRARIES" => "libclang_rt.asan.dylib:#{library}" },
        TestFiles.environment(env: { "DYLD_INSERT_LIBRARIES" => "libclang_rt.asan.dylib" }, library:,
          platform: "arm64-darwin27"))
    end
  end

  def test_a_run_preloads_nothing_before_the_build
    in_tree do |root|
      assert_empty TestFiles.environment(env: {}, library: File.join(root, "missing.so"), platform: "x86_64-linux")
    end
  end

  def test_a_task_runs_its_tests_in_that_environment
    environment = TestFiles.environment
    previous = Rake.application
    Rake.application = Rake::Application.new
    task = TestFiles::Task.create(:probe) { |t| t.test_globs = %w[test/*_test.rb] }
    ran = nil
    task.define_singleton_method(:sh) { |*command, **| ran = command }
    in_test_tree { Rake::Task[:probe].invoke }

    assert_equal [environment, RbConfig.ruby], ran.first(2)
  ensure
    Rake.application = previous
  end

  def guarded = Object.new.extend(UnitGuard::Kernel)

  def assert_refused(what, &)
    error = assert_raises(UnitGuard::Reached, &)
    assert_includes error.message, "a unit test may not #{what}"
  end

  def test_the_guard_refuses_a_process_a_sleep_and_the_native_extension
    assert_refused("start a process (system)") { guarded.__send__(:system, "true") }
    assert_refused("start a process (`)") { guarded.__send__(:`, "true") }
    assert_refused("sleep") { guarded.__send__(:sleep, 1) }
    assert_refused("load the native extension (lota/native)") { guarded.__send__(:require, "lota/native") }
    assert_refused("load the native extension (lota_native_test)") { guarded.__send__(:require, "lota_native_test") }
    assert_refused("start a process (Process.spawn)") { Module.new.extend(UnitGuard::Process).spawn("true") }
    assert_refused("start a process (IO.popen)") { Module.new.extend(UnitGuard::IO).popen("true") }
  end

  def test_the_guard_lets_ruby_load_what_is_not_native
    guarded.__send__(:require, "json")
    assert defined?(JSON)
    refute_match UnitGuard::NATIVE, "lota/native_gem"
    assert_match UnitGuard::NATIVE, "/lib/lota/native.bundle"
  end
end
