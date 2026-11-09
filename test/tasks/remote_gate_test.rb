# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/remote_gate"
require "rbconfig"

# RemoteGate sends a commit, or the working tree, to a gate runner over
# ssh. The ssh here is a program that runs its command in a shell whose
# home is a folder of the test's, holding a runner as the real host's
# is laid out: a clone of the origin, a fetch lock, and a run script that
# prints what it was asked to run and the subject of that commit, and
# exits with a status of its own.
class RemoteGateTest < Minitest::Test
  include TreeHelper

  FAKE_SSH = <<~RUBY
    #!#{RbConfig.ruby}
    File.write(ENV.fetch("FAKE_SSH_ARGS"), ARGV.join("\\n"))
    File.write(ENV.fetch("FAKE_SSH_STDIN"), $stdin.read)
    $stdin.reopen(ENV.fetch("FAKE_SSH_STDIN"))
    exec({ "HOME" => ENV.fetch("FAKE_HOST_HOME") }, "bash", "-c", ARGV.last)
  RUBY

  RUN = <<~SH
    #!/bin/sh
    lota="$HOME/lota-gate/lota"
    echo "run $*"
    echo "subject $(git -C "$lota" log -1 --format=%s "$1")"
    git -C "$lota" ls-tree -r --name-only "$1" | sed 's/^/file /'
    echo GATE_EXIT=3
    exit 3
  SH

  # flock comes with Linux, not macOS; where it is missing, one that only
  # runs its command stands in, since the lock is not under test.
  FLOCK = <<~SH
    #!/bin/sh
    shift
    exec "$@"
  SH

  def setup
    @tree = File.realpath(Dir.mktmpdir("lota-remote-gate"))
    @origin = File.join(@tree, "origin")
    @home = File.join(@tree, "home")
    @checkout = File.join(@tree, "checkout")
    commit_file(@origin, "a.txt", "a", "first", init: true)
    run!(@tree, "git", "clone", "--quiet", @origin, @checkout)
    run!(@tree, "git", "clone", "--quiet", @origin, File.join(@home, "lota-gate/lota"))
    write(@home, "lota-gate/locks/fetch")
    File.chmod(0o755, write(@home, "lota-gate/run", RUN))
    @bin = File.join(@tree, "bin")
    File.chmod(0o755, write(@tree, "bin/ssh", FAKE_SSH))
    File.chmod(0o755, write(@tree, "bin/flock", FLOCK)) unless system("command -v flock >/dev/null 2>&1")
  end

  def teardown
    FileUtils.rm_rf(@tree)
  end

  def commit_file(repository, path, content, subject, init: false)
    run!(@tree, "git", "init", "--quiet", "--initial-branch=trunk", repository) if init
    write(repository, path, content)
    run!(repository, "git", "add", path)
    run!(repository, "git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet",
      "-m", subject)
  end

  def gate(**)
    RemoteGate.new(repository: @checkout, ssh: File.join(@bin, "ssh"), **)
  end

  # What the fake ssh and git, which makes the working tree's commit, read.
  def environment
    {
      "FAKE_SSH_ARGS" => File.join(@tree, "ssh.args"),
      "FAKE_SSH_STDIN" => File.join(@tree, "ssh.stdin"),
      "FAKE_HOST_HOME" => @home,
      "PATH" => [@bin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR),
      "GIT_AUTHOR_NAME" => "Test",
      "GIT_AUTHOR_EMAIL" => "test@example.com",
      "GIT_COMMITTER_NAME" => "Test",
      "GIT_COMMITTER_EMAIL" => "test@example.com",
    }
  end

  # Runs the gate as rake gate:remote does, returning its status and what
  # it printed.
  def remote(gate, rake_args = [])
    status = nil
    out, err = capture_subprocess_io do
      saved = environment.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
      ENV.update(environment)
      status = gate.run(rake_args)
    ensure
      ENV.update(saved)
    end
    [status, out, err]
  end

  def ssh_args = File.read(File.join(@tree, "ssh.args")).split("\n")

  def test_an_unpushed_commit_goes_as_a_bundle_and_the_gates_status_comes_back
    commit_file(@checkout, "b.txt", "b", "second")
    head = run!(@checkout, "git", "rev-parse", "HEAD").strip

    status, out, err = remote(gate, %w[prepush])

    assert_equal 3, status, err
    assert_includes out, "remote gate: #{head[0, 12]} on agent@192.168.10.114\n"
    assert_includes out, "run remote-gate/#{head} prepush\n"
    assert_includes out, "subject second\n"
    assert_includes out, "GATE_EXIT=3\n"
    refute_empty File.binread(File.join(@tree, "ssh.stdin"))
    assert_empty run!(@checkout, "git", "for-each-ref", "refs/remote-gate")
  end

  def test_a_commit_origin_holds_goes_by_name_alone
    head = run!(@checkout, "git", "rev-parse", "HEAD").strip

    status, out, err = remote(gate)

    assert_equal 3, status, err
    assert_includes out, "run #{head}\n"
    assert_includes out, "subject first\n"
    assert_empty File.binread(File.join(@tree, "ssh.stdin"))
  end

  def test_the_working_tree_goes_as_a_commit_without_touching_the_index_or_head
    head = run!(@checkout, "git", "rev-parse", "HEAD").strip
    write(@checkout, "a.txt", "changed")
    write(@checkout, "new.txt", "untracked")
    write(@checkout, "staged.txt", "staged")
    run!(@checkout, "git", "add", "staged.txt")

    status, out, err = remote(gate)

    assert_equal 3, status, err
    assert_includes out, "(the working tree)"
    assert_includes out, "subject The working tree, for the remote gate\n"
    assert_includes out, "file new.txt\nfile staged.txt\n"
    assert_equal head, run!(@checkout, "git", "rev-parse", "HEAD").strip
    assert_equal "A  staged.txt\n", run!(@checkout, "git", "status", "--porcelain", "staged.txt")
    assert_equal " M a.txt\n", run!(@checkout, "git", "status", "--porcelain", "a.txt")
    assert_equal "?? new.txt\n", run!(@checkout, "git", "status", "--porcelain", "new.txt")
  end

  def test_ssh_takes_the_key_host_and_batch_mode
    remote(gate(host: "gate@example.test", key: "~/.ssh/gate_key"))

    expected = ["-i", File.expand_path("~/.ssh/gate_key"), "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]

    assert_equal [*expected, "gate@example.test"], ssh_args.first(7)
  end

  def test_without_a_key_ssh_chooses_its_own
    remote(gate)

    assert_equal ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "agent@192.168.10.114"], ssh_args.first(5)
  end

  def test_a_failed_fetch_on_the_host_fails_without_running_the_gate
    commit_file(@checkout, "b.txt", "b", "second")
    FileUtils.rm_rf(File.join(@home, "lota-gate/lota"))

    status, out, = remote(gate)

    refute_equal 0, status
    refute_includes out, "run remote-gate/"
    assert_match(/GATE_EXIT=[1-9]/, out)
  end
end
