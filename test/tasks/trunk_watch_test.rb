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

  JOBS = JSON.generate(jobs: [{ name: "Gate (linux)", conclusion: "failure" }, { name: "Delivery", conclusion: "success" }])

  # A gh that answers from recorded output and remembers what it was asked.
  class FakeGh
    attr_reader :calls

    def initialize(runs, log, jobs: JOBS)
      @runs = runs
      @log = log
      @jobs = jobs
      @calls = []
    end

    def call(*args)
      @calls << args
      case args.first(2)
      when %w[run list] then JSON.generate(@runs)
      when %w[run view] then args.include?("jobs") ? @jobs : @log
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

  # A git that answers from a table of recorded output, keyed by the first
  # argument, and remembers what it was asked. A nil answer is a failure;
  # an array answers once per call.
  class FakeGit
    attr_reader :calls

    def initialize(answers)
      @answers = answers
      @calls = []
    end

    def call(*args)
      @calls << args
      answer = @answers.fetch(args.first, "")
      answer.respond_to?(:shift) ? answer.shift : answer
    end

    def verbs = @calls.map(&:first)
  end

  RED = "a" * 40
  GREEN = "b" * 40
  OLDER = "c" * 40
  OTHER = "d" * 40

  def run_row(id, sha, conclusion, status: "completed", attempt: 1)
    { databaseId: id, status:, conclusion:, attempt:, headSha: sha, workflowName: "CI" }
  end

  def history_runs = [run_row(30, RED, "failure", attempt: 2), run_row(20, GREEN, "success"), run_row(10, OLDER, "success")]

  def stringify(rows) = rows.map { |row| row.transform_keys(&:to_s) }

  def test_plan_reverts_the_only_commit_after_the_last_green_one
    plan = TrunkWatch.plan(stringify(history_runs), RED, "#{RED} #{GREEN}\n#{GREEN} #{OLDER}\n")

    assert_equal :revert, plan.action
    assert_equal RED, plan.sha
    assert_equal GREEN, plan.green
    assert_equal "bbbbbbb..aaaaaaa", plan.range
  end

  def test_plan_skips_commits_whose_runs_are_not_all_green
    runs = stringify([run_row(25, GREEN, "success"), run_row(26, GREEN, "failure"), run_row(10, OLDER, "success")])
    plan = TrunkWatch.plan(runs, RED, "#{RED} #{GREEN}\n#{GREEN} #{OLDER}\n#{OLDER}\n")

    assert_equal :report, plan.action
    assert_equal OLDER, plan.green
    assert_equal [RED, GREEN], plan.commits
    assert_match(/2 commits/, plan.reason)
  end

  def test_plan_reports_a_merge_commit
    plan = TrunkWatch.plan(stringify([run_row(20, GREEN, "success")]), RED, "#{RED} #{GREEN} #{OTHER}\n#{GREEN}\n")

    assert_equal :report, plan.action
    assert_match(/merge commit/, plan.reason)
  end

  def test_plan_reports_when_no_commit_is_green_or_history_is_wrong
    assert_match(/no fully green/, TrunkWatch.plan([], RED, "#{RED} #{GREEN}\n").reason)
    assert_match(/does not start/, TrunkWatch.plan([], RED, "#{GREEN}\n").reason)
    assert_match(/does not start/, TrunkWatch.plan([], RED, nil).reason)
  end

  def test_failed_jobs_names_the_failures_and_tolerates_junk
    assert_equal ["Gate (linux)"], TrunkWatch.failed_jobs(JOBS)
    assert_empty TrunkWatch.failed_jobs("not json")
    assert_empty TrunkWatch.failed_jobs(nil)
  end

  def test_classify_flags_an_exhausted_outage_as_an_outage
    assert TrunkWatch.classify(OUTAGE_LOG, 3).outage
    refute TrunkWatch.classify(CODE_LOG, 3).outage
  end

  def revert_watch(runs, git, log: CODE_LOG, out: StringIO.new)
    gh = FakeGh.new(runs, log)
    [TrunkWatch.new(repository: "o/r", gh:, git:, out:, pause: -> (_) {}), gh]
  end

  def test_a_first_real_failure_is_rerun_once_not_reverted
    git = FakeGit.new({})
    out = StringIO.new
    watch, gh = revert_watch([run_row(30, RED, "failure")], git, out:)

    assert_nil watch.check
    assert_includes gh.calls, %w[run rerun 30 --repo o/r --failed]
    assert_empty git.calls
    assert_match(/once to rule out a flaky test; failed: Gate \(linux\)/, out.string)
  end

  def test_a_run_that_passes_on_rerun_is_called_flaky_and_not_reverted
    git = FakeGit.new({})
    out = StringIO.new
    listings = [[run_row(30, RED, "failure")], [run_row(30, RED, "success", attempt: 2)]]
    gh = FakeGh.new([], CODE_LOG)
    gh.define_singleton_method(:call) do |*args|
      (args[1] == "list") ? JSON.generate((listings.size > 1) ? listings.shift : listings.first) : super(*args)
    end
    watch = TrunkWatch.new(repository: "o/r", gh:, git:, out:, pause: -> (_) {})

    assert_nil watch.check
    assert_nil watch.check
    assert_nil watch.check
    assert_match(/run 30 \(aaaaaaa\) passed on rerun after Gate \(linux\) failed: a likely flaky test, worth fixing/, out.string)
    assert_equal 1, out.string.scan("passed on rerun").size
    assert_empty git.calls
  end

  def test_a_run_red_after_rerun_reverts_its_only_commit
    git = FakeGit.new("rev-list" => "#{RED} #{GREEN}\n#{GREEN} #{OLDER}\n", "log" => "feat: break it\n")
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)

    assert_equal 30, watch.check.id
    assert_equal %w[fetch rev-list log revert commit fetch rebase push], git.verbs
    assert_equal ["revert", "--no-edit", RED], git.calls[3]
    assert_equal %w[push origin HEAD:trunk], git.calls.last
    message = git.calls[4].last

    assert_includes message, "revert: feat: break it"
    assert_includes message, "CI run 30 was red"
    assert_includes message, "Gate (linux)"
    assert_includes out.string, "REVERTED aaaaaaa (run 30)"
    refute_includes out.string, "TRUNK RED"
  end

  def test_a_rejected_push_is_fetched_rebased_and_retried_but_never_forced
    git = FakeGit.new("rev-list" => "#{RED} #{GREEN}\n#{GREEN}\n", "push" => [nil, nil, ""])
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)
    watch.check

    assert_equal 3, git.verbs.count("push")
    assert_equal 3, git.verbs.count("rebase")
    assert(git.calls.none? { |call| call.any? { |arg| arg.include?("force") || arg == "-f" } })
    assert_includes out.string, "REVERTED"
  end

  def test_a_push_rejected_every_time_reports_red
    git = FakeGit.new("rev-list" => "#{RED} #{GREEN}\n#{GREEN}\n", "push" => nil)
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)

    assert_equal 30, watch.check.id
    assert_equal 3, git.verbs.count("push")
    assert_includes out.string, "TRUNK RED"
    assert_includes out.string, "rejected 3 times"
  end

  def test_a_conflicting_revert_is_aborted_and_reported
    git = FakeGit.new("rev-list" => "#{RED} #{GREEN}\n#{GREEN}\n", "revert" => [nil, ""])
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)

    assert_equal 30, watch.check.id
    assert_includes git.calls, %w[revert --abort]
    refute_includes git.verbs, "push"
    assert_includes out.string, "TRUNK RED: run 30 (aaaaaaa CI), attempt 2"
    assert_includes out.string, "Failure: GameTest#test_draw"
  end

  def test_a_rebase_conflict_is_aborted_and_reported
    git = FakeGit.new("rev-list" => "#{RED} #{GREEN}\n#{GREEN}\n", "rebase" => [nil, ""])
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)
    watch.check

    assert_includes git.calls, %w[rebase --abort]
    refute_includes git.verbs, "push"
    assert_includes out.string, "does not rebase"
  end

  def test_several_commits_are_reported_with_their_range_and_not_reverted
    git = FakeGit.new("rev-list" => "#{RED} #{OTHER}\n#{OTHER} #{GREEN}\n#{GREEN}\n")
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)

    assert_equal 30, watch.check.id
    refute_includes git.verbs, "revert"
    assert_includes out.string, "TRUNK RED: run 30"
    assert_includes out.string, "commits bbbbbbb..aaaaaaa (aaaaaaa ddddddd); not reverted: 2 commits are not one"
  end

  def test_a_failed_fetch_reports_without_reverting
    git = FakeGit.new("fetch" => nil)
    out = StringIO.new
    watch, = revert_watch(history_runs, git, out:)

    assert_equal 30, watch.check.id
    assert_includes out.string, "could not be fetched"
  end

  def test_an_outage_that_persists_is_reported_not_reverted
    git = FakeGit.new({})
    out = StringIO.new
    watch, = revert_watch([run_row(30, RED, "failure", attempt: 3)], git, log: OUTAGE_LOG, out:)

    assert_equal 30, watch.check.id
    assert_empty git.calls
    assert_includes out.string, "TRUNK RED"
  end

  def test_without_git_a_real_failure_stops_at_once
    gh = FakeGh.new([run_row(30, RED, "failure")], CODE_LOG)

    assert_equal 30, TrunkWatch.new(repository: "o/r", gh:, out: StringIO.new, pause: -> (_) {}).check.id
    assert(gh.calls.none? { |call| call[1] == "rerun" })
  end
end
