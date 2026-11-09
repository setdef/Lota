# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "shellwords"
require "tempfile"

# Runs the gate on another computer before a push (rake gate:remote): a
# Linux machine with a gate runner, leased capacity that spares the
# computer you type on and needs no push to find out whether a change is
# good. It sends the commit to test over one ssh connection, as a git
# bundle on the connection's standard input, has the runner fetch it and
# run the gate on it, prints what the gate prints as it prints it, and
# gives back the gate's exit status.
#
# The commit is HEAD when the working tree is clean, and otherwise a
# commit of the working tree as git add --all would stage it, made with an
# index of its own, so nothing you staged, no branch, and no stash
# changes. The bundle holds only what +base+ (origin/trunk) lacks, which
# the runner fetches from origin first; a commit +base+ already holds
# goes by its name alone.
#
# The runner is a folder on the host (+runner+, ~/lota-gate) holding a
# clone of Lota's origin in +lota+, a script +run+ that takes a branch of
# that clone and the rake arguments and prints GATE_EXIT=<status> last,
# and +locks/fetch+, which every fetch into the clone holds.
class RemoteGate
  # Raised when the commit cannot be made or bundled.
  class Failure < StandardError; end

  # The host, as ssh names it, of the maintainer's gate runner.
  HOST = "agent@192.168.10.114"

  # Where the runner lives on the host, as its shell expands it.
  RUNNER = "~/lota-gate"

  # The branch the bundle is fetched into in the runner's clone.
  BRANCH = "remote-gate"

  # The ref the bundle carries the commit under.
  REF = "refs/#{BRANCH}/commit".freeze

  # [repository] The checkout whose commit or working tree is sent.
  # [host] The ssh destination.
  # [key] An identity file for ssh's -i, or nil for ssh's own choice.
  # [runner] The runner's folder on the host.
  # [base] What the host already has, which the bundle leaves out.
  # [ssh] The ssh program.
  # [commit] A commit to run the gate on instead of HEAD or the working
  #          tree, such as the tip of a push.
  def initialize(repository:, host: HOST, key: nil, runner: RUNNER, base: "origin/trunk", ssh: "ssh", commit: nil)
    @repository = repository
    @host = host
    @key = key
    @runner = runner
    @base = base
    @ssh = ssh
    @given = commit
  end

  # The commit the gate runs on: HEAD, or the working tree's commit.
  def commit
    @commit ||= if @given
      git("rev-parse", "--verify", "#{@given}^{commit}")
    else
      clean? ? git("rev-parse", "HEAD") : snapshot
    end
  end

  # The ssh command, for Kernel#system, that runs the gate with
  # +rake_args+ (the full gate when empty) on what the bundle on its
  # standard input holds, or on +commit+ itself when +bundled+ is false.
  def command(rake_args, bundled:)
    options = @key ? ["-i", File.expand_path(@key)] : []
    [@ssh, *options, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", @host, script(rake_args, bundled:)]
  end

  # Runs the gate on the host with +rake_args+, printing what it prints,
  # and returns its exit status: the gate's, or ssh's own when ssh fails.
  def run(rake_args = [])
    $stdout.puts "remote gate: #{commit[0, 12]}#{' (the working tree)' unless @given || clean?} on #{@host}"
    $stdout.flush
    Tempfile.create(["lota-remote-gate", ".bundle"]) do |bundle|
      bundled = bundle(bundle.path)
      system(*command(rake_args, bundled:), in: bundled ? bundle.path : File::NULL)
      $?.exitstatus || 1
    end
  end

  # Writes the bundle of +commit+ less +base+ to +path+; returns false,
  # writing nothing, when +base+ already holds +commit+.
  def bundle(path)
    base = git_ok?("rev-parse", "--verify", "--quiet", "#{@base}^{commit}") ? @base : nil
    return false if base && git_ok?("merge-base", "--is-ancestor", commit, base)

    git("update-ref", REF, commit)
    begin
      git("bundle", "create", "--quiet", path, REF, *("^#{base}" if base))
    ensure
      git("update-ref", "-d", REF)
    end
    true
  end

  private def script(rake_args, bundled:)
    run = "#{@runner}/run"
    target = bundled ? "#{BRANCH}/#{commit}" : commit
    fetch = if bundled
      lota = "#{@runner}/lota"
      "bundle=$(mktemp) && cat > \"$bundle\" && " \
        "flock #{@runner}/locks/fetch sh -c 'git -C #{lota} fetch -q origin && " \
        "git -C #{lota} fetch -q \"$0\" +#{REF}:refs/heads/#{target}' \"$bundle\"; " \
        "status=$?; rm -f \"$bundle\"; [ $status -eq 0 ] || { echo GATE_EXIT=$status; exit $status; }; "
    else
      ""
    end
    "#{fetch}exec #{run} #{Shellwords.join([target, *rake_args])}"
  end

  private def clean? = git("status", "--porcelain", "--untracked-files=normal").empty?

  # A commit of the working tree on top of HEAD, staged with a copy of the
  # index, so the real one is untouched.
  private def snapshot
    Tempfile.create("lota-remote-gate-index") do |index|
      index.close
      FileUtils.cp(git("rev-parse", "--path-format=absolute", "--git-path", "index"), index.path)
      environment = { "GIT_INDEX_FILE" => index.path }
      git("add", "--all", environment:)
      tree = git("write-tree", environment:)
      git("commit-tree", tree, "-p", "HEAD", "-m", "The working tree, for the remote gate")
    end
  end

  private def git(*args, environment: {})
    output, error, status = Open3.capture3(environment, "git", *args, chdir: @repository)
    raise Failure, "git #{args.join(' ')} failed: #{error}" unless status.success?

    output.strip
  end

  private def git_ok?(*)
    _, _, status = Open3.capture3("git", *, chdir: @repository)
    status.success?
  end
end
