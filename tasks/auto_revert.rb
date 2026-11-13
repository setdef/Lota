# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require_relative "trunk_watch"

# Trunk's automatic revert, the backstop for a commit the pre-push checks
# let through (doc/contributors/ci.md, .github/workflows/revert.yml).
#
# A full CI run on trunk takes an hour or more, and runs coalesce, so one
# red run may hold several commits, and the commit that broke trunk is not
# named by the run alone. Waiting for someone to bisect leaves trunk red
# for everyone in the meantime. So when a run on trunk fails, its failed
# jobs run once more, which rules out a flaky test, unless a newer run is
# going already, which would leave the rerun waiting until a push cancels
# it; when they fail again, or no rerun could be judged, every commit
# since the last commit whose run passed is reverted in one commit pushed
# to trunk, never forced, whose message names the run, the jobs, and each
# commit with its author, which is how they are told. Each lands again
# once fixed.
#
# The decisions are pure functions of what +gh+ and +git+ report (triage,
# batch, screen, fixed), so the tests can ask them every case, and Bot
# carries them out through callables a test can fake. It never reverts a
# revert, which could loop, nor CI's own release bookkeeping; it reports
# a run where only the release's jobs failed, which says nothing about
# its commits; and it reverts nothing when trunk already holds a fix.
module AutoRevert
  # A run of a workflow: its id, attempt, status and conclusion, head
  # commit, branch, the event that started it, the workflow's file, and
  # its page.
  class Run < Data.define(:id, :attempt, :status, :conclusion, :sha, :branch, :event, :workflow, :url)
    # The Run in the JSON of gh api repos/OWNER/NAME/actions/runs/ID.
    def self.parse(json)
      run = JSON.parse(json)
      new(id: run.fetch("id"), attempt: run.fetch("run_attempt"), status: run.fetch("status"),
        conclusion: run["conclusion"].to_s, sha: run.fetch("head_sha"), branch: run.fetch("head_branch").to_s,
        event: run.fetch("event"), workflow: File.basename(run.fetch("path")), url: run.fetch("html_url"))
    end
  end

  # What to do about a run: +action+ is :nothing, :rerun, :revert, or
  # :report (tell people, revert nothing); +reason+ says why; +green+ is
  # the last commit whose run passed; +commits+ the commits to revert,
  # newest first; +skipped+ those of CI's bookkeeping left alone.
  class Plan < Data.define(:action, :reason, :green, :commits, :skipped)
    # A plan of +action+ for +reason+ alone.
    def self.of(action, reason) = new(action:, reason:, green: nil, commits: [], skipped: [])
  end

  # A run that failed only on outages runs again while its attempt is
  # below this.
  ATTEMPTS = TrunkWatch::ATTEMPTS

  # Commits of history read to find the last green one.
  HISTORY = 500

  # The most commits one revert takes back; more go to a person.
  MOST = 30

  # The events whose runs on trunk judge trunk.
  EVENTS = %w[push workflow_dispatch].freeze

  # A commit CI wrote to record a release in the changelog, or a release
  # commit from before releases were recorded that way.
  BOOKKEEPING = /^(?:Recorded-by|Released-by): CI run |\Achore: release \d/

  # The jobs of CI's release (doc/contributors/releasing.md): when only
  # they fail, the release did not go out, or its bookkeeping did not
  # reach trunk, and that says nothing about the commits the run proved.
  RELEASE_JOBS = ["Release", "Refuse the release", "Record the releases in CHANGELOG.md"].freeze

  # A revert, by its subject or its body: git's, bin/trunk-watch's, or
  # this one's.
  REVERT = /\A(?:Revert "|revert(?:\([^)]*\))?:)|^This reverts commit \h+|^Reverts: \h/

  # What a red run asks for before any commit is looked at: nothing for a
  # run that has not failed or was not started by a push or by hand; a
  # report when +jobs+, the names of its failed jobs, are all
  # RELEASE_JOBS; a rerun of its failed jobs on its first attempt, to
  # rule out a flaky test, and after that while every error was an
  # +outage+ (TrunkWatch's classification) and attempts remain; a report
  # when outages outlast them. Otherwise nil: the commits decide.
  #
  # +newer+ is the id of a newer run of the workflow on the branch that
  # has not finished, or nil. A rerun joins the branch's concurrency group
  # behind it, and the next push cancels the rerun before it starts, so
  # on a busy branch a rerun is never judged and trunk stays red unseen.
  # With a newer run there, the first failed attempt goes to the commits
  # as it is, unless it may be a flake no rerun has ruled out: an outage,
  # or a +hang+, where every failed job hung or ran out of time (HANG), as
  # a test that waits on a slow runner does on an innocent commit, and
  # +hang+ is the first such line. Those are left to the newer run, which
  # holds the same commits; a hang is reported, naming its line, so a hang
  # a commit caused shows in every run it repeats in.
  def self.triage(run, outage:, jobs: [], newer: nil, hang: nil)
    return Plan.of(:nothing, "run #{run.id} is #{run.status}") unless run.status == "completed"
    return Plan.of(:nothing, "run #{run.id} concluded #{run.conclusion.empty? ? 'nothing' : run.conclusion}") unless run.conclusion == "failure"
    return Plan.of(:nothing, "run #{run.id} was started by #{run.event}, which does not judge a branch") unless EVENTS.include?(run.event)
    return Plan.of(:report, "only CI's release jobs failed (#{jobs.join(', ')}), which says nothing about the commits") if
      !jobs.empty? && (jobs - RELEASE_JOBS).empty?
    return Plan.of(:nothing, "every error of run #{run.id} was an outage, and run #{newer}, newer, holds the same commits") if outage && newer
    if hang && newer && run.attempt == 1
      return Plan.of(:report, "every failed job hung or ran out of time (#{hang}), as a flake does too, so it is left to " \
        "run #{newer}, newer, which holds the same commits; if it hangs there as well, a commit may be the cause")
    end
    return Plan.of(:rerun, "attempt 1 of run #{run.id} failed; running its failed jobs again rules out a flaky test") if run.attempt == 1 && !newer
    return Plan.of(:rerun, "every error of run #{run.id} was an outage") if outage && run.attempt < ATTEMPTS
    return Plan.of(:report, "every error of run #{run.id} was an outage, through #{run.attempt} attempts") if outage

    nil
  end

  # A line of a job's log that says the job hung or ran out of time rather
  # than failed a check: the gate's own end of a lane past its budget, the
  # parity harness's stop of an engine that showed no new frame, and
  # GitHub's end of a job past its timeout-minutes.
  HANG = Regexp.union(
    /TIMED OUT/,
    /showed no new frame for \d+ seconds/,
    /has exceeded the maximum execution time/
  )

  # The first line that shows a HANG in +logs+, the failed jobs' logs,
  # when every one of them shows one; otherwise nil.
  def self.hang(logs)
    lines = logs.map { |log| TrunkWatch.strip_ansi(log).lines.find { |line| line.match?(HANG) } }
    lines.first&.strip unless lines.empty? || lines.any?(&:nil?)
  end

  # The states of a run that has not finished, and so holds or waits for
  # the branch's concurrency group.
  UNFINISHED = %w[queued in_progress pending waiting requested].freeze

  # The id of the newest run after +id+ that has not finished, in the JSON
  # of gh run list --json databaseId,status, or nil.
  def self.newer(json, id)
    JSON.parse(json.to_s).select { |run| run["databaseId"].to_i > id && UNFINISHED.include?(run["status"]) }
      .map { |run| run["databaseId"] }.max
  rescue JSON::ParserError
    nil
  end

  # The commits a red run on +head+ brought in, from +graph+ (git
  # rev-list --parents of +head+, newest first) and +green+, the commits
  # whose runs of the workflow passed: every commit after the newest green
  # one. A merge, a history that does not reach a green commit, or more
  # than MOST commits go to a person.
  def self.batch(head, graph, green)
    commits = graph.to_s.lines.map(&:split)
    return Plan.of(:report, "the history does not start at #{head[0, 7]}") unless commits.dig(0, 0) == head

    index = commits.index { |sha, *| sha != head && green.include?(sha) }
    return Plan.of(:report, "no commit in the last #{commits.size} before #{head[0, 7]} passed") unless index

    range = commits.first(index)
    shas = range.map(&:first)
    merge = range.find { |commit| commit.size > 2 }
    return Plan.of(:report, "#{merge.first[0, 7]} is a merge commit").with(green: commits[index].first, commits: shas) if merge
    return Plan.of(:report, "#{range.size} commits are more than one revert takes back").with(green: commits[index].first, commits: shas) if
      range.size > MOST

    Plan.new(action: :revert, reason: nil, green: commits[index].first, commits: shas, skipped: [])
  end

  # +plan+ with CI's bookkeeping commits set aside, given each commit's
  # message in +messages+. A revert in the batch goes to a person, since
  # reverting it could put back what broke trunk and loop.
  def self.screen(plan, messages)
    revert = plan.commits.find { |sha| revert?(messages.fetch(sha)) }
    return plan.with(action: :report, reason: "#{revert[0, 7]} is a revert, and a revert is never reverted") if revert

    skipped, commits = plan.commits.partition { |sha| messages.fetch(sha).match?(BOOKKEEPING) }
    return plan.with(action: :report, reason: "every commit is CI's release bookkeeping", skipped:, commits:) if commits.empty?

    plan.with(commits:, skipped:)
  end

  # Whether trunk already holds a fix for a red run: +later+, the commits
  # after its head, newest first, and their +messages+. A later commit
  # whose run passed is a fix; a later revert has its own run judge what
  # is left. Returns the Plan to do nothing, or nil.
  def self.fixed(later, green, messages)
    passed = later.find { |sha| green.include?(sha) }
    return Plan.of(:nothing, "#{passed[0, 7]}, later on the branch, passed, so the branch holds a fix") if passed

    revert = later.find { |sha| revert?(messages.fetch(sha)) }
    return Plan.of(:nothing, "#{revert[0, 7]}, later on the branch, is a revert; its own run judges what is left") if revert

    nil
  end

  # Whether +message+ is a revert's.
  def self.revert?(message) = message.match?(REVERT)

  # The commits whose runs passed, in the JSON of gh run list --json
  # headSha,status,conclusion.
  def self.green(json)
    JSON.parse(json.to_s).select { |run| run["status"] == "completed" && run["conclusion"] == "success" }.map { |run| run["headSha"] }.uniq
  rescue JSON::ParserError
    []
  end

  # The message of the revert of +commits+ (newest first, each [sha,
  # subject, author]) for red +run+, whose +jobs+ failed twice, since
  # +green+, with the bookkeeping commits +skipped+ left alone. It is the
  # notice: it names the run, the jobs, and each commit's author.
  def self.message(run:, commits:, jobs:, green:, skipped: [])
    count = (commits.size == 1) ? "the commit" : "the #{commits.size} commits"
    subject = (commits.size == 1) ? "revert: #{commits.first[1]}" : "revert: #{count} CI run #{run.id} found red"
    named = commits.reverse.map { |sha, title, author| "#{sha[0, 7]} (#{title}, by #{author})" }.join("; ")
    left = skipped.empty? ? "" : " The run also held #{skipped.map { |sha| sha[0, 7] }.join(', ')}, CI's own release bookkeeping, which is left alone."
    batch = if commits.size == 1
      "so the commit it brought in broke the branch. This reverts it: #{named}.#{left} Land it again once it is fixed."
    else
      "so it brought in #{count} that it alone proved, and nothing tells which of them broke the branch. " \
        "This reverts all of them together: #{named}.#{left} Land each again once it is fixed."
    end
    again = if run.attempt == 1
      "and a newer run, already going, would have cancelled a rerun before it started, so this attempt is judged as it is"
    else
      "and those jobs failed again when run again, so this is no flaky test"
    end
    body = "#{run.workflow} run #{run.id} failed on #{run.sha[0, 7]} in #{jobs.empty? ? 'jobs it did not name' : jobs.join(', ')}, " \
      "#{again}. The run was the first to finish since #{green[0, 7]}, the last commit whose run passed, #{batch}"
    trailers = [
      "Reverts: #{commits.map(&:first).join(' ')}",
      "Red-run: #{run.url}",
      "Red-jobs: #{jobs.empty? ? 'none named' : jobs.join(', ')}",
      "Red-before-green: none (revert)",
      "Provenance: requested",
]
    "#{subject}\n\n#{wrap(body)}\n\n#{trailers.join("\n")}\n"
  end

  # +text+ wrapped at 72 columns.
  def self.wrap(text)
    text.split.each_with_object([+""]) do |word, lines|
      lines << +"" if !lines.last.empty? && lines.last.size + 1 + word.size > 72
      lines.last << " " unless lines.last.empty?
      lines.last << word
    end.join("\n")
  end

  # Carries out the plan for one run of +repository+ ("owner/name"): +gh+
  # and +git+ are callables that take a command's arguments and return its
  # standard output, or nil if it failed; +git+ runs in a clone of the
  # repository that the caller owns, with origin able to push. It tells
  # people only through the revert's message and what it prints, which the
  # workflow keeps as the run's summary; it opens no issue and writes no
  # comment. A +dry_run+ starts no run on the revert, so a rehearsal on a
  # branch costs one push. Without one it acts on trunk alone.
  class Bot
    # The branch a real revert lands on.
    TRUNK = "trunk"

    # The workflows started on the revert, since a push GitHub's token
    # makes starts none.
    FOLLOW_UPS = %w[ci.yml prepush.yml].freeze

    # Times the revert is rebased and pushed when the branch moves first.
    PUSH_ATTEMPTS = 3

    # The identity the revert is committed as.
    IDENTITY = ["-c", "user.name=github-actions[bot]", "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com"].freeze

    # [repository] "owner/name".
    # [run_id] The red run.
    # [gh] Runs gh.
    # [git] Runs git in the caller's clone.
    # [dry_run] Start no run on the revert.
    # [out] Where it says what it does.
    def initialize(repository:, run_id:, gh:, git:, dry_run: false, out: $stdout)
      @repository = repository
      @run_id = run_id
      @gh = gh
      @git = git
      @dry_run = dry_run
      @out = out
    end

    # Does what the run asks, says so, and returns the exit status: 0 when
    # it did what the run asked, 1 when trunk stays red for a person to
    # see to.
    def call
      run = Run.parse(gh!("api", "repos/#{@repository}/actions/runs/#{@run_id}"))
      return refuse("run #{run.id} is on #{run.branch}; only a dry run acts on a branch other than #{TRUNK}") unless @dry_run || run.branch == TRUNK

      jobs = failed_jobs(run)
      red = run.status == "completed" && run.conclusion == "failure"
      logs = red ? logs(jobs) : []
      plan = AutoRevert.triage(run, outage: !logs.empty? && TrunkWatch.classify_jobs(logs, 1).outage,
        jobs: jobs.map(&:last), newer: newer_run(run), hang: AutoRevert.hang(logs))
      plan ||= plan_for(run)
      act(run, jobs.map(&:last), plan)
    end

    private def act(run, jobs, plan)
      case plan.action
      when :nothing
        @out.puts "Nothing to do: #{plan.reason}"
        0
      when :rerun
        gh!("run", "rerun", run.id.to_s, "--repo", @repository, "--failed")
        @out.puts "Reran the failed jobs of run #{run.id}: #{plan.reason}"
        0
      when :revert
        revert(run, jobs, plan)
      else
        report(run, jobs, plan)
      end
    end

    # A newer run of the workflow on the run's branch that has not
    # finished, or nil (AutoRevert.newer).
    private def newer_run(run)
      AutoRevert.newer(@gh.call("run", "list", "--repo", @repository, "--workflow", run.workflow, "--branch", run.branch,
        "--limit", "20", "--json", "databaseId,status"), run.id)
    end

    # [id, name] of each failed job of the run's latest attempt.
    private def failed_jobs(run)
      TrunkWatch.failed_job_ids(@gh.call("run", "view", run.id.to_s, "--repo", @repository, "--json", "jobs"))
    end

    # Each failed job's log, which TrunkWatch tells outages from the
    # code's failures in, and AutoRevert.hang hangs. A log that cannot be
    # read counts as the code's failure, and as no hang.
    private def logs(jobs)
      jobs.map do |id, name|
        @gh.call("api", "--allow-escape-sequences", "repos/#{@repository}/actions/jobs/#{id}/logs") ||
          "##[error]the log of job #{name} (#{id}) could not be read\n"
      end
    end

    private def plan_for(run)
      branch = "origin/#{run.branch}"
      git!("fetch", "--quiet", "origin", "+refs/heads/#{run.branch}:refs/remotes/#{branch}")
      return Plan.of(:report, "#{run.sha[0, 7]} is no longer on #{run.branch}") unless @git.call("merge-base", "--is-ancestor", run.sha, branch)

      green = AutoRevert.green(@gh.call("run", "list", "--repo", @repository, "--workflow", run.workflow, "--branch", run.branch,
        "--limit", "200", "--json", "headSha,status,conclusion"))
      later = git!("rev-list", "#{run.sha}..#{branch}").split
      fixed = AutoRevert.fixed(later, green, messages(later))
      return fixed if fixed

      plan = AutoRevert.batch(run.sha, git!("rev-list", "--parents", "--max-count=#{HISTORY}", run.sha), green)
      (plan.action == :revert) ? AutoRevert.screen(plan, messages(plan.commits)) : plan
    end

    private def messages(shas)
      shas.to_h { |sha| [sha, git!("log", "-1", "--format=%B", sha)] }
    end

    private def subject(sha) = git!("log", "-1", "--format=%s", sha).strip

    # Reverts the plan's commits in one commit on the run's branch, pushes
    # it, tells their authors, and starts the branch's runs on it.
    private def revert(run, jobs, plan)
      branch = "origin/#{run.branch}"
      git!("checkout", "--quiet", "--detach", branch)
      unless @git.call("revert", "--no-commit", *plan.commits)
        @git.call("revert", "--abort")
        return report(run, jobs, plan.with(reason: "git revert of #{plan.commits.map { |sha| sha[0, 7] }.join(' ')} does not apply"))
      end
      message = AutoRevert.message(run:, commits: authored(plan.commits), jobs:, green: plan.green, skipped: plan.skipped)
      git!(*IDENTITY, "commit", "--quiet", "-m", message)
      failure = push(run.branch)
      return report(run, jobs, plan.with(reason: failure)) if failure

      sha = git!("rev-parse", "HEAD").strip
      @out.puts "REVERTED #{plan.commits.map { |commit| commit[0, 7] }.join(' ')} as #{sha[0, 7]} on #{run.branch} (run #{run.id}):\n\n#{message}"
      follow_up(run.branch)
      0
    end

    # Pushes HEAD to +branch+, never forced, rebasing onto it when it
    # moved; returns nil once pushed, otherwise why not.
    private def push(branch)
      PUSH_ATTEMPTS.times do
        return nil if @git.call("push", "--quiet", "origin", "HEAD:refs/heads/#{branch}")

        git!("fetch", "--quiet", "origin", "+refs/heads/#{branch}:refs/remotes/origin/#{branch}")
        next if @git.call(*IDENTITY, "rebase", "--quiet", "origin/#{branch}")

        @git.call("rebase", "--abort")
        return "the revert does not rebase onto #{branch}"
      end
      "the push of the revert was refused #{PUSH_ATTEMPTS} times"
    end

    # Says what stays red, and why nothing was reverted, with each commit
    # and its author, and fails, so the run's summary shows it.
    private def report(run, jobs, plan)
      @out.puts "RED: #{run.workflow} run #{run.id} on #{run.branch} (#{run.sha[0, 7]}) failed in " \
        "#{jobs.empty? ? 'jobs it did not name' : jobs.join(', ')}; reverted nothing: #{plan.reason}"
      authored(plan.commits.empty? ? [run.sha] : plan.commits).each do |sha, title, author|
        @out.puts "  #{sha[0, 7]} #{title}, by #{author}"
      end
      1
    end

    private def refuse(reason)
      @out.puts "Refused: #{reason}"
      1
    end

    # [sha, subject, author] of each of +shas+, the author as git records
    # them, name and email.
    private def authored(shas)
      shas.map { |sha| [sha, subject(sha), git!("log", "-1", "--format=%an <%ae>", sha).strip] }
    end

    # Starts the branch's runs on the revert. A dry run starts none.
    private def follow_up(branch)
      return @out.puts("Dry run: would start #{FOLLOW_UPS.join(' and ')} on #{branch}") if @dry_run

      FOLLOW_UPS.each do |workflow|
        started = @gh.call("workflow", "run", workflow, "--repo", @repository, "--ref", branch)
        @out.puts(started ? "Started #{workflow} on #{branch}" : "Could not start #{workflow} on #{branch}")
      end
    end

    private def gh!(*arguments)
      @gh.call(*arguments) or raise Failure, "gh #{arguments.join(' ')} failed"
    end

    private def git!(*arguments)
      @git.call(*arguments) or raise Failure, "git #{arguments.join(' ')} failed"
    end
  end

  # Raised when gh or git fails where nothing can go on without it.
  class Failure < StandardError; end
end
