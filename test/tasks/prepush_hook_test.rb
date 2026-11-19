# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# The pre-push hook's Ruby as the hook runs it, tasks/prepush.rb as a
# program, with git's refs on its standard input, in a repository of its
# own. It runs bundle exec rake push_check there, which loads Lota's own
# tasks/push_check.rake and runs real RuboCop over the files the push
# changes. The repository's Rakefile stands in for the checks RuboCop
# does not do, each of which records that it ran and fails as the test
# asks. So these tests fail when the hook passes a push it never checked:
# one whose checks did not run, or failed.
class PrePushHookTest < Minitest::Test
  include TreeHelper

  PREPUSH = File.join(ROOT, "tasks/prepush.rb")

  # The checks push_check runs that are not RuboCop: each records its
  # name in PUSH_CHECK_LOG, and aborts or raises when PUSH_CHECK_FAIL
  # names it, as a rake task fails.
  RAKEFILE = <<~RUBY
    # frozen_string_literal: true

    load ENV.fetch("LOTA_PUSH_CHECK_RAKE")

    def stand_in(name)
      File.open(ENV.fetch("PUSH_CHECK_LOG"), "a") { |log| log.puts(name) }
      case ENV.fetch("PUSH_CHECK_FAIL", "")
      when "abort:\#{name}" then abort "\#{name} found a fault"
      when "raise:\#{name}" then raise "\#{name} could not start"
      end
    end

    namespace(:test) { task(:unit) { stand_in("test:unit") } }
    namespace(:reuse) { task(:lint) { stand_in("reuse:lint") } }
    task(:steep) { stand_in("steep") }
    namespace(:red_before_green) do
      task(:unit, [:range]) { |_task, args| stand_in("red_before_green:unit[\#{args[:range]}]") }
    end
  RUBY

  CLEAN = <<~RUBY
    # frozen_string_literal: true

    # The game.
    module SampleGame
      LIVES = 3
    end
  RUBY

  def setup
    @tree = File.realpath(Dir.mktmpdir("lota-prepush-hook"))
    @repo = File.join(@tree, "repo")
    @log = File.join(@tree, "ran")
    run!(@tree, "git", "init", "--quiet", "--initial-branch=trunk", @repo)
    write(@repo, "Rakefile", RAKEFILE)
    write(@repo, ".rubocop.yml", "AllCops:\n  NewCops: enable\n  SuggestExtensions: false\n")
    write(@repo, "lib/sample_game.rb", CLEAN)
    write(@repo, "lib/old.rb", CLEAN)
    @base = commit("first", trailers: "")
    run!(@repo, "git", "update-ref", "refs/remotes/origin/trunk", @base)
  end

  def teardown
    FileUtils.rm_rf(@tree)
  end

  # The trailers every commit pushed carries, as git reads them: one
  # paragraph, the message's last.
  TRAILERS = "Provenance: requested\nCo-Authored-By: Sample <sample@example.com>\n"

  def commit(subject, trailers: TRAILERS)
    run!(@repo, "git", "add", "--all")
    run!(@repo, "git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "-m",
      "#{subject}\n\nWhy it changed.\n\n#{trailers}")
    run!(@repo, "git", "rev-parse", "HEAD").strip
  end

  # Runs the hook's Ruby as .githooks/pre-push runs it, pushing +tip+ to
  # trunk, with +fail+ naming the check that fails; answers its output
  # and exit status.
  def push(tip, fail: "", remote: "origin", refs: "refs/heads/trunk #{tip} refs/heads/trunk #{@base}\n")
    Open3.capture2e(env(fail), RbConfig.ruby, PREPUSH, remote, stdin_data: refs, chdir: @repo)
  end

  def env(fail = "")
    {
      "LOTA_PREPUSH" => nil,
      "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"),
      "LOTA_PUSH_CHECK_RAKE" => File.join(ROOT, "tasks/push_check.rake"),
      "PUSH_CHECK_LOG" => @log,
      "PUSH_CHECK_FAIL" => fail,
    }
  end

  def ran = File.exist?(@log) ? File.readlines(@log, chomp: true) : []

  def test_a_push_runs_every_check_over_the_commits_it_brings
    write(@repo, "lib/sample_game.rb", CLEAN.sub("3", "4"))
    FileUtils.rm(File.join(@repo, "lib/old.rb"))
    tip = commit("second")

    output, status = push(tip)

    assert status.success?, output
    assert_includes output, "push_check: rubocop (1 files)\n"
    assert_includes output, "push_check: rubocop passed"
    assert_includes output, "push_check: provenance[#{@base}..#{tip}] passed"
    assert_equal ["test:unit", "reuse:lint", "steep", "red_before_green:unit[#{@base}..#{tip}]"], ran
  end

  # The commit already on the remote has no trailer, and cannot be mended,
  # so it is never checked; of those the push brings, one whose
  # provenance line a blank line cuts off from the footer refuses it, and
  # names it, the fault, and the remedy, before any other check runs.
  def test_a_commit_whose_provenance_git_does_not_read_as_a_trailer_refuses_the_push
    write(@repo, "lib/sample_game.rb", CLEAN.sub("3", "4"))
    stray = commit("second", trailers: TRAILERS.sub("\n", "\n\n"))
    write(@repo, "lib/sample_game.rb", CLEAN.sub("3", "5"))
    tip = commit("third")

    output, status = push(tip)

    refute status.success?, output
    assert_includes output, "1 commit does not say its provenance in a trailer git reads:\n" \
      "  #{stray[0, 12]} second\n    has a Provenance: line that is not in the trailer block"
    refute_includes output, "#{tip[0, 12]} third"
    refute_includes output, "#{@base[0, 12]} first"
    assert_includes output, "git rebase -i #{stray}^"
    assert_includes output, "push refused: rake push_check[#{@base}..#{tip}] failed"
    assert_empty ran
  end

  def test_a_commit_with_no_provenance_trailer_refuses_the_push
    write(@repo, "lib/sample_game.rb", CLEAN.sub("3", "4"))
    tip = commit("second", trailers: "Co-Authored-By: Sample <sample@example.com>\n")

    output, status = push(tip)

    refute status.success?, output
    assert_includes output, "  #{tip[0, 12]} second\n    has no Provenance: trailer\n"
    assert_empty ran
  end

  # Commits git cannot list are not commits that passed.
  def test_a_range_git_cannot_read_fails_the_provenance_check
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "provenance[nowhere..#{@base}]", chdir: @repo)

    refute status.success?, output
    assert_includes output, "git log nowhere..#{@base} failed"
  end

  def test_an_offence_rubocop_finds_refuses_the_push
    write(@repo, "lib/sample_game.rb", "puts 1\n")
    tip = commit("second")

    output, status = push(tip)

    refute status.success?, output
    assert_includes output, "Style/FrozenStringLiteralComment"
    assert_includes output, "push refused: rake push_check[#{@base}..#{tip}] failed"
    assert_empty ran
  end

  # A rake task fails by aborting, as a test run that fails does.
  def test_a_check_that_aborts_refuses_the_push
    write(@repo, "lib/sample_game.rb", CLEAN.sub("3", "4"))
    tip = commit("second")

    output, status = push(tip, fail: "abort:test:unit")

    refute status.success?, output
    assert_includes output, "push_check: test:unit failed"
    assert_equal ["test:unit"], ran
  end

  # A rake task fails by raising, as one whose command cannot start does.
  def test_a_check_that_raises_refuses_the_push
    write(@repo, "lib/sample_game.rb", CLEAN.sub("3", "4"))
    tip = commit("second")

    output, status = push(tip, fail: "raise:reuse:lint")

    refute status.success?, output
    assert_includes output, "reuse:lint: reuse:lint could not start"
    assert_equal ["test:unit", "reuse:lint"], ran
  end

  # git names the remote as the hook's first argument, and a push that
  # brings no refs passes only when that remote holds HEAD, which origin
  # does here and upstream does not.
  def test_the_remote_is_the_one_git_names
    output, status = push(@base, remote: "upstream", refs: "")

    refute status.success?, output
    assert_includes output, "HEAD has commits upstream lacks"
  end
end
