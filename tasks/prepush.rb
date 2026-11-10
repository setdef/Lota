# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require "time"
require_relative "machines_run"

# What .githooks/pre-push runs: the checks a push needs, over what the
# push brings. For each ref git is about to update (it names them on the
# hook's standard input, one "local_ref local_sha remote_ref remote_sha"
# line each) it runs rake prepush, then rake red_before_green over the
# commits the push adds, and fails the push, with the reason, when a
# check fails.
#
# By default the checks run here, in the clone that pushes, and CI checks
# Windows after the push. With LOTA_PREPUSH=machines they run on build
# machines through the machines command (tasks/machines_run.rb) instead,
# and never here: script/remote-gate prepush on a Linux machine, and, when
# the push could break on Windows (WindowsRule), Lota's Windows checks
# (.github/windows_prepush.sh) on a Windows machine at the same time.
# Then a push also fails when the machines cannot run them.
#
# Pushing a tag, deleting a ref, and LOTA_PREPUSH=skip run nothing; the
# last is for emergencies. LOTA_PREPUSH_WINDOWS=always or never overrides
# WindowsRule. git push --no-verify skips the hook itself, as git always
# allows.
class PrePush
  # What git writes for a ref that does not exist.
  ZERO = "0" * 40

  # Where the checks run, by LOTA_PREPUSH's value.
  MODES = { "" => :here, "machines" => :machines, "skip" => :skip }.freeze

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
  class LocalRunner
    def initialize(repository)
      @repository = repository
    end

    # The command, for Kernel#system, that runs rake with +args+.
    def command(args) = ["bundle", "exec", "rake", *args]

    # Runs rake +args+ here and returns its exit status.
    def run(args)
      system(*command(args), chdir: @repository) ? 0 : ($?.exitstatus || 1)
    end
  end

  # Decides whether a push needs the Windows checks, from the paths it
  # changes and the lines it adds or removes: a change to the native
  # code, to the dependencies, or to anything of Windows' own, or a path or
  # line that names Windows, MinGW, Win32 or a DLL.
  class WindowsRule
    # What names Windows in a path or a line.
    WORDS = /windows|mingw|win32|\.dll/i

    # The files that pin Lota's dependencies.
    DEPENDENCIES = %w[Gemfile Gemfile.lock lota.gemspec mise.toml].freeze

    # Each clause a changed path can meet, by the name the hook reports.
    CLAUSES = {
      "ext/" => -> (path) { path.start_with?("ext/") },
      DEPENDENCIES.join(", ") => -> (path) { DEPENDENCIES.include?(path) },
      "tasks/windows*" => -> (path) { path.start_with?("tasks/windows") },
      ".github/windows*" => -> (path) { path.start_with?(".github/windows") },
      "test/native/windows*" => -> (path) { path.start_with?("test/native/windows") },
      "a path matching #{WORDS.source}" => -> (path) { WORDS.match?(path) },
    }.freeze

    # The clause a change met, and the path that met it (nil for an
    # override).
    class Verdict < Data.define(:clause, :path)
      # The verdict as words.
      def to_s = path ? "#{clause} (#{path})" : clause
    end

    # [override] LOTA_PREPUSH_WINDOWS: "always", "never", or empty.
    def initialize(override)
      raise ArgumentError, "LOTA_PREPUSH_WINDOWS is #{override.inspect}; leave it unset, or use always or never" \
        unless ["", "always", "never"].include?(override)

      @override = override
    end

    # Whether LOTA_PREPUSH_WINDOWS=never leaves the rule nothing to decide.
    def never? = @override == "never"

    # The Verdict for +changes+, each changed path with the lines it adds
    # or removes, or nil when the push needs no Windows checks.
    def verdict(changes)
      return Verdict.new(clause: "LOTA_PREPUSH_WINDOWS=always", path: nil) if @override == "always"
      return if never?

      CLAUSES.each do |clause, meets|
        path = changes.each_key.find(&meets)
        return Verdict.new(clause:, path:) if path
      end
      path, = changes.find { |_path, lines| lines.any? { |line| WORDS.match?(line) } }
      Verdict.new(clause: "a changed line matching #{WORDS.source}", path:) if path
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

    # The paths the commits from +old+ to +new+ change, each with the lines
    # they add or remove, as WindowsRule#verdict takes them.
    def changes(old, new)
      range = "#{old}...#{new}"
      names, = capture("diff", "--name-only", "--no-renames", "-z", range)
      changes = names.split("\0").to_h { |path| [path, []] }
      diff, = capture("diff", "--no-color", "--no-ext-diff", "--no-renames", "--unified=0", range)
      self.class.changed_lines(diff).each { |path, lines| (changes[path] ||= []).concat(lines) }
      changes
    end

    # The lines a unified +diff+ adds or removes, by the path they are in.
    def self.changed_lines(diff)
      path = nil
      diff.b.each_line.with_object(Hash.new { |hash, key| hash[key] = [] }) do |line, lines|
        if (header = line[%r{\A(?:---|\+\+\+) [ab]/(.*?)\n?\z}, 1])
          path = header.dup.force_encoding(Encoding::UTF_8)
        elsif line.start_with?("+", "-") && !line.start_with?("+++ ", "--- ")
          lines[path] << line[1..].chomp if path
        end
      end
    end

    # The file the hook records each time WindowsRule fires, in the clone's
    # own git folder, which every worktree shares.
    def windows_log
      common, = capture("rev-parse", "--path-format=absolute", "--git-common-dir")
      File.join(common.strip, "lota-prepush-windows.log")
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
  # [machines] What runs on the build machines, a MachinesRun.
  # [clock] Answers the time in seconds, with #next.
  # [remote] The remote git pushes to, the hook's first argument.
  def initialize(input:, output:, env:, git:, repository:, local: nil, machines: nil, clock: nil, remote: "origin")
    @input = input
    @remote = remote
    @output = output
    @env = env
    @git = git
    @repository = repository
    @local = local || LocalRunner.new(repository)
    @machines = machines || MachinesRun.new(env:)
    @clock = clock || Enumerator.new { |y| loop { y << Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
  end

  # Where the checks run, from LOTA_PREPUSH: :here, :machines, or :skip.
  def mode
    value = @env.fetch("LOTA_PREPUSH", "")
    MODES.fetch(value) { raise ArgumentError, "LOTA_PREPUSH is #{value.inspect}; leave it unset, or use machines or skip" }
  end

  # The commit +push+ starts from: the remote ref's old tip when this
  # clone has it, else origin/trunk's.
  def base(push)
    return push.remote_sha unless push.create? || !@git.known?(push.remote_sha)

    @git.resolve("origin/trunk") or raise ArgumentError, "origin/trunk names no commit; run git fetch origin"
  end

  # Runs the checks for each push; returns the hook's exit status.
  def run
    where = mode
    return skipped("LOTA_PREPUSH=skip is set") if where == :skip

    rule = WindowsRule.new(@env.fetch("LOTA_PREPUSH_WINDOWS", ""))
    pushes = self.class.pushes(@input)
    return nothing_to_push if pushes.empty?

    checked = pushes.reject { |push| push.delete? || push.tag? }
    return skipped("nothing but tags or deletions") if checked.empty? && !pushes.empty?

    (checked.all? { |push| (where == :machines) ? on_machines(push, rule) : here(push) }) ? 0 : 1
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

  private def on_machines(push, rule)
    old = base(push)
    runs = [@machines.linux_prepush(old:, new: push.local_sha)]
    runs << @machines.windows_prepush(new: push.local_sha) if windows?(push, old, rule)
    say "checking #{old[0, 12]}..#{push.local_sha[0, 12]} on the build machines (#{runs.map(&:name).join(' and ')})"
    started = @clock.next
    results = @machines.run_all(runs, output: @output, chdir: @repository)
    elapsed = format("%.1f", @clock.next - started)
    results.each { |result| say "#{result.name} #{result.passed? ? 'passed' : "failed: #{result.reason}"}" }
    failed = results.reject(&:passed?)
    return say("the checks passed in #{elapsed}s") if failed.empty?

    refuse(failed.map { |result| "#{result.name}: #{result.reason}" }.join("; "))
    false
  end

  private def windows?(push, old, rule)
    return !say("the Windows checks are skipped: LOTA_PREPUSH_WINDOWS=never") if rule.never?

    verdict = rule.verdict(@git.changes(old, push.local_sha))
    return !say("the Windows rule did not fire for #{push.local_sha[0, 12]}: Linux only") unless verdict

    line = "the Windows rule fired for #{push.remote_ref} #{push.local_sha[0, 12]}: #{verdict}"
    say line
    File.open(@git.windows_log, "a") { |log| log.puts("#{Time.now.utc.iso8601} #{line}") }
    true
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
  exit(MachinesRun.outside_bundle do
    PrePush.new(input: $stdin, output: $stdout, env: ENV, git: PrePush::Git.new(repository), repository:,
      remote: ARGV.fetch(0, "origin")).run
  end)
end
