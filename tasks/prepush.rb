# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# What .githooks/pre-push runs: the checks a push needs, over what the
# push brings. For each ref git is about to update (it names them on the
# hook's standard input, one "local_ref local_sha remote_ref remote_sha"
# line each) it runs rake prepush, then rake red_before_green over the
# commits the push adds, and fails the push, with the reason, when a
# check fails.
#
# The checks run here, in the clone that pushes, and CI checks Windows
# after the push. Pushing a tag, deleting a ref, and LOTA_PREPUSH=skip run
# nothing; the last is for emergencies. git push --no-verify skips the
# hook itself, as git always allows.
class PrePush
  # What git writes for a ref that does not exist.
  ZERO = "0" * 40

  # Whether the checks run, by LOTA_PREPUSH's value.
  MODES = { "" => :here, "skip" => :skip }.freeze

  # One line of the hook's standard input.
  Push = Data.define(:local_ref, :local_sha, :remote_ref, :remote_sha) do
    # True when the push removes the remote ref.
    def delete? = local_sha == ZERO

    # True when the push creates the remote ref.
    def create? = remote_sha == ZERO

    # True when the push updates a tag.
    def tag? = remote_ref.start_with?("refs/tags/")
  end

  # Runs rake tasks in this clone.
  #
  # git runs the hook with GIT_DIR set, and in a linked worktree more of
  # the variables that point git at a repository. A check that runs git
  # in a repository of its own, as many of Lota's tests do in a temporary
  # one, would reach the pushing clone through them instead. So rake runs
  # without any of the variables git rev-parse --local-env-vars lists, as
  # git itself clears them before it runs a command in a submodule.
  class LocalRunner
    # [repository] Where rake runs.
    # [env] The hook's environment, which rake gets without git's.
    def initialize(repository, env: ENV)
      @repository = repository
      @env = env
    end

    # The command, for Kernel#system, that runs rake with +args+.
    def command(args) = ["bundle", "exec", "rake", *args]

    # The environment rake runs in.
    def environment
      local, status = Open3.capture2("git", "rev-parse", "--local-env-vars")
      raise ArgumentError, "git rev-parse --local-env-vars failed" unless status.success?

      @env.to_h.except(*local.split)
    end

    # Runs rake +args+ here and returns its exit status.
    def run(args)
      system(environment, *command(args), chdir: @repository, unsetenv_others: true) ? 0 : ($?.exitstatus || 1)
    end
  end

  # What the hook asks of the clone it runs in.
  class Git
    def initialize(repository)
      @repository = repository
    end

    # Whether the clone has the commit +sha+.
    def known?(sha) = Open3.capture2e("git", "cat-file", "-e", "#{sha}^{commit}", chdir: @repository).last.success?

    # Whether HEAD has a commit that no ref of the remote +remote+ holds.
    def unpushed?(remote)
      output, status = capture("rev-list", "-n", "1", "HEAD", "--not", "--remotes=#{remote}")
      !status.success? || !output.strip.empty?
    end

    # The commit +ref+ names, or nil.
    def resolve(ref)
      output, status = capture("rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
      output.strip if status.success?
    end

    private def capture(*) = Open3.capture2("git", "-c", "core.quotePath=false", *, chdir: @repository)
  end

  # Parses the hook's standard input into its Pushes.
  def self.pushes(input)
    input.each_line.filter_map do |line|
      fields = line.split
      Push.new(*fields) if fields.size == 4
    end
  end

  # [input] The hook's standard input.
  # [output] Where it says what it does.
  # [env] The environment.
  # [git] The clone, a Git.
  # [repository] Where the checks run from.
  # [local] What runs rake tasks here: #run(args) answering an exit status.
  # [clock] Answers the time in seconds, with #next.
  # [remote] The remote git pushes to, the hook's first argument.
  def initialize(input:, output:, env:, git:, repository:, local: nil, clock: nil, remote: "origin")
    @input = input
    @remote = remote
    @output = output
    @env = env
    @git = git
    @repository = repository
    @local = local || LocalRunner.new(repository, env:)
    @clock = clock || Enumerator.new { |y| loop { y << Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
  end

  # Whether the checks run, from LOTA_PREPUSH: :here or :skip.
  def mode
    value = @env.fetch("LOTA_PREPUSH", "")
    MODES.fetch(value) { raise ArgumentError, "LOTA_PREPUSH is #{value.inspect}; leave it unset, or use skip" }
  end

  # The commit +push+ starts from: the remote ref's old tip when this
  # clone has it, else origin/trunk's.
  def base(push)
    return push.remote_sha unless push.create? || !@git.known?(push.remote_sha)

    @git.resolve("origin/trunk") or raise ArgumentError, "origin/trunk names no commit; run git fetch origin"
  end

  # Runs the checks for each push; returns the hook's exit status.
  def run
    return skipped("LOTA_PREPUSH=skip is set") if mode == :skip

    pushes = self.class.pushes(@input)
    return nothing_to_push if pushes.empty?

    checked = pushes.reject { |push| push.delete? || push.tag? }
    return skipped("nothing but tags or deletions") if checked.empty?

    (checked.all? { |push| here(push) }) ? 0 : 1
  rescue ArgumentError => e
    refuse(e.message)
  end

  # git runs the hook with no refs when the push brings nothing, so no refs
  # pass when the remote holds HEAD. When it does not, a hook that runs this
  # one, such as a global hook in core.hooksPath, has most likely read the
  # refs first, and passing would check nothing.
  private def nothing_to_push
    if @git.unpushed?(@remote)
      return refuse("git gave the hook no refs, but HEAD has commits #{@remote} lacks; " \
        "a hook that runs this one may have read them first")
    end

    say "nothing to push: #{@remote} holds HEAD"
    0
  end

  private def skipped(why)
    say "skipped, #{why}"
    0
  end

  private def here(push)
    range = "#{base(push)}..#{push.local_sha}"
    [["prepush"], ["red_before_green[#{range}]"]].all? do |args|
      name = "rake #{args.first}"
      say "#{name} (here)"
      started = @clock.next
      status = @local.run(args)
      say "#{name} #{status.zero? ? 'passed' : 'failed'} in #{format('%.1f', @clock.next - started)}s"
      status.zero? || (refuse("#{name} failed") && false)
    end
  end

  private def refuse(why)
    say "push refused: #{why}. Fix it and push again " \
      "(git push --no-verify skips the hook, LOTA_PREPUSH=skip is for emergencies)."
    1
  end

  # Writes +text+ as the hook's own line, and answers true.
  private def say(text)
    @output.puts "pre-push: #{text}"
    @output.flush
    true
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  repository = Dir.pwd
  exit(PrePush.new(input: $stdin, output: $stdout, env: ENV, git: PrePush::Git.new(repository), repository:,
    remote: ARGV.fetch(0, "origin")).run)
end
