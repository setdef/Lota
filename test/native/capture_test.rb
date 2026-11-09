# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "rbconfig"

# NativeHelper#capture2e, which the native suite runs every command
# through, behaves as Open3.capture2e does without forking this process.
class CaptureTest < Minitest::Test
  include NativeHelper

  def ruby(script, environment = {})
    capture2e(environment, RbConfig.ruby, "-e", script)
  end

  def test_output_and_error_arrive_interleaved_on_one_stream
    output, status = ruby('$stdout.sync = true; print "a"; $stderr.print "b"; print "c"')

    assert_predicate status, :success?
    assert_equal "abc", output
  end

  def test_the_status_is_the_commands_own
    _, status = ruby("exit 3")

    assert_equal 3, status.exitstatus
  end

  # LOTA_TEST_HOME is this process's own (test_helper.rb), where HOME
  # would not do: Ruby on Windows sets HOME as it starts when it is unset.
  def test_the_command_runs_with_this_environment_changed
    _, status = ruby('exit(ENV["LOTA_CAPTURE"] == "set" && !ENV.key?("LOTA_TEST_HOME") && ENV.key?("PATH") ? 0 : 1)',
      { "LOTA_CAPTURE" => "set", "LOTA_TEST_HOME" => nil })

    assert_predicate status, :success?
  end

  def test_the_command_reads_nothing
    output, = ruby("print $stdin.read.inspect")

    assert_equal '""', output
  end

  # A descriptor this process left inheritable stays out of the child.
  # Windows has no /dev/fd to list them, and Ruby starts a process there
  # with CreateProcess, which hands it only the three handles Ruby names
  # (win32/win32.c, CreateChild, STARTF_USESTDHANDLES).
  def test_the_command_inherits_no_other_descriptor
    skip("Windows has no /dev/fd") if TestHome::WINDOWS
    reader, writer = IO.pipe
    writer.close_on_exec = false
    output, = capture2e({}, "ls", "/dev/fd")

    refute_includes output.split, writer.fileno.to_s
  ensure
    reader&.close
    writer&.close
  end

  # Rice raises a std::system_error as SystemCallError
  # (rice/detail/cpp_protect.hpp:84-87), and on Windows Process.spawn
  # raises Errno::ENOENT itself.
  def test_a_missing_command_raises
    error = assert_raises(SystemCallError) { capture2e({}, "lota-no-such-command") }

    expected = TestHome::WINDOWS ? "No such file or directory - lota-no-such-command" : "lota-no-such-command: No such file or directory"
    assert_includes error.message, expected
  end
end
