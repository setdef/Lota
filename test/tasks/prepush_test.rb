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
  # status it was given for the task (0 unless set).
  class FakeLocal
    attr_reader :calls

    def initialize(statuses = {})
      @statuses = statuses
      @calls = []
    end

    def run(args)
      @calls << args
      @statuses.fetch(args.first, 0)
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
    assert_equal [["prepush"], ["red_before_green[#{@trunk}..#{tip}]"]], @local.calls
    assert_includes @out.string, "pre-push: rake prepush (here)"
    assert_includes @out.string, "passed in 12.5s"
  end

  def test_a_new_branch_is_checked_from_origin_trunk
    tip = commit("lib/a.rb", "a\n", "second")

    hook(line(local: tip, remote: ZERO, ref: "refs/heads/topic")).run

    assert_equal ["red_before_green[#{@trunk}..#{tip}]"], @local.calls.last
  end

  def test_a_remote_tip_this_clone_lacks_falls_back_to_origin_trunk
    tip = commit("lib/a.rb", "a\n", "second")

    hook(line(local: tip, remote: "c" * 40)).run

    assert_equal ["red_before_green[#{@trunk}..#{tip}]"], @local.calls.last
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

    assert_equal 2, @local.calls.size
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

  def test_a_failing_prepush_fails_the_push_and_skips_red_before_green
    tip = commit("lib/a.rb", "a\n", "second")
    local = FakeLocal.new("prepush" => 2)

    assert_equal 1, hook(line(local: tip), local:).run
    assert_equal [["prepush"]], local.calls
    assert_includes @out.string, "push refused: rake prepush failed"
  end

  def test_a_failing_red_before_green_fails_the_push
    tip = commit("lib/a.rb", "a\n", "second")
    local = FakeLocal.new("red_before_green[#{@trunk}..#{tip}]" => 1)

    assert_equal 1, hook(line(local: tip), local:).run
    assert_includes @out.string, "push refused: rake red_before_green"
  end

  def test_an_unknown_mode_refuses_the_push
    tip = commit("lib/a.rb", "a\n", "second")

    assert_equal 1, hook(line(local: tip), env: { "LOTA_PREPUSH" => "remote" }).run
    assert_includes @out.string, 'push refused: LOTA_PREPUSH is "remote"; leave it unset, or use machines or skip'
    assert_empty @local.calls
  end
end
