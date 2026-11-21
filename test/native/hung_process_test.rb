# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# A test that starts a process and finds it still running past its time
# says where it hung before it kills it: the process and those it started,
# as ps lists them, and a stack sample of each, where the system has a
# tool for one. A hang that shows on one runner alone then names its
# cause in the run that shows it.
class HungProcessTest < Minitest::Test
  include NativeHelper

  # How long the grandchild sleeps. While it lives it holds the output
  # open, so a test that killed only the child would wait this long.
  SLEEP = 30

  # A Ruby that starts a grandchild, Ruby sleeping, writing to its own
  # output, prints both their ids, and sleeps.
  HANGS = <<~RUBY
    require "lota/native"
    require "lota_native_test"
    variables = ENV.map { |name, value| "\#{name}=\#{value}" }
    grandchild = LotaNativeTest.spawn([RbConfig.ruby, "-e", "sleep #{SLEEP}", "hung-grandchild"], 1, variables)
    puts Process.pid, grandchild
    $stdout.flush
    sleep
  RUBY

  def test_a_process_past_its_time_says_where_it_hung_and_is_killed_with_what_it_started
    skip "Windows has no ps, and no stack sampler" if TestHome::WINDOWS

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    test_extension = File.dirname(loaded("lota_native_test"))
    output, status = ruby_of_its_own("-I#{test_extension}", "-e", HANGS, timeout: 2)
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    child, grandchild = output.lines.first(2).map { |line| Integer(line) }
    assert_match(/^--- processes \(ps\) ---\n.*PID/, output)
    assert_match(/^ *#{child} .*-e/, output, "ps lists the child")
    assert_match(/^ *#{grandchild} .*hung-grandchild/, output, "ps lists what it started")
    [child, grandchild].each { |pid| assert_match(/^--- stack of #{pid}: /, output) }
    assert_match(/Call graph:/, output, "sample's report") unless TestHome::LINUX
    assert_match(/\(killed after 2 seconds\)\n\z/, output)
    assert_equal "KILL", Signal.signame(status.termsig)
    assert_operator took, :<, SLEEP, "the grandchild is killed too, so the output closes"
  end
end
