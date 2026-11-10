# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "fake_machines"
require_relative "../../tasks/prepush"
require "stringio"

# PrePush reads the refs git hands a pre-push hook, works out which
# checks the push needs and over what range in a real repository, and
# runs them here through a runner that records what it was asked to run,
# or, with LOTA_PREPUSH=machines, through a fake machines program.
class PrePushTest < Minitest::Test
  include TreeHelper
  include FakeMachines

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
    @bin = File.join(@tree, "bin")
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

  # The hook as git runs it, with +env+ and a PATH that holds the fake
  # machines when +config+ is given, and none otherwise.
  def hook(stdin, env: {}, local: @local, config: nil)
    fake_machines(@bin, config) if config
    env = { "PATH" => @bin, **env }
    PrePush.new(input: StringIO.new(stdin), output: @out, env:, git: PrePush::Git.new(@repo), repository: @repo,
      local:, clock: [0.0, 12.5].cycle)
  end

  def line(local:, remote: @trunk, ref: "refs/heads/trunk", remote_ref: ref)
    "#{ref} #{local} #{remote_ref} #{remote}\n"
  end

  def machines = { "LOTA_PREPUSH" => "machines" }

  def test_by_default_the_checks_run_here_over_exactly_the_pushed_range
    tip = commit("lib/a.rb", "a\n", "second")

    status = hook(line(local: tip)).run

    assert_equal 0, status
    assert_equal [["prepush"], ["red_before_green[#{@trunk}..#{tip}]"]], @local.calls
    assert_includes @out.string, "pre-push: rake prepush (here)"
    assert_includes @out.string, "passed in 12.5s"
    assert_empty machines_calls(@bin)
  end

  def test_by_default_a_windows_change_still_runs_only_here_and_needs_no_machines
    tip = commit("ext/lota/win32.cpp", "int x;\n", "native")

    assert_equal 0, hook(line(local: tip), config: {}).run
    assert_equal 2, @local.calls.size
    assert_empty machines_calls(@bin)
    refute_path_exists File.join(@repo, ".git/lota-prepush-windows.log")
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

  def test_on_the_machines_a_push_windows_cannot_tell_apart_runs_on_linux_alone
    tip = commit("lib/a.rb", "a\n", "second")

    status = hook(line(local: tip), env: machines, config: {}).run

    assert_equal 0, status, @out.string
    calls = machines_calls(@bin)

    assert_equal 1, calls.size
    assert_equal ["run", "linux"], calls.first.first(2)
    assert_equal ["--commit", tip, "--base", @trunk], calls.first[4, 4]
    assert_equal ["script/remote-gate", "prepush", @trunk, tip], calls.first.last(4)
    assert_includes @out.string, "[linux] hello from linux\n"
    assert_includes @out.string, "the Windows rule did not fire for #{tip[0, 12]}: Linux only"
    assert_includes @out.string, "pre-push: linux passed"
    assert_empty @local.calls
  end

  def test_on_the_machines_a_windows_change_runs_both_at_once_and_is_logged
    tip = commit("ext/lota/engine.cpp", "int x;\n", "native")

    status = hook(line(local: tip), env: machines, config: { "together" => %w[linux windows] }).run

    assert_equal 0, status, @out.string
    assert_equal [%w[run linux], %w[run windows]], machines_calls(@bin).map { |call| call.first(2) }.sort
    assert_includes @out.string, "[windows] hello from windows\n"
    fired = "the Windows rule fired for refs/heads/trunk #{tip[0, 12]}: ext/ (ext/lota/engine.cpp)"

    assert_includes @out.string, "pre-push: #{fired}\n"
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ #{Regexp.escape(fired)}\n\z/,
      File.read(File.join(@repo, ".git/lota-prepush-windows.log")))
  end

  def test_on_the_machines_a_failing_windows_run_refuses_the_push
    tip = commit("tasks/windows_build.rb", "x\n", "windows")

    status = hook(line(local: tip), env: machines, config: { "windows" => { "code" => 4 } }).run

    assert_equal 1, status
    assert_includes @out.string, "pre-push: linux passed"
    assert_includes @out.string, "push refused: windows: the command failed (exit 4)"
  end

  def test_on_the_machines_their_trouble_refuses_the_push_and_nothing_runs_here
    tip = commit("lib/a.rb", "a\n", "second")

    status = hook(line(local: tip), env: machines, config: { "linux" => { "machines" => 75 } }).run

    assert_equal 1, status
    assert_includes @out.string, "push refused: linux: build machines unavailable"
    assert_empty @local.calls
  end

  def test_on_the_machines_without_the_command_the_push_is_refused
    tip = commit("lib/a.rb", "a\n", "second")

    assert_equal 1, hook(line(local: tip), env: machines).run
    assert_includes @out.string, "push refused: linux: the machines command is not on PATH"
    assert_empty @local.calls
  end

  def test_the_windows_overrides_decide_for_the_rule
    docs = commit("doc/a.md", "a\n", "docs")
    hook(line(local: docs), env: { **machines, "LOTA_PREPUSH_WINDOWS" => "always" }, config: {}).run

    assert_includes @out.string, "the Windows rule fired for refs/heads/trunk #{docs[0, 12]}: LOTA_PREPUSH_WINDOWS=always"
    native = commit("ext/a.cpp", "a\n", "native")
    hook(line(local: native, remote: docs), env: { **machines, "LOTA_PREPUSH_WINDOWS" => "never" }, config: {}).run

    assert_includes @out.string, "the Windows checks are skipped: LOTA_PREPUSH_WINDOWS=never"
    assert_equal({ "linux" => 2, "windows" => 1 }, machines_calls(@bin).map { |call| call[1] }.tally)
    assert_equal 1, hook(line(local: native), env: { **machines, "LOTA_PREPUSH_WINDOWS" => "maybe" }).run
  end

  def test_the_clone_answers_what_a_range_changes_with_the_lines_it_adds_or_removes
    commit("lib/a.rb", "keep\nold line\n", "second")
    base = run!(@repo, "git", "rev-parse", "HEAD").strip
    write(@repo, "lib/a.rb", "keep\nnew MinGW line\n")
    FileUtils.rm(File.join(@repo, "README.md"))
    tip = commit("doc/b.md", "b\n", "third")

    changes = PrePush::Git.new(@repo).changes(base, tip)

    assert_equal ["README.md", "doc/b.md", "lib/a.rb"], changes.keys.sort
    assert_equal ["old line", "new MinGW line"], changes["lib/a.rb"]
    assert_equal ["Sample Game"], changes["README.md"]
    assert_equal File.join(File.realpath(File.join(@repo, ".git")), "lota-prepush-windows.log"),
      PrePush::Git.new(@repo).windows_log
  end
end

# WindowsRule decides from a push's changes whether it needs Lota's
# Windows checks, and names the clause and the path that decided it.
class WindowsRuleTest < Minitest::Test
  def verdict(changes, override = "") = PrePush::WindowsRule.new(override).verdict(changes)

  def test_each_path_clause_fires_on_its_paths
    {
      "ext/lota/native.cpp" => "ext/",
      "Gemfile" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "Gemfile.lock" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "lota.gemspec" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "mise.toml" => "Gemfile, Gemfile.lock, lota.gemspec, mise.toml",
      "tasks/windows_build.rb" => "tasks/windows*",
      ".github/windows_prepush.sh" => ".github/windows*",
      "test/native/windows_paths_test.rb" => "test/native/windows*",
      "doc/contributors/Windows.md" => "a path matching windows|mingw|win32|\\.dll",
      "lib/lota/MinGW.rb" => "a path matching windows|mingw|win32|\\.dll",
      "lib/lota/win32/a.rb" => "a path matching windows|mingw|win32|\\.dll",
      "lib/lota/libraries/OpenAL32.DLL" => "a path matching windows|mingw|win32|\\.dll",
    }.each do |path, clause|
      assert_equal PrePush::WindowsRule::Verdict.new(clause:, path:), verdict({ path => [] }), path
    end
  end

  def test_a_changed_line_naming_windows_fires
    assert_equal PrePush::WindowsRule::Verdict.new(clause: "a changed line matching windows|mingw|win32|\\.dll",
      path: "lib/lota/boot.rb"), verdict({ "doc/a.md" => ["plain"], "lib/lota/boot.rb" => ["load 'SDL3.dll'"] })
  end

  def test_a_change_that_names_nothing_of_windows_does_not_fire
    assert_nil verdict({ "lib/lota/boot.rb" => ["def boot", "end"], "test/native/linux_test.rb" => [], "Rakefile" => [] })
    assert_nil verdict({})
  end

  def test_a_path_clause_wins_over_a_line
    assert_equal "ext/", verdict({ "lib/a.rb" => ["windows"], "ext/a.cpp" => [] }).clause
  end

  def test_the_overrides
    assert_equal "LOTA_PREPUSH_WINDOWS=always", verdict({}, "always").to_s
    assert_nil verdict({ "ext/a.cpp" => [] }, "never")
    assert_equal "ext/ (ext/a.cpp)", verdict({ "ext/a.cpp" => [] }).to_s
    assert_raises(ArgumentError) { PrePush::WindowsRule.new("sometimes") }
  end
end
