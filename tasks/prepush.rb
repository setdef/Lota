# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require_relative "windows_affected"

# What .githooks/pre-push runs: the checks a push needs, over what the
# push brings. For each ref git is about to update (it names them on the
# hook's standard input, one "local_ref local_sha remote_ref remote_sha"
# line each) it runs rake prepush, then rake red_before_green over the
# commits the push adds, and fails the push, with the reason, when a
# check fails or changes a tracked file, which it then puts back.
#
# The checks run here, in the clone that pushes. On Windows, where the
# gate cannot run, the hook runs Lota's Windows checks instead
# (.github/windows_prepush.sh), and only when a pushed range can change
# Lota there (WindowsAffected); elsewhere CI checks Windows after the push.
# Pushing a tag, deleting a ref, and LOTA_PREPUSH=skip run nothing; the
# last is for emergencies. git push --no-verify skips the hook itself, as
# git always allows.
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

  # Runs a command in this clone: rake tasks, unless given another.
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
    # [command] What runs, before its arguments.
    def initialize(repository, env: ENV, command: %w[bundle exec rake])
      @repository = repository
      @env = env
      @command = command
    end

    # The command, for Kernel#system, that runs with +args+.
    def command(args) = [*@command, *args]

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

    # A commit of the working tree as it is, or HEAD when it is clean,
    # made without touching the working tree or the stash. The index's
    # stat data is refreshed first: git stash create exits 1, saying
    # nothing, when a file's stat data is stale though its contents are
    # not, as in a checkout whose files were rewritten unchanged.
    def snapshot
      capture!("update-index", "-q", "--refresh")
      output = capture!("stash", "create")
      output.strip.empty? ? resolve("HEAD") : output.strip
    end

    # The tracked files whose contents differ from the commit +snapshot+'s.
    def changed_since(snapshot)
      capture!("diff", "--name-only", "-z", snapshot, "--").split("\0")
    end

    # Puts +paths+ back as the commit +snapshot+ has them, in the working
    # tree alone.
    def restore(snapshot, paths)
      return if paths.empty?

      capture!("restore", "--source=#{snapshot}", "--worktree", "--", *paths)
    end

    # The commit +ref+ names, or nil.
    def resolve(ref)
      output, status = capture("rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
      output.strip if status.success?
    end

    private def capture(*) = Open3.capture2("git", "-c", "core.quotePath=false", *, chdir: @repository)

    # The output of git +args+, or ArgumentError with what git said when
    # it fails, so that the refusal says why.
    private def capture!(*args)
      output, error, status = Open3.capture3("git", "-c", "core.quotePath=false", *args, chdir: @repository)
      raise ArgumentError, "git #{args.first} failed: #{error.strip}" unless status.success?

      output
    end
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
  # [platform] The platform the hook runs on, as RUBY_PLATFORM names it.
  # [windows] What runs the Windows checks there: #run([]) answering an
  #   exit status.
  def initialize(input:, output:, env:, git:, repository:, local: nil, clock: nil, remote: "origin",
    platform: RUBY_PLATFORM, windows: nil
  )
    @input = input
    @remote = remote
    @output = output
    @env = env
    @git = git
    @repository = repository
    @local = local || LocalRunner.new(repository, env:)
    @platform = platform
    @windows = windows || LocalRunner.new(repository, env:, command: %w[bash .github/windows_prepush.sh])
    @clock = clock || Enumerator.new { |y| loop { y << Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
  end

  # Whether the checks run, from LOTA_PREPUSH: :here or :skip.
  def mode
    value = @env.fetch("LOTA_PREPUSH", "")
    MODES.fetch(value) { raise ArgumentError, "LOTA_PREPUSH is #{value.inspect}; leave it unset, or use skip" }
  end

  # The commit +push+ starts from: the remote ref's old tip when this
  # clone has it, else origin/trunk's, or, in a clone that holds no
  # origin/trunk, the remote's default branch's.
  def base(push)
    return push.remote_sha unless push.create? || !@git.known?(push.remote_sha)

    @git.resolve("origin/trunk") || @git.resolve("origin/HEAD") or
      raise ArgumentError, "origin/trunk names no commit; run git fetch origin"
  end

  # Runs the checks for each push; returns the hook's exit status.
  def run
    return skipped("LOTA_PREPUSH=skip is set") if mode == :skip

    pushes = self.class.pushes(@input)
    return nothing_to_push if pushes.empty?

    checked = pushes.reject { |push| push.delete? || push.tag? }
    return skipped("nothing but tags or deletions") if checked.empty?

    return windows(checked) if @platform.match?(/mingw|mswin/)

    (checked.all? { |push| here(push) }) ? 0 : 1
  rescue ArgumentError, WindowsAffected::Failure => e
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
      snapshot = @git.snapshot
      status = @local.run(args)
      say "#{name} #{status.zero? ? 'passed' : 'failed'} in #{format('%.1f', @clock.next - started)}s"
      unchanged = unchanged?(name, snapshot)
      next refuse("#{name} failed") && false unless status.zero?

      unchanged
    end
  end

  # Runs the Windows checks once when any of +pushes+ can change Lota on
  # Windows, and nothing when none can.
  private def windows(pushes)
    ranges = pushes.map { |push| "#{base(push)}..#{push.local_sha}" }
    range, verdict = ranges.lazy.map { |each| [each, WindowsAffected.verdict(WindowsAffected.changes(@repository, each))] }
      .find { |_range, found| found }
    return skipped_windows(ranges) unless verdict

    say "Windows checks (here): #{range} can change Lota on Windows: #{verdict}"
    started = @clock.next
    status = @windows.run([])
    say "Windows checks #{status.zero? ? 'passed' : 'failed'} in #{format('%.1f', @clock.next - started)}s"
    status.zero? ? 0 : refuse("the Windows checks failed")
  end

  private def skipped_windows(ranges)
    say "#{ranges.join(', ')} cannot change Lota on Windows; no Windows checks"
    0
  end

  # Whether the check +name+ left every tracked file as it found it. A
  # file it changed, as RuboCop's autocorrection changes one, is put back,
  # since the next check needs the commits as they are, and the push is
  # refused, as CI's gate fails when a check changes a file.
  private def unchanged?(name, snapshot)
    changed = @git.changed_since(snapshot)
    return true if changed.empty?

    @git.restore(snapshot, changed)
    refuse("#{name} changed #{changed.join(', ')}, now put back; " \
      "run bundle exec rake rubocop:autocorrect_all and commit what it changes") && false
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
