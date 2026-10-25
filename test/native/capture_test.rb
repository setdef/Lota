# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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

  def test_the_command_runs_with_this_environment_changed
    _, status = ruby('exit(ENV["LOTA_CAPTURE"] == "set" && !ENV.key?("HOME") && ENV.key?("PATH") ? 0 : 1)',
      { "LOTA_CAPTURE" => "set", "HOME" => nil })

    assert_predicate status, :success?
  end

  def test_the_command_reads_nothing
    output, = ruby("print $stdin.read.inspect")

    assert_equal '""', output
  end

  # A descriptor this process left inheritable stays out of the child.
  def test_the_command_inherits_no_other_descriptor
    reader, writer = IO.pipe
    writer.close_on_exec = false
    output, = capture2e({}, "ls", "/dev/fd")

    refute_includes output.split, writer.fileno.to_s
  ensure
    reader&.close
    writer&.close
  end

  # Rice raises a std::system_error as SystemCallError
  # (rice/detail/cpp_protect.hpp:84-87).
  def test_a_missing_command_raises
    error = assert_raises(SystemCallError) { capture2e({}, "lota-no-such-command") }

    assert_includes error.message, "lota-no-such-command: No such file or directory"
  end
end
