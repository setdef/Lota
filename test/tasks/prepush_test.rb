# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/prepush"
require "stringio"

# PrePush reads the refs git hands a pre-push hook, works out which
# checks the push needs and over what range in a real repository, and
# runs them here through a runner that records what it was asked to run.
class PrePushTest < Minitest::Test
  include TreeHelper

  ZERO = "0" * 40

  # Stands in for rake here: records each call and answers with the
  # status it was given for the task, by its name without its arguments
  # (0 unless set).
  class FakeLocal
    attr_reader :calls

    def initialize(statuses = {})
      @statuses = statuses
      @calls = []
    end

    def run(args)
      @calls << args
      @statuses.fetch(args.first[/\A[^\[]*/], 0)
    end
  end

  def setup
    @tree = File.realpath(Dir.mktmpdir("lota-prepush"))
    @repo = File.join(@tree, "repo")
    @out = StringIO.new
    @local = FakeLocal.new
    run!(@tree, "git", "init", "--quiet", "--initial-branch=trunk", @repo)
    @trunk = commit("README.md", "Sample Game\n", "first")
    run!(@repo, "git", "update-ref", "refs/remotes/origin/trunk", @trunk)
  end

  def teardown
    FileUtils.rm_rf(@tree)
  end

  def commit(path, content, subject)
    write(@repo, path, content)
    run!(@repo, "git", "add", "--all")
    run!(@repo, "git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "-m", subject)
    run!(@repo, "git", "rev-parse", "HEAD").strip
  end

  # The hook as git runs it, with +env+.
  def hook(stdin, env: {}, local: @local)
    PrePush.new(input: StringIO.new(stdin), output: @out, env:, git: PrePush::Git.new(@repo), repository: @repo,
      local:, clock: [0.0, 12.5].cycle)
  end

  def line(local:, remote: @trunk, ref: "refs/heads/trunk", remote_ref: ref)
    "#{ref} #{local} #{remote_ref} #{remote}\n"
  end

  def test_by_default_the_checks_run_here_over_exactly_the_pushed_range
    tip = commit("lib/a.rb", "a\n", "second")

    status = hook(line(local: tip)).run

    assert_equal 0, status
    assert_equal [["push_check[#{@trunk}..#{tip}]"]], @local.calls
    assert_includes @out.string, "pre-push: rake push_check[#{@trunk}..#{tip}] (here)"
    assert_includes @out.string, "passed in 12.5s"
  end

  # The hook is the same wherever it runs: it neither runs the pre-push
  # tier, which builds the engine, nor a set of checks of Windows' own.
  def test_the_hook_runs_push_check_alone
    tip = commit("ext/lota/windows_paths.cpp", "a\n", "second")

    hook(line(local: tip)).run

    assert_equal ["push_check"], @local.calls.map { |args| args.first[/\A[^\[]*/] }
  end

  def test_a_new_branch_is_checked_from_origin_trunk
    tip = commit("lib/a.rb", "a\n", "second")

    hook(line(local: tip, remote: ZERO, ref: "refs/heads/topic")).run

    assert_equal ["push_check[#{@trunk}..#{tip}]"], @local.calls.last
  end

  def test_a_remote_tip_this_clone_lacks_falls_back_to_origin_trunk
    tip = commit("lib/a.rb", "a\n", "second")

    hook(line(local: tip, remote: "c" * 40)).run

    assert_equal ["push_check[#{@trunk}..#{tip}]"], @local.calls.last
  end

  def test_deleting_a_ref_pushing_a_tag_and_the_emergency_variable_skip_the_checks
    tip = commit("lib/a.rb", "a\n", "second")

    assert_equal 0, hook(line(local: ZERO, ref: "(delete)", remote_ref: "refs/heads/topic")).run
    assert_equal 0, hook(line(local: tip, remote: ZERO, ref: "refs/tags/v1")).run
    assert_equal 0, hook(line(local: tip), env: { "LOTA_PREPUSH" => "skip" }).run
    assert_empty @local.calls
    assert_includes @out.string, "skipped, nothing but tags or deletions"
    assert_includes @out.string, "skipped, LOTA_PREPUSH=skip is set"
  end

  def test_a_branch_push_beside_a_tag_checks_only_the_branch
    tip = commit("lib/a.rb", "a\n", "second")

    hook(line(local: tip, ref: "refs/tags/v1", remote: ZERO) + line(local: tip)).run

    assert_equal [["push_check[#{@trunk}..#{tip}]"]], @local.calls
  end

  def test_no_refs_on_standard_input_pass_only_when_the_remote_holds_head
    assert_equal 0, hook("").run
    assert_includes @out.string, "pre-push: nothing to push: origin holds HEAD"

    commit("lib/a.rb", "a\n", "second")

    assert_equal 1, hook("").run
    assert_includes @out.string, "push refused: git gave the hook no refs, but HEAD has commits origin lacks; " \
      "a hook that runs this one may have read them first"
    assert_empty @local.calls
  end

  def test_a_failing_push_check_fails_the_push
    tip = commit("lib/a.rb", "a\n", "second")
    local = FakeLocal.new("push_check" => 2)

    assert_equal 1, hook(line(local: tip), local:).run
    assert_includes @out.string, "push refused: rake push_check[#{@trunk}..#{tip}] failed"
  end

  def test_the_first_ref_whose_checks_fail_refuses_the_push_without_checking_the_rest
    tip = commit("lib/a.rb", "a\n", "second")
    local = FakeLocal.new("push_check" => 1)

    assert_equal 1, hook(line(local: tip) + line(local: tip, remote: ZERO, ref: "refs/heads/topic"), local:).run
    assert_equal 1, local.calls.size
  end

  # git runs the hook with GIT_DIR, and in a linked worktree more, set to
  # the clone that pushes; a check that made a repository of its own would
  # reach that clone instead, so the checks run without them, as git runs
  # a command in a submodule.
  def test_the_checks_run_without_the_variables_that_point_git_at_the_pushing_clone
    tip = commit("lib/a.rb", "a\n", "second")
    seen = File.join(@tree, "seen")
    git = { "GIT_DIR" => File.join(@repo, ".git"), "GIT_INDEX_FILE" => File.join(@repo, ".git", "index") }
    env = ENV.to_h.merge(git, "LOTA_PREPUSH_PROBE" => "kept")
    local = PrePush::LocalRunner.new(@repo, env:)
    local.define_singleton_method(:command) do |_args|
      [RbConfig.ruby, "-e", "File.write(ARGV[0], ENV.keys.join(' '))", seen]
    end

    assert_equal 0, hook(line(local: tip), env:, local:).run
    names = File.read(seen).split
    assert_includes names, "LOTA_PREPUSH_PROBE"
    assert_empty names & git.keys
  end

  # Stands in for a check that rewrites a file, as RuboCop's autocorrection: rewrites +path+ in the
  # repository, then passes.
  class Fixer < FakeLocal
    def initialize(repo, path, statuses = {})
      super(statuses)
      @repo = repo
      @path = path
    end

    def run(args)
      File.write(File.join(@repo, @path), "fixed\n") if args.first.start_with?("push_check[")
      super
    end
  end

  def test_a_check_that_changes_a_tracked_file_puts_it_back_and_fails_the_push
    tip = commit("lib/a.rb", "a\n", "second")
    local = Fixer.new(@repo, "lib/a.rb")

    assert_equal 1, hook(line(local: tip), local:).run
    assert_equal "a\n", File.read(File.join(@repo, "lib/a.rb"))
    assert_includes @out.string, "push refused: rake push_check[#{@trunk}..#{tip}] changed lib/a.rb, now put back"
  end

  def test_a_failing_check_that_changes_a_tracked_file_puts_it_back_too
    tip = commit("lib/a.rb", "a\n", "second")
    local = Fixer.new(@repo, "lib/a.rb", { "push_check" => 1 })

    assert_equal 1, hook(line(local: tip), local:).run
    assert_equal "a\n", File.read(File.join(@repo, "lib/a.rb"))
    assert_includes @out.string, "push refused: rake push_check[#{@trunk}..#{tip}] failed"
  end

  def test_putting_back_what_a_check_changed_keeps_edits_made_before_it
    tip = commit("lib/a.rb", "a\n", "second")
    write(@repo, "README.md", "an edit of the contributor's own\n")
    write(@repo, "lib/a.rb", "an edit the check rewrites\n")
    local = Fixer.new(@repo, "lib/a.rb")

    assert_equal 1, hook(line(local: tip), local:).run
    assert_equal "an edit of the contributor's own\n", File.read(File.join(@repo, "README.md"))
    assert_equal "an edit the check rewrites\n", File.read(File.join(@repo, "lib/a.rb"))
  end

  def test_an_unknown_mode_refuses_the_push
    tip = commit("lib/a.rb", "a\n", "second")

    assert_equal 1, hook(line(local: tip), env: { "LOTA_PREPUSH" => "remote" }).run
    assert_includes @out.string, 'push refused: LOTA_PREPUSH is "remote"; leave it unset, or use skip'
    assert_empty @local.calls
  end

  # A clone made for the push alone may hold no origin/trunk, only the
  # remote's default branch, origin/HEAD.
  def test_a_new_branch_without_origin_trunk_is_checked_from_origin_head
    tip = commit("lib/a.rb", "a\n", "second")
    run!(@repo, "git", "update-ref", "-d", "refs/remotes/origin/trunk")
    run!(@repo, "git", "update-ref", "refs/remotes/origin/HEAD", @trunk)

    hook(line(local: tip, remote: ZERO, ref: "refs/heads/topic")).run

    assert_equal ["push_check[#{@trunk}..#{tip}]"], @local.calls.last
  end

  # A refusal says what git said, since a check that cannot start is
  # otherwise a mystery on a machine no one is watching.
  def test_a_snapshot_git_cannot_make_says_why
    empty = File.join(@tree, "empty")
    run!(@tree, "git", "init", "--quiet", empty)
    error = assert_raises(ArgumentError) { PrePush::Git.new(empty).snapshot }

    assert_match(/\Agit stash failed: .*initial commit/, error.message)
  end

  # A checkout that rewrites a file unchanged, as a copy into a build
  # machine's workspace may, leaves the index's stat data stale.
  def test_a_file_rewritten_unchanged_is_not_a_change
    tip = commit("lib/a.rb", "a\n", "second")
    later = Time.now + 5
    File.utime(later, later, File.join(@repo, "lib/a.rb"))

    assert_equal tip, PrePush::Git.new(@repo).snapshot
  end
end
