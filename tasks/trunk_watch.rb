# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

# Keeps trunk's GitHub Actions runs green for anyone who wants a hand with
# it (bin/trunk-watch). It lists the trunk's completed runs, and for each
# failed one reads the failed steps' log: a run that failed only because
# GitHub's runners or a download broke is run again. Any other failure has
# its failed jobs run again once, so that a flaky test cannot condemn a good
# commit. A run still red after that is the backstop's business: when
# exactly one commit lies between the last fully green commit and the red
# one, the watch reverts it in a scratch clone and pushes the revert to
# trunk; otherwise, or with no +git+, it stops the watch so that whoever
# started it learns that trunk is red.
class TrunkWatch
  # Lines of a failed log that report an error.
  ERROR_LINE = /##\[error\]|Failure:|Error:/

  # Error lines that say a download or a runner broke, not the code: curl
  # exit codes, HTTP 5xx, failed downloads, DNS failures, resets, canceled
  # operations, lost runners, and timeouts.
  OUTAGE = Regexp.union(
    /curl.? failed with exit code/,
    /Unexpected HTTP response: 5/,
    /Download failed/,
    /Could not resolve host/,
    /ECONNRESET/,
    /The operation was canceled/,
    /lost communication with the server/,
    /runner has received a shutdown signal/,
    /503 Service/,
    /502 Bad Gateway/,
    /timed out after/
  )

  # Error lines that say nothing about the code: a tool a failed step
  # never installed, and the cache report that follows any failure.
  NOISE = /Process completed with exit code 127|Report ccache/

  # A run is run again while its attempt is below this.
  ATTEMPTS = 3

  # Lines of errors printed for a run that stays red.
  SHOWN = 15

  # Times the revert is fetched, rebased, and pushed when pushes are rejected.
  PUSH_ATTEMPTS = 3

  # Commits of history read to find the last green one.
  HISTORY = 500

  # What to do about a failed run: +action+ is :rerun or :stop, +errors+
  # are the log's error lines, and +outage+ is true when every error was an
  # outage's or noise, so that stopping is not the code's fault.
  class Verdict < Data.define(:action, :errors, :outage)
  end

  # A failed run's id, attempt, short and full commit, and workflow's name.
  class Run < Data.define(:id, :attempt, :sha, :head, :workflow)
  end

  # What to do about a run that stayed red: +action+ is :revert or :report;
  # +commits+ are the shas after +green+ up to the red head, newest first;
  # +green+ is the last fully green commit, or nil; +reason+ says why the
  # action is :report.
  class Plan < Data.define(:action, :green, :commits, :reason)
    # The commit to revert, for a :revert plan.
    def sha = commits.first

    # The range as git writes it, or "unknown" without a green commit.
    def range = green ? "#{green[0, 7]}..#{commits.first[0, 7]}" : "unknown"
  end

  # The verdict on a failed run's +log+ at +attempt+: :rerun when every
  # error line is an outage's or noise and the attempt is below ATTEMPTS,
  # otherwise :stop.
  def self.classify(log, attempt)
    errors = log.lines(chomp: true).grep(ERROR_LINE)
    real = errors.grep_v(OUTAGE).grep_v(NOISE)
    Verdict.new(action: (real.empty? && attempt < ATTEMPTS) ? :rerun : :stop, errors:, outage: real.empty?)
  end

  # The names of the failed jobs in the JSON of +gh run view --json jobs+,
  # or none if +json+ is unreadable.
  def self.failed_jobs(json)
    jobs = JSON.parse(json.to_s).fetch("jobs", [])
    jobs.select { |job| job["conclusion"] == "failure" }.map { |job| job["name"] }
  rescue JSON::ParserError, TypeError
    []
  end

  # What to do about the run whose head is +head+, given +runs+ (the parsed
  # JSON of gh run list for trunk, every workflow) and +graph+ (the output
  # of +git rev-list --parents HEAD+, newest first). The green commit is
  # the newest ancestor of +head+, +head+ excepted, all of whose runs
  # succeeded. Exactly one commit with one parent between them is a
  # :revert; anything else is a :report with its reason.
  def self.plan(runs, head, graph)
    commits = graph.to_s.lines.map(&:split)
    return report_plan(nil, [], "the history does not start at #{head[0, 7]}") unless commits.dig(0, 0) == head

    green = green_shas(runs)
    index = commits.index { |sha, *| sha != head && green.include?(sha) }
    return report_plan(nil, commits.map(&:first), "no fully green commit in the last #{commits.size}") unless index

    range = commits.first(index)
    shas = range.map(&:first)
    return report_plan(commits[index].first, shas, "#{range.size} commits are not one") unless range.size == 1
    return report_plan(commits[index].first, shas, "#{head[0, 7]} is a merge commit") unless range.first.size == 2

    Plan.new(action: :revert, green: commits[index].first, commits: shas, reason: nil)
  end

  # The message of the revert of +sha+, whose subject was +subject+, for
  # the red run +run_id+ and the +jobs+ that failed in it.
  def self.revert_message(sha, subject, run_id, jobs)
    named = jobs.empty? ? "no failed job named" : "failed jobs #{jobs.join(', ')}"
    <<~MESSAGE
      revert: #{subject}

      CI run #{run_id} was red, with #{named}, and
      the failed jobs failed again when run again. This commit is the only
      one between the last fully green commit and the red one, so
      bin/trunk-watch reverted #{sha[0, 7]} automatically. Tell its author:
      fix it and land it again.

      Provenance: requested
    MESSAGE
  end

  def self.green_shas(runs)
    runs.group_by { |run| run["headSha"] }.select do |_sha, group|
      group.all? { |run| run["status"] == "completed" && run["conclusion"] == "success" }
    end.keys
  end
  private_class_method :green_shas

  def self.report_plan(green, commits, reason) = Plan.new(action: :report, green:, commits:, reason:)
  private_class_method :report_plan

  # Starts a watch of +repository+ ("owner/name"). +gh+ is a callable that
  # takes the arguments of a gh command and returns its standard output,
  # or nil if it failed. +git+ is likewise for git commands, run in a
  # scratch clone of the repository that the caller owns; without it the
  # watch never reverts. The watch looks at runs with an id above +floor+
  # every +interval+ seconds, waits with +pause+, and tells +out+ what it
  # does.
  def initialize(repository:, gh:, git: nil, floor: 0, interval: 180, out: $stdout, pause: Kernel.method(:sleep), clock: Time)
    @repository = repository
    @gh = gh
    @git = git
    @floor = floor
    @interval = interval
    @out = out
    @pause = pause
    @clock = clock
    @rerun_for_flake = {}
  end

  # Checks the runs again and again until one stays red, and returns it.
  def run
    loop do
      red = check
      return red if red

      @pause.call(@interval)
    end
  end

  # Looks at each failed run above the floor once. Runs it can rerun are
  # rerun; returns the first Run to stay red, after printing it (and
  # reverting its commit, if that is safe), or nil.
  def check
    @runs = list_runs(15)
    announce_passes
    failed_runs.each do |run|
      verdict = TrunkWatch.classify(log(run), run.attempt)
      if verdict.action == :rerun
        rerun(run)
      elsif verdict.outage || @git.nil?
        report(run, verdict)
        return run
      elsif run.attempt == 1
        rerun_for_flake(run)
      else
        settle(run, verdict)
        return run
      end
    end
    nil
  end

  private def list_runs(limit)
    json = @gh.call("run", "list", "--repo", @repository, "--branch", "trunk", "--limit", limit.to_s,
      "--json", "databaseId,status,conclusion,attempt,headSha,workflowName")
    JSON.parse(json || "[]")
  end

  private def failed_runs
    @runs.filter_map do |run|
      next unless run["status"] == "completed" && run["conclusion"] == "failure" && run["databaseId"] > @floor

      Run.new(id: run["databaseId"], attempt: run["attempt"], sha: run["headSha"][0, 7], head: run["headSha"], workflow: run["workflowName"])
    end
  end

  private def log(run) = @gh.call("run", "view", run.id.to_s, "--repo", @repository, "--log-failed").to_s

  private def failed_job_names(run)
    TrunkWatch.failed_jobs(@gh.call("run", "view", run.id.to_s, "--repo", @repository, "--json", "jobs"))
  end

  private def rerun(run)
    return unless @gh.call("run", "rerun", run.id.to_s, "--repo", @repository, "--failed")

    @out.puts "#{stamp} reran #{run.id} (#{run.sha} #{run.workflow}, attempt #{run.attempt}) after an outage"
  end

  private def rerun_for_flake(run)
    jobs = failed_job_names(run)
    return unless @gh.call("run", "rerun", run.id.to_s, "--repo", @repository, "--failed")

    @rerun_for_flake[run.id] = jobs
    @out.puts "#{stamp} reran #{run.id} (#{run.sha} #{run.workflow}) once to rule out a flaky test; failed: #{jobs.join(', ')}"
  end

  private def announce_passes
    @rerun_for_flake.keys.each do |id|
      run = @runs.find { |r| r["databaseId"] == id }
      next unless run && run["status"] == "completed" && run["conclusion"] == "success"

      jobs = @rerun_for_flake.delete(id)
      @out.puts "#{stamp} run #{id} (#{run['headSha'][0, 7]}) passed on rerun after #{jobs.join(', ')} failed: a likely flaky test, worth fixing"
    end
  end

  private def settle(run, verdict)
    plan = plan_for(run)
    reason = plan.reason
    if plan.action == :revert
      reason = revert(run, plan)
      unless reason
        @out.puts "REVERTED #{plan.sha[0, 7]} (run #{run.id})"
        return
      end
    end
    report(run, verdict, plan, reason)
  end

  private def plan_for(run)
    graph = @git.call("fetch", "origin") && @git.call("rev-list", "--parents", "--max-count=#{HISTORY}", run.head)
    return Plan.new(action: :report, green: nil, commits: [], reason: "the history could not be fetched") unless graph

    TrunkWatch.plan(list_runs(100), run.head, graph)
  end

  # Reverts the plan's commit and pushes it to trunk; returns nil when it
  # is pushed, otherwise why it was not.
  private def revert(run, plan)
    sha = plan.sha
    subject = @git.call("log", "-1", "--format=%s", sha).to_s.strip
    unless @git.call("revert", "--no-edit", sha)
      @git.call("revert", "--abort")
      return "git revert of #{sha[0, 7]} failed (a conflict, most likely)"
    end
    @git.call("commit", "--amend", "-m", TrunkWatch.revert_message(sha, subject, run.id, failed_job_names(run)))
    PUSH_ATTEMPTS.times do
      @git.call("fetch", "origin")
      unless @git.call("rebase", "origin/trunk")
        @git.call("rebase", "--abort")
        return "the revert of #{sha[0, 7]} does not rebase onto trunk"
      end
      return nil if @git.call("push", "origin", "HEAD:trunk")
    end
    "the push of the revert was rejected #{PUSH_ATTEMPTS} times"
  end

  private def stamp = @clock.now.utc.strftime("%H:%MZ")

  private def report(run, verdict, plan = nil, reason = nil)
    @out.puts "TRUNK RED: run #{run.id} (#{run.sha} #{run.workflow}), attempt #{run.attempt}"
    @out.puts "commits #{plan.range} (#{plan.commits.map { |sha| sha[0, 7] }.join(' ')}); not reverted: #{reason}" if plan
    @out.puts verdict.errors.first(SHOWN)
  end
end
