# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"

# Keeps trunk's GitHub Actions runs green for anyone who wants a hand with
# it (bin/trunk-watch). It lists the trunk's completed runs, and for each
# failed one reads the failed steps' log: a run that failed only because
# GitHub's runners or a download broke is run again, and any other failure
# stops the watch so that whoever started it learns that trunk is red.
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

  # What to do about a failed run: +action+ is :rerun or :stop, and
  # +errors+ are the log's error lines.
  class Verdict < Data.define(:action, :errors)
  end

  # A failed run's id, attempt, short commit, and workflow's name.
  class Run < Data.define(:id, :attempt, :sha, :workflow)
  end

  # The verdict on a failed run's +log+ at +attempt+: :rerun when every
  # error line is an outage's or noise and the attempt is below ATTEMPTS,
  # otherwise :stop.
  def self.classify(log, attempt)
    errors = log.lines(chomp: true).grep(ERROR_LINE)
    real = errors.grep_v(OUTAGE).grep_v(NOISE)
    Verdict.new(action: (real.empty? && attempt < ATTEMPTS) ? :rerun : :stop, errors:)
  end

  # Starts a watch of +repository+ ("owner/name"). +gh+ is a callable that
  # takes the arguments of a gh command and returns its standard output,
  # or nil if it failed. The watch looks at runs with an id above +floor+
  # every +interval+ seconds, waits with +pause+, and tells +out+ what it
  # does.
  def initialize(repository:, gh:, floor: 0, interval: 180, out: $stdout, pause: Kernel.method(:sleep), clock: Time)
    @repository = repository
    @gh = gh
    @floor = floor
    @interval = interval
    @out = out
    @pause = pause
    @clock = clock
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
  # rerun; returns the first Run to stay red, after printing it, or nil.
  def check
    failed_runs.each do |run|
      verdict = TrunkWatch.classify(log(run), run.attempt)
      if verdict.action == :rerun
        rerun(run)
      else
        report(run, verdict)
        return run
      end
    end
    nil
  end

  private def failed_runs
    json = @gh.call("run", "list", "--repo", @repository, "--branch", "trunk", "--limit", "15",
      "--json", "databaseId,status,conclusion,attempt,headSha,workflowName")
    JSON.parse(json || "[]").filter_map do |run|
      next unless run["status"] == "completed" && run["conclusion"] == "failure" && run["databaseId"] > @floor

      Run.new(id: run["databaseId"], attempt: run["attempt"], sha: run["headSha"][0, 7], workflow: run["workflowName"])
    end
  end

  private def log(run) = @gh.call("run", "view", run.id.to_s, "--repo", @repository, "--log-failed").to_s

  private def rerun(run)
    return unless @gh.call("run", "rerun", run.id.to_s, "--repo", @repository, "--failed")

    @out.puts "#{@clock.now.utc.strftime('%H:%MZ')} reran #{run.id} (#{run.sha} #{run.workflow}, attempt #{run.attempt}) after an outage"
  end

  private def report(run, verdict)
    @out.puts "TRUNK RED: run #{run.id} (#{run.sha} #{run.workflow}), attempt #{run.attempt}"
    @out.puts verdict.errors.first(SHOWN)
  end
end
