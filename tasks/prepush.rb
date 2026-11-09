# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require_relative "remote_gate"

# What .githooks/pre-push runs: the checks a push needs, over what the
# push brings. For each ref git is about to update (it names them on the
# hook's standard input, one "local_ref local_sha remote_ref remote_sha"
# line each) it runs rake prepush, then rake red_before_green over the
# commits the push adds, and fails the push, with the reason, when a
# check fails.
#
# The checks run on the gate runner (rake gate:remote) when LOTA_GATE_KEY
# is set, so the computer you type on does no heavy work, and otherwise
# here. Pushing a tag, deleting a ref, and LOTA_PREPUSH=skip run nothing;
# the last is for emergencies. git push --no-verify skips the hook
# itself, as git always allows.
class PrePush
  # What git writes for a ref that does not exist.
  ZERO = "0" * 40

  # One line of the hook's standard input.
  Push = Data.define(:local_ref, :local_sha, :remote_ref, :remote_sha) do
    # True when the push removes the remote ref.
    def delete? = local_sha == ZERO

    # True when the push creates the remote ref.
    def create? = remote_sha == ZERO

    # True when the push updates a tag.
    def tag? = remote_ref.start_with?("refs/tags/")
  end

  # Runs rake tasks on this clone.
  class LocalRunner
    def initialize(repository)
      @repository = repository
    end

    # The command, for Kernel#system, that runs rake with +args+.
    def command(args) = ["bundle", "exec", "rake", *args]

    # Runs rake +args+ here and returns its exit status; +tip+ is not
    # used, as the push is of what is checked out.
    def run(_tip, args)
      system(*command(args), chdir: @repository) ? 0 : ($?.exitstatus || 1)
    end
  end

  # Runs rake tasks on the gate runner, on the commit being pushed.
  class RemoteRunner
    def initialize(repository, env)
      @repository = repository
      @env = env
    end

    # The RemoteGate that runs on +tip+.
    def gate(tip)
      RemoteGate.new(repository: @repository, commit: tip, key: @env.fetch("LOTA_GATE_KEY"),
        host: @env.fetch("LOTA_GATE_HOST", RemoteGate::HOST), runner: @env.fetch("LOTA_GATE_RUNNER", RemoteGate::RUNNER))
    end

    # Runs rake +args+ on the runner and returns its exit status.
    def run(tip, args) = gate(tip).run(args)
  rescue RemoteGate::Failure => e
    warn e.message
    1
  end

  # The runner for +env+: the gate runner when LOTA_GATE_KEY is set and not empty.
  def self.runner(env, repository)
    env.fetch("LOTA_GATE_KEY", "").empty? ? LocalRunner.new(repository) : RemoteRunner.new(repository, env)
  end

  # Parses the hook's standard input into its Pushes.
  def self.pushes(input)
    input.each_line.filter_map do |line|
      fields = line.split
      Push.new(*fields) if fields.size == 4
    end
  end

  # Whether this clone has the commit +sha+.
  def self.known?(sha, repository)
    _, status = Open3.capture2e("git", "cat-file", "-e", "#{sha}^{commit}", chdir: repository)
    status.success?
  end

  # [input] The hook's standard input.
  # [output] Where it says what it does.
  # [env] The environment.
  # [runner] What runs rake tasks: #run(tip, args) answering an exit status.
  # [known] Answers whether this clone has a commit.
  # [clock] Answers the time in seconds, with #next.
  def initialize(input:, output:, env:, runner:, known:, clock: nil)
    @input = input
    @output = output
    @env = env
    @runner = runner
    @known = known
    @clock = clock || Enumerator.new { |y| loop { y << Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
  end

  # The commits +push+ adds, as git rev-list takes them: from the remote
  # ref's old tip when this clone has it, else from origin/trunk.
  def range(push)
    old = (push.create? || !@known.call(push.remote_sha)) ? "origin/trunk" : push.remote_sha
    "#{old}..#{push.local_sha}"
  end

  # Runs the checks for each push; returns the hook's exit status.
  def run
    if @env["LOTA_PREPUSH"] == "skip"
      @output.puts "pre-push: skipped, LOTA_PREPUSH=skip is set"
      return 0
    end
    pushes = self.class.pushes(@input)
    checked = pushes.reject { |push| push.delete? || push.tag? }
    @output.puts "pre-push: skipped, nothing but tags or deletions" if checked.empty? && !pushes.empty?
    checked.each { |push| return 1 unless check(push) }
    0
  end

  private def check(push)
    [["prepush"], ["red_before_green[#{range(push)}]"]].all? do |args|
      @output.puts "pre-push: rake #{args.first} (#{(@runner.class.name.split('::').last == 'RemoteRunner') ? 'on the gate runner' : 'here'})"
      started = @clock.next
      status = @runner.run(push.local_sha, args)
      @output.puts "pre-push: rake #{args.first} #{status.zero? ? 'passed' : 'failed'} in #{format('%.1f', @clock.next - started)}s"
      next true if status.zero?

      @output.puts "pre-push: push refused: rake #{args.first} failed. Fix it and push again " \
        "(git push --no-verify skips the hook, LOTA_PREPUSH=skip is for emergencies)."
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  repository = Dir.pwd
  exit PrePush.new(input: $stdin, output: $stdout, env: ENV, runner: PrePush.runner(ENV, repository),
    known: -> (sha) { PrePush.known?(sha, repository) }).run
end
