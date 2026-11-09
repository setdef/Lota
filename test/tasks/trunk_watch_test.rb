# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/trunk_watch"
require "json"
require "stringio"

# TrunkWatch tells a run that failed on an outage from one that failed on
# the code, from the log gh prints, and reruns the first kind.
class TrunkWatchTest < Minitest::Test
  OUTAGE_LOG = <<~LOG
    build\tRun\t2026-11-09T10:00:00Z curl: (22) The requested URL returned error: 503
    build\tRun\t2026-11-09T10:00:01Z ##[error]curl failed with exit code 22
    build\tRun\t2026-11-09T10:00:02Z ##[error]Process completed with exit code 127.
  LOG

  CODE_LOG = <<~LOG
    test\tRun\t2026-11-09T10:00:00Z Failure: GameTest#test_draw [test/game_test.rb:12]
    test\tRun\t2026-11-09T10:00:01Z ##[error]Download failed
  LOG

  def test_outage_errors_are_rerun
    verdict = TrunkWatch.classify(OUTAGE_LOG, 1)

    assert_equal :rerun, verdict.action
    assert_equal 2, verdict.errors.size
  end

  def test_one_real_error_among_outage_errors_stops
    assert_equal :stop, TrunkWatch.classify(CODE_LOG, 1).action
  end

  def test_a_third_attempt_stops_even_on_an_outage
    assert_equal :rerun, TrunkWatch.classify(OUTAGE_LOG, 2).action
    assert_equal :stop, TrunkWatch.classify(OUTAGE_LOG, 3).action
  end

  def test_each_known_outage_is_recognized
    [
      "##[error]Unexpected HTTP response: 502",
      "Error: Could not resolve host: github.com",
      "Error: read ECONNRESET",
      "##[error]The operation was canceled.",
      "##[error]The runner lost communication with the server",
      "##[error]The runner has received a shutdown signal",
      "Error: 503 Service Unavailable",
      "Error: 502 Bad Gateway",
      "Error: step timed out after 10 minutes",
].each do |line|
      assert_equal :rerun, TrunkWatch.classify(line, 1).action, line
    end
  end

  def test_a_log_with_no_error_lines_is_an_outage
    assert_equal :rerun, TrunkWatch.classify("nothing to see\n", 1).action
  end

  # A gh that answers from recorded output and remembers what it was asked.
  class FakeGh
    attr_reader :calls

    def initialize(runs, log)
      @runs = runs
      @log = log
      @calls = []
    end

    def call(*args)
      @calls << args
      case args.first(2)
      when %w[run list] then JSON.generate(@runs)
      when %w[run view] then @log
      when %w[run rerun] then ""
      end
    end
  end

  def runs
    [
      { databaseId: 30, status: "completed", conclusion: "failure", attempt: 1, headSha: "abcdef0123", workflowName: "CI" },
      { databaseId: 20, status: "completed", conclusion: "success", attempt: 1, headSha: "1111111111", workflowName: "CI" },
      { databaseId: 10, status: "in_progress", conclusion: nil, attempt: 1, headSha: "2222222222", workflowName: "CI" },
    ]
  end

  def watch(gh, floor: 0, out: StringIO.new) = TrunkWatch.new(repository: "o/r", gh:, floor:, out:, pause: -> (_) {})

  def test_an_outage_is_rerun_and_reported_in_one_line
    gh = FakeGh.new(runs, OUTAGE_LOG)
    out = StringIO.new

    assert_nil watch(gh, out:).check
    assert_includes gh.calls, %w[run rerun 30 --repo o/r --failed]
    assert_match(/\A\d\d:\d\dZ reran 30 \(abcdef0 CI, attempt 1\) after an outage\n\z/, out.string)
  end

  def test_a_real_failure_is_reported_and_returned
    out = StringIO.new
    red = watch(FakeGh.new(runs, CODE_LOG), out:).check

    assert_equal 30, red.id
    assert_includes out.string, "TRUNK RED: run 30 (abcdef0 CI), attempt 1"
    assert_includes out.string, "Failure: GameTest#test_draw"
  end

  def test_runs_at_or_below_the_floor_are_ignored
    gh = FakeGh.new(runs, CODE_LOG)

    assert_nil watch(gh, floor: 30).check
    assert(gh.calls.none? { |call| call[1] == "view" })
  end

  def test_run_keeps_checking_until_a_run_is_red
    answers = [[], runs]
    gh = -> (*args) { (args[1] == "list") ? JSON.generate(answers.shift) : CODE_LOG }
    pauses = []
    watch = TrunkWatch.new(repository: "o/r", gh:, out: StringIO.new, interval: 7, pause: -> (seconds) { pauses << seconds })

    assert_equal 30, watch.run.id
    assert_equal [7], pauses
  end
end
