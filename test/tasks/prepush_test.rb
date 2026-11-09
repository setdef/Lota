# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/prepush"
require "stringio"

# PrePush reads the refs git hands a pre-push hook, works out which
# checks the push needs and over what range, and runs them through a
# runner: here a fake that records what it was asked to run.
class PrePushTest < Minitest::Test
  ZERO = "0" * 40
  TIP = "a" * 40
  OLD = "b" * 40

  # Stands in for the checks: records each call and answers with the
  # status it was given for the task (0 unless set).
  class FakeRunner
    attr_reader :calls

    def initialize(statuses = {})
      @statuses = statuses
      @calls = []
    end

    def run(tip, args)
      @calls << [tip, args]
      @statuses.fetch(args.first, 0)
    end
  end

  def setup
    @out = StringIO.new
    @runner = FakeRunner.new
  end

  def hook(stdin, env: {}, runner: @runner, known: -> (_sha) { true })
    PrePush.new(input: StringIO.new(stdin), output: @out, env:, runner:, known:, clock: [0.0, 12.5].cycle)
  end

  def line(local: TIP, remote: OLD, ref: "refs/heads/trunk", remote_ref: ref)
    "#{ref} #{local} #{remote_ref} #{remote}\n"
  end

  def test_an_update_checks_exactly_the_pushed_range
    status = hook(line).run

    assert_equal 0, status
    assert_equal [[TIP, ["prepush"]], [TIP, ["red_before_green[#{OLD}..#{TIP}]"]]], @runner.calls
  end

  def test_a_new_branch_is_checked_from_origin_trunk
    hook(line(remote: ZERO, ref: "refs/heads/topic")).run

    assert_equal ["red_before_green[origin/trunk..#{TIP}]"], @runner.calls.last.last
  end

  def test_a_remote_tip_this_clone_lacks_falls_back_to_origin_trunk
    hook(line, known: -> (sha) { sha != OLD }).run

    assert_equal ["red_before_green[origin/trunk..#{TIP}]"], @runner.calls.last.last
  end

  def test_deleting_a_ref_skips_the_checks
    status = hook(line(local: ZERO, ref: "(delete)", remote_ref: "refs/heads/topic")).run

    assert_equal 0, status
    assert_empty @runner.calls
    assert_includes @out.string, "skipped"
  end

  def test_pushing_a_tag_skips_the_checks
    status = hook(line(remote: ZERO, ref: "refs/tags/v1")).run

    assert_equal 0, status
    assert_empty @runner.calls
  end

  def test_a_branch_push_beside_a_tag_checks_only_the_branch
    hook(line(ref: "refs/tags/v1", remote: ZERO) + line).run

    assert_equal 2, @runner.calls.size
  end

  def test_the_emergency_variable_skips_the_checks
    status = hook(line, env: { "LOTA_PREPUSH" => "skip" }).run

    assert_equal 0, status
    assert_empty @runner.calls
    assert_includes @out.string, "LOTA_PREPUSH=skip"
  end

  def test_nothing_on_standard_input_runs_nothing
    assert_equal 0, hook("").run
    assert_empty @runner.calls
  end

  def test_a_failing_prepush_fails_the_push_and_skips_red_before_green
    runner = FakeRunner.new("prepush" => 2)

    status = hook(line, runner:).run

    assert_equal 1, status
    assert_equal 1, runner.calls.size
    assert_includes @out.string, "push refused: rake prepush failed"
  end

  def test_a_failing_red_before_green_fails_the_push
    runner = FakeRunner.new("red_before_green[#{OLD}..#{TIP}]" => 1)

    status = hook(line, runner:).run

    assert_equal 1, status
    assert_includes @out.string, "push refused: rake red_before_green"
  end

  def test_it_says_what_it_runs_and_how_long_it_took
    hook(line).run

    assert_includes @out.string, "pre-push: rake prepush"
    assert_includes @out.string, "passed in 12.5s"
  end

  def test_the_gate_runner_is_chosen_when_the_key_is_set
    assert_instance_of PrePush::RemoteRunner, PrePush.runner({ "LOTA_GATE_KEY" => "~/key" }, "/repo")
    assert_instance_of PrePush::LocalRunner, PrePush.runner({}, "/repo")
    assert_instance_of PrePush::LocalRunner, PrePush.runner({ "LOTA_GATE_KEY" => "" }, "/repo")
  end

  def test_the_local_runner_runs_rake
    assert_equal %w[bundle exec rake prepush], PrePush::LocalRunner.new("/repo").command(["prepush"])
  end

  def test_the_remote_runner_gates_the_pushed_tip_with_the_environments_host
    runner = PrePush::RemoteRunner.new("/repo", { "LOTA_GATE_KEY" => "/k", "LOTA_GATE_HOST" => "h" })

    assert_instance_of RemoteGate, runner.gate(TIP)
  end

  # Stands in for the Windows checks: records each tip it was asked to
  # check and answers with the status it was given.
  class FakeWindows
    attr_reader :tips

    def initialize(status = 0)
      @status = status
      @tips = []
    end

    def host = "pc.test"

    def run(tip)
      @tips << tip
      @status
    end
  end

  def test_the_windows_checks_run_on_the_pushed_tip_after_the_rake_checks
    windows = FakeWindows.new
    status = PrePush.new(input: StringIO.new(line), output: @out, env: {}, runner: @runner, known: -> (_) { true },
      windows:, clock: [0.0, 1.0].cycle).run

    assert_equal 0, status
    assert_equal [TIP], windows.tips
    assert_equal 2, @runner.calls.size
    assert_operator @out.string.index("rake red_before_green"), :<, @out.string.index("the Windows checks (on pc.test)")
  end

  def test_failing_windows_checks_refuse_the_push_and_a_failing_tier_skips_them
    windows = FakeWindows.new(4)
    hook = lambda do |runner|
      PrePush.new(input: StringIO.new(line), output: @out, env: {}, runner:, known: -> (_) { true }, windows:)
    end

    assert_equal 1, hook.call(@runner).run
    assert_includes @out.string, "push refused: the Windows checks failed"
    assert_equal 1, hook.call(FakeRunner.new("prepush" => 2)).run
    assert_equal [TIP], windows.tips
  end

  def test_the_windows_checks_run_only_where_a_host_is_named
    assert_nil PrePush.windows({}, "/repo")
    assert_nil PrePush.windows({ "LOTA_WINDOWS_HOST" => "" }, "/repo")
    runner = PrePush.windows({ "LOTA_WINDOWS_HOST" => "agent@pc.test", "LOTA_WINDOWS_KEY" => "/k" }, "/repo")

    assert_equal "agent@pc.test", runner.host
    assert_equal ["ssh", "-i", "/k", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "agent@pc.test", "x"],
      runner.windows(TIP).command("x")
  end

  def test_the_pushes_are_parsed_from_the_hooks_input
    push = PrePush.pushes(StringIO.new(line)).first

    assert_equal [TIP, OLD, "refs/heads/trunk"], [push.local_sha, push.remote_sha, push.remote_ref]
  end
end
