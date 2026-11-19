# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

# Keeps trunk's GitHub Actions runs green for anyone who wants a hand with
# it (bin/trunk-watch). It lists the trunk's completed runs, and for each
# failed one reads the raw log of every failed job (gh run view --log-failed
# silently drops lines that hold terminal escape sequences, so it is not
# used), strips the escape codes, and classifies each job's errors: a run
# that failed only because GitHub's runners or a download broke is run
# again. Any other failure has
# its failed jobs run again once, so that a flaky test cannot condemn a good
# commit. A run still red after that is the backstop's business: when
# exactly one commit lies between the last commit its workflow passed on
# and the red one, the watch reverts it in a scratch clone and pushes the revert to
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

  # Lines, not reported as errors, that show a job's download arrived
  # broken: sdkmanager could not open the Android system image it had
  # just downloaded, and the emulator step ended with only its exit
  # status as its error.
  BROKEN_DOWNLOAD = /An error occurred while preparing SDK package .*Error on ZipFile/

  # The error line a failed step always ends with, which names no cause:
  # in a job whose log shows BROKEN_DOWNLOAD, it is that outage's.
  STEP_EXIT = /##\[error\](?:The process '.*' failed|Process completed) with exit code \d+/

  # A Metal command buffer the GPU hung on, as macOS names it in what the
  # parity harness's Metal watch prints (doc/contributors/parity.md). A
  # macOS runner's GPU has hung under the reference love, which then drew
  # black frames to its run's end, so a parity test compared Lota with
  # them and failed on an innocent commit.
  GPU_HANG = /kIOGPUCommandBufferCallbackErrorHang/

  # The lines of a parity failure that head what the reference love's
  # Metal watch reported, and what Lota printed, which follows it
  # (Parity.mismatch_message, test/parity/parity_helper.rb).
  REFERENCE_WATCH = "The reference love's Metal watch reported:"
  LOTA_PRINTED = /\ALota printed/

  # The lines of the gate's report (tasks/gate.rb): the heading of each
  # check's output, the heading of its table of timings, and a check's
  # row there that did not pass.
  GATE_CHECK = /\A\S+ gate: \S+ \(\d+ s/
  GATE_TIMINGS = "gate timings"
  GATE_UNPASSED = /\A  (\S+) +\d+ s  (?:FAILED|TIMED OUT)\z/

  # Minitest's heading of each failure or error, and its count of them.
  TEST_FAILURE = /\A *\d+\) (?:Failure|Error):\z/
  TEST_COUNT = /\A\d+ runs, \d+ assertions, (\d+) failures, (\d+) errors/

  # The timestamp the logs API puts before each line.
  STAMP = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ?/

  # Terminal escape sequences: CSI sequences (colors, cursor moves) and the
  # two-character escapes.
  ANSI = %r{\e\[[0-?]*[ -/]*[@-~]|\e[@-Z\\-_]}

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
  # +green+ is the last green commit, or nil; +reason+ says why the
  # action is :report.
  class Plan < Data.define(:action, :green, :commits, :reason)
    # The commit to revert, for a :revert plan.
    def sha = commits.first

    # The range as git writes it, or "unknown" without a green commit.
    def range = green ? "#{green[0, 7]}..#{commits.first[0, 7]}" : "unknown"
  end

  # The verdict on a failed run's +log+ at +attempt+: :rerun when every
  # error line is an outage's or noise and the attempt is below ATTEMPTS,
  # otherwise :stop. In a job whose every failed gate check failed only
  # on the GPU's hang (gpu_hang), those checks' error lines and the
  # step's exit status are the hang's, and its first line is shown among
  # the errors.
  def self.classify(log, attempt)
    lines = strip_ansi(log).lines(chomp: true)
    hung = gpu_hang(lines.map { |line| line.sub(STAMP, "") })
    broken = lines.grep(BROKEN_DOWNLOAD)
    errors = broken + lines.values_at(*hung).grep(GPU_HANG).first(1) + lines.grep(ERROR_LINE)
    real = broken + lines.reject.with_index { |_, index| hung.include?(index) }.grep(ERROR_LINE)
    real = real.grep_v(OUTAGE).grep_v(NOISE).grep_v(BROKEN_DOWNLOAD)
    real = real.grep_v(STEP_EXIT) unless broken.empty? && hung.empty?
    Verdict.new(action: (real.empty? && attempt < ATTEMPTS) ? :rerun : :stop, errors:, outage: real.empty?)
  end

  # The indexes of the +lines+ (a job's log, without escapes or
  # timestamps) of the gate checks a hung GPU explains, when it explains
  # every check that did not pass; otherwise none. A check is explained
  # when minitest counted as many failures and errors in its output as
  # it shows, at least one, and the reference love's Metal watch reported
  # a GPU_HANG in each. A commit that breaks Lota's drawing fails with
  # the reference's GPU fine, or with only Lota's hung, and is not.
  def self.gpu_hang(lines)
    checks = lines.filter_map { |line| line[GATE_UNPASSED, 1] }.map { |name| gate_check(lines, name) }
    return [] unless !checks.empty? && checks.all? { |check| check && gpu_hung?(lines[check]) }

    checks.flat_map(&:to_a)
  end

  # The range of +lines+ that holds the output of the gate check +name+,
  # from its heading to the next check's or the table of timings, or nil.
  def self.gate_check(lines, name)
    start = lines.index { |line| line.match?(GATE_CHECK) && line.split[2] == name }
    return unless start

    length = lines.drop(start + 1).index { |line| line.match?(GATE_CHECK) || line == GATE_TIMINGS } || (lines.size - start - 1)
    start..(start + length)
  end
  private_class_method :gate_check

  # Whether every failure in a check's +output+ is a parity test's whose
  # reference love's GPU hung, and minitest counted no other.
  def self.gpu_hung?(output)
    failures = output.slice_before { |line| line.match?(TEST_FAILURE) }.drop(1)
    counted = output.sum { |line| line.match(TEST_COUNT)&.captures&.sum(&:to_i) || 0 }
    !failures.empty? && failures.size == counted && failures.all? { |failure| reference_hung?(failure) }
  end

  # Whether what the reference love's Metal watch reported in a parity
  # test's +failure+ shows a GPU_HANG.
  def self.reference_hung?(failure)
    failure.drop_while { |line| line != REFERENCE_WATCH }.drop(1).take_while { |line| !line.match?(LOTA_PRINTED) }.any?(GPU_HANG)
  end
  private_class_method :gpu_hung?, :reference_hung?

  # The verdict on a failed run's jobs, from each job's log in +logs+:
  # each is classified alone, so that one job's broken download excuses
  # no other job's error.
  def self.classify_jobs(logs, attempt)
    verdicts = logs.map { |log| classify(log, attempt) }
    outage = verdicts.all?(&:outage)
    Verdict.new(action: (outage && attempt < ATTEMPTS) ? :rerun : :stop, errors: verdicts.flat_map(&:errors), outage:)
  end

  # +log+ without its terminal escape sequences.
  def self.strip_ansi(log) = log.to_s.gsub(ANSI, "")

  # The [id, name] pairs of the failed jobs in the JSON of
  # +gh run view --json jobs+, or none if +json+ is unreadable.
  def self.failed_job_ids(json)
    jobs = JSON.parse(json.to_s).fetch("jobs", [])
    jobs.select { |job| job["conclusion"] == "failure" }.map { |job| [job["databaseId"], job["name"]] }
  rescue JSON::ParserError, TypeError
    []
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
  # succeeded, of +workflow+ alone when it is given: a workflow that runs
  # on every commit judges a commit by its own runs, though another, which
  # gives way to newer pushes, was cancelled there. Exactly one commit with
  # one parent between them is a :revert; anything else is a :report with
  # its reason.
  def self.plan(runs, head, graph, workflow = nil)
    commits = graph.to_s.lines.map(&:split)
    return report_plan(nil, [], "the history does not start at #{head[0, 7]}") unless commits.dig(0, 0) == head

    green = green_shas(workflow ? runs.select { |run| run["workflowName"] == workflow } : runs)
    index = commits.index { |sha, *| sha != head && green.include?(sha) }
    return report_plan(nil, commits.map(&:first), "no fully green commit in the last #{commits.size}") unless index

    range = commits.first(index)
    shas = range.map(&:first)
    return report_plan(commits[index].first, shas, "#{range.size} commits are not one") unless range.size == 1
    return report_plan(commits[index].first, shas, "#{head[0, 7]} is a merge commit") unless range.first.size == 2

    Plan.new(action: :revert, green: commits[index].first, commits: shas, reason: nil)
  end

  # The message of the revert of +sha+, whose subject was +subject+, for
  # the red run +run_id+ of +workflow+ and the +jobs+ that failed in it.
  def self.revert_message(sha, subject, run_id, jobs, workflow = "CI")
    named = jobs.empty? ? "no failed job named" : "failed jobs #{jobs.join(', ')}"
    <<~MESSAGE
      revert: #{subject}

      #{workflow} run #{run_id} was red, with #{named}, and
      the failed jobs failed again when run again. This commit is the only
      one between the last commit #{workflow} passed and the red one, so
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
      verdict = TrunkWatch.classify_jobs(logs(run), run.attempt)
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

  # The raw log of each of the run's failed jobs. A job whose log cannot
  # be read gives an error that is no outage's, so that an unseen job
  # never lets a run pass as an outage.
  private def logs(run)
    jobs = TrunkWatch.failed_job_ids(@gh.call("run", "view", run.id.to_s, "--repo", @repository, "--json", "jobs"))
    return ["##[error]no failed job of run #{run.id} could be listed\n"] if jobs.empty?

    jobs.map do |id, name|
      raw = @gh.call("api", "--allow-escape-sequences", "repos/#{@repository}/actions/jobs/#{id}/logs")
      raw ? TrunkWatch.strip_ansi(raw) : "##[error]the log of job #{name} (#{id}) could not be read\n"
    end
  end

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

    TrunkWatch.plan(list_runs(100), run.head, graph, run.workflow)
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
    @git.call("commit", "--amend", "-m", TrunkWatch.revert_message(sha, subject, run.id, failed_job_names(run), run.workflow))
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
