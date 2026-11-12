# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/auto_revert"
require "json"
require "stringio"

# AutoRevert decides what a red run asks for, from what gh and git report,
# and its Bot carries that out through gh and git, faked here with what
# they would print, so each case runs without GitHub or a push.
class AutoRevertTest < Minitest::Test
  GREEN = "1" * 40
  FIRST = "2" * 40
  SECOND = "3" * 40
  LATER = "4" * 40
  REVERT = "5" * 40

  def run_of(attempt: 2, status: "completed", conclusion: "failure", branch: "trunk", event: "push", sha: SECOND)
    AutoRevert::Run.new(id: 42, attempt:, status:, conclusion:, sha:, branch:, event:, workflow: "ci.yml",
      url: "https://github.com/setdef/Lota/actions/runs/42")
  end

  def test_a_first_failed_attempt_runs_its_failed_jobs_again_to_rule_out_a_flaky_test
    assert_equal :rerun, AutoRevert.triage(run_of(attempt: 1), outage: false).action
  end

  def test_a_second_failed_attempt_goes_on_to_the_commits
    assert_nil AutoRevert.triage(run_of, outage: false)
  end

  def test_an_outage_runs_again_until_its_attempts_run_out_and_is_then_reported
    assert_equal :rerun, AutoRevert.triage(run_of(attempt: 2), outage: true).action
    assert_equal :report, AutoRevert.triage(run_of(attempt: 3), outage: true).action
  end

  def test_a_run_that_did_not_fail_or_judges_no_branch_asks_for_nothing
    assert_equal :nothing, AutoRevert.triage(run_of(conclusion: "success"), outage: false).action
    assert_equal :nothing, AutoRevert.triage(run_of(conclusion: "cancelled"), outage: false).action
    assert_equal :nothing, AutoRevert.triage(run_of(status: "in_progress", conclusion: ""), outage: false).action
    assert_equal :nothing, AutoRevert.triage(run_of(event: "pull_request"), outage: false).action
  end

  # git rev-list --parents, newest first.
  GRAPH = "#{SECOND} #{FIRST}\n#{FIRST} #{GREEN}\n#{GREEN} #{'0' * 40}\n".freeze

  def test_the_batch_is_every_commit_since_the_last_green_one
    plan = AutoRevert.batch(SECOND, GRAPH, [GREEN])

    assert_equal :revert, plan.action
    assert_equal [SECOND, FIRST], plan.commits
    assert_equal GREEN, plan.green
  end

  def test_a_batch_of_one_is_that_commit
    assert_equal [SECOND], AutoRevert.batch(SECOND, GRAPH, [FIRST, GREEN]).commits
  end

  def test_a_merge_no_green_commit_or_too_long_a_batch_goes_to_a_person
    merge = "#{SECOND} #{FIRST} #{LATER}\n#{FIRST} #{GREEN}\n#{GREEN}\n"

    assert_match(/merge commit/, AutoRevert.batch(SECOND, merge, [GREEN]).reason)
    assert_equal :report, AutoRevert.batch(SECOND, GRAPH, []).action
    assert_equal :report, AutoRevert.batch(FIRST, GRAPH, [GREEN]).action
    long = (1..(AutoRevert::MOST + 1)).map { |n| format("%040x", n) }
    graph = (long + [GREEN]).each_cons(2).map { |sha, parent| "#{sha} #{parent}\n" }.join + "#{GREEN}\n"
    assert_match(/more than one revert takes back/, AutoRevert.batch(long.first, graph, [GREEN]).reason)
  end

  def plan(*commits)
    AutoRevert::Plan.new(action: :revert, reason: nil, green: GREEN, commits:, skipped: [])
  end

  BOOKKEEPING = "chore: record v0.4.0 in the changelog\n\nRelease: v0.4.0\nRecorded-by: CI run 7, job changelog\n"

  def test_ci_bookkeeping_is_never_reverted
    screened = AutoRevert.screen(plan(SECOND, FIRST), SECOND => "feat: a change\n", FIRST => BOOKKEEPING)

    assert_equal :revert, screened.action
    assert_equal [SECOND], screened.commits
    assert_equal [FIRST], screened.skipped
    assert_equal :report, AutoRevert.screen(plan(FIRST), FIRST => BOOKKEEPING).action
    assert_equal [FIRST], AutoRevert.screen(plan(SECOND, FIRST), SECOND => "x\n", FIRST => "chore: release 0.3.1\n").skipped
  end

  # A revert in the batch could put back what broke trunk, and its own
  # revert would loop, so it goes to a person.
  def test_a_batch_with_a_revert_in_it_is_never_reverted
    [
      "Revert \"feat: a change\"\n\nThis reverts commit #{GREEN}.\n",
      "revert: feat: a change\n",
      "revert: the 2 commits CI run 9 found red\n\nReverts: #{FIRST} #{GREEN}\n",
].each do |message|
      screened = AutoRevert.screen(plan(SECOND, FIRST), SECOND => "feat: x\n", FIRST => message)

      assert_equal :report, screened.action, message
      assert_match(/a revert is never reverted/, screened.reason)
    end
  end

  def test_trunk_that_already_holds_a_fix_or_a_revert_asks_for_nothing
    assert_match(/passed, so the branch holds a fix/, AutoRevert.fixed([LATER], [LATER], LATER => "fix: it\n").reason)
    assert_match(/is a revert/, AutoRevert.fixed([LATER], [], LATER => "revert: feat: a change\n").reason)
    assert_nil AutoRevert.fixed([LATER], [], LATER => "feat: unrelated\n")
    assert_nil AutoRevert.fixed([], [], {})
  end

  def test_green_is_each_commit_with_a_run_that_passed
    json = JSON.generate([
      { headSha: GREEN, status: "completed", conclusion: "success" },
      { headSha: FIRST, status: "completed", conclusion: "cancelled" },
      { headSha: SECOND, status: "in_progress", conclusion: "" },
    ])

    assert_equal [GREEN], AutoRevert.green(json)
    assert_empty AutoRevert.green("not json")
  end

  def test_the_message_names_the_run_the_jobs_and_every_commit_with_its_trailers_in_one_paragraph
    message = AutoRevert.message(run: run_of, commits: [
      [SECOND, "feat: second", "Ann <ann@example.com>"],
      [FIRST, "feat: first", "Bo <bo@example.com>"],
], jobs: ["Gate", "Fuse"], green: GREEN, skipped: [LATER])
    subject, body, trailers = message.split("\n\n")

    assert_equal "revert: the 2 commits CI run 42 found red", subject
    assert(body.lines.all? { |line| line.chomp.size <= 72 }, body)
    assert_includes body.tr("\n", " "),
      "#{FIRST[0, 7]} (feat: first, by Bo <bo@example.com>); #{SECOND[0, 7]} (feat: second, by Ann <ann@example.com>)"
    assert_includes body.tr("\n", " "), "#{LATER[0, 7]}, CI's own release bookkeeping, which is left alone"
    assert_equal [
      "Reverts: #{SECOND} #{FIRST}",
      "Red-run: https://github.com/setdef/Lota/actions/runs/42",
      "Red-jobs: Gate, Fuse",
      "Red-before-green: none (revert)",
      "Provenance: requested",
], trailers.lines(chomp: true)
    assert AutoRevert.revert?(message)
  end

  def test_the_message_of_one_commit_takes_its_subject
    message = AutoRevert.message(run: run_of, commits: [[SECOND, "feat: second", "Ann <ann@example.com>"]], jobs: [], green: FIRST)

    assert message.start_with?("revert: feat: second\n\n"), message
  end

  # gh and git as the Bot calls them: each is answered from +answers+, the
  # first pattern its arguments match, and every call is kept.
  class Fake
    attr_reader :calls

    def initialize(answers)
      @answers = answers
      @calls = []
    end

    def to_proc
      lambda do |*args|
        @calls << args
        line = args.join(" ")
        answer = @answers.find { |pattern, _| pattern.match?(line) }&.last
        answer.respond_to?(:call) ? answer.call(args) : answer
      end
    end

    # Whether some call's arguments, joined, match +pattern+.
    def called?(pattern) = @calls.any? { |args| pattern.match?(args.join(" ")) }
  end

  def run_json(attempt: 2, branch: "trunk")
    JSON.generate(id: 42, run_attempt: attempt, status: "completed", conclusion: "failure", head_sha: SECOND, head_branch: branch,
      event: "push", path: ".github/workflows/ci.yml", html_url: "https://github.com/setdef/Lota/actions/runs/42")
  end

  def gh_answers(attempt: 2, branch: "trunk", runs: [GREEN])
    {
      %r{\Aapi repos/setdef/Lota/actions/runs/42\z} => run_json(attempt:, branch:),
      /\Arun view 42/ => JSON.generate(jobs: [{ databaseId: 7, name: "Gate", conclusion: "failure" }]),
      %r{actions/jobs/7/logs} => "Failure: GameTest#test_draw [test/game_test.rb:12]\n",
      /\Arun rerun 42/ => "",
      /\Arun list/ => JSON.generate(runs.map { |sha| { headSha: sha, status: "completed", conclusion: "success" } }),
      /\Aworkflow run/ => "",
    }
  end

  def git_answers(later: "", revert: "")
    {
      /\Afetch/ => "",
      /\Amerge-base --is-ancestor/ => "",
      /\Arev-list #{SECOND}\.\./ => later,
      /\Arev-list --parents/ => GRAPH,
      /\Alog -1 --format=%B #{LATER}/ => "fix: it\n",
      /\Alog -1 --format=%B/ => "feat: a change\n",
      /\Alog -1 --format=%s/ => "feat: a change\n",
      /\Alog -1 --format=%an/ => "Someone <someone@example.com>\n",
      /\Acheckout/ => "",
      /\Arevert --no-commit/ => revert,
      /\Arevert --abort/ => "",
      /commit --quiet -m/ => "",
      /\Apush/ => "",
      /\Arev-parse HEAD/ => "#{REVERT}\n",
    }
  end

  def bot(gh, git, dry_run: false)
    out = StringIO.new
    status = AutoRevert::Bot.new(repository: "setdef/Lota", run_id: 42, gh: gh.to_proc, git: git.to_proc, dry_run:, out:).call
    [status, out.string]
  end

  def test_the_bot_reruns_a_first_failed_attempt_and_reverts_nothing
    gh = Fake.new(gh_answers(attempt: 1))
    git = Fake.new(git_answers)
    status, out = bot(gh, git)

    assert_equal 0, status
    assert gh.called?(%r{\Arun rerun 42 --repo setdef/Lota --failed\z})
    refute git.called?(/\Arevert/)
    assert_match(/Reran the failed jobs of run 42/, out)
  end

  # The revert's message is the notice: it names the run, the jobs, and
  # each commit's author. Nothing else public is made.
  def test_the_bot_reverts_the_whole_batch_in_one_commit_that_names_the_authors_and_starts_the_runs
    gh = Fake.new(gh_answers)
    git = Fake.new(git_answers)
    status, out = bot(gh, git)

    assert_equal 0, status, out
    assert git.called?(/\Arevert --no-commit #{SECOND} #{FIRST}\z/)
    commit = git.calls.find { |args| args.include?("commit") }
    assert_includes commit.last, "Reverts: #{SECOND} #{FIRST}"
    assert_includes commit.last.tr("\n", " "), "by Someone <someone@example.com>"
    assert_includes commit.last, "Red-run: https://github.com/setdef/Lota/actions/runs/42"
    assert git.called?(%r{\Apush --quiet origin HEAD:refs/heads/trunk\z})
    refute git.called?(/--force|\s-f\b/)
    refute gh.called?(%r{\Aissue|comments|\Arelease|git/tags|git/refs})
    assert gh.called?(%r{\Aworkflow run ci\.yml --repo setdef/Lota --ref trunk\z})
    assert gh.called?(%r{\Aworkflow run prepush\.yml --repo setdef/Lota --ref trunk\z})
    assert_match(/REVERTED #{SECOND[0, 7]} #{FIRST[0, 7]} as #{REVERT[0, 7]} on trunk/, out)
  end

  # A rehearsal on a branch reverts there, but starts no run.
  def test_a_dry_run_on_a_branch_reverts_there_and_starts_no_run
    gh = Fake.new(gh_answers(branch: "experiment/revert"))
    git = Fake.new(git_answers)
    status, out = bot(gh, git, dry_run: true)

    assert_equal 0, status, out
    assert git.called?(%r{\Apush --quiet origin HEAD:refs/heads/experiment/revert\z})
    refute gh.called?(/\Aissue|comments|\Aworkflow run/)
    assert_match(%r{Dry run: would start ci\.yml and prepush\.yml on experiment/revert}, out)
  end

  def test_without_a_dry_run_a_branch_other_than_trunk_is_refused
    gh = Fake.new(gh_answers(branch: "experiment/revert"))
    git = Fake.new(git_answers)
    status, out = bot(gh, git)

    assert_equal 1, status
    assert_empty git.calls
    assert_match(/only a dry run acts on a branch other than trunk/, out)
  end

  def test_the_bot_reverts_nothing_when_a_later_commit_passed
    gh = Fake.new(gh_answers(runs: [GREEN, LATER]))
    git = Fake.new(git_answers(later: "#{LATER}\n"))
    status, out = bot(gh, git)

    assert_equal 0, status
    refute git.called?(/\Arevert/)
    assert_match(/holds a fix/, out)
  end

  def test_a_revert_that_does_not_apply_is_aborted_and_reported
    gh = Fake.new(gh_answers)
    git = Fake.new(git_answers(revert: nil))
    status, out = bot(gh, git)

    assert_equal 1, status
    assert git.called?(/\Arevert --abort/)
    refute git.called?(/\Apush/)
    assert_match(/reverted nothing: git revert of .* does not apply/, out)
    assert_match(/#{SECOND[0, 7]} feat: a change, by Someone <someone@example.com>/, out)
    refute gh.called?(/\Aissue|comments/)
  end
end
