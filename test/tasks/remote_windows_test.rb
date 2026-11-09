# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/remote_windows"
require "rbconfig"

# RemoteWindows sends a commit to a Windows computer over ssh and runs
# Lota's Windows checks there through its desktop job runner. The ssh
# here stands in for that computer: the PowerShell that writes the
# bundle becomes a write of what it decodes into a home folder of the
# test's, and agent-job's run becomes bash running the job's script
# there, with a cygpath that answers as MSYS2's does for that home.
class RemoteWindowsTest < Minitest::Test
  include TreeHelper

  FAKE_SSH = <<~RUBY
    #!#{RbConfig.ruby}
    require "fileutils"
    log = ENV.fetch("FAKE_SSH_LOG")
    command = ARGV.last
    input = $stdin.read
    File.write(log, [ARGV.join(" "), input.bytesize].join("\\t") + "\\n", mode: "a")
    home = ENV.fetch("FAKE_HOST_HOME")
    if command.include?("WriteAllBytes")
      folder = command[/Join-Path \\$env:USERPROFILE '([^']+)'/, 1]
      name = command[/'(push-\\h+\\.bundle)'/, 1]
      FileUtils.mkdir_p(File.join(home, folder))
      File.binwrite(File.join(home, folder, name), input.unpack1("m0"))
      exit 0
    end
    abort "not an exclusive job: \#{command}" unless command.start_with?("agent-job run --exclusive --type sh ")
    exec({ "USERPROFILE" => home }, "bash", "-c", input)
  RUBY

  CYGPATH = <<~SH
    #!/bin/sh
    echo "$2"
  SH

  CHECKS = <<~SH
    #!/bin/bash
    echo "checks on $(git log -1 --format=%s)"
    exit 5
  SH

  def setup
    @tree = File.realpath(Dir.mktmpdir("lota-remote-windows"))
    @origin = File.join(@tree, "origin")
    @home = File.join(@tree, "home")
    @checkout = File.join(@tree, "checkout")
    commit_file(@origin, ".github/windows_prepush.sh", CHECKS, "first", init: true)
    run!(@tree, "git", "clone", "--quiet", @origin, @checkout)
    FileUtils.mkdir_p(@home)
    @bin = File.join(@tree, "bin")
    File.chmod(0o755, write(@tree, "bin/ssh", FAKE_SSH))
    File.chmod(0o755, write(@tree, "bin/cygpath", CYGPATH))
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

  def windows(**)
    RemoteWindows.new(repository: @checkout, host: "agent@pc.test", origin: @origin, ssh: File.join(@bin, "ssh"), **)
  end

  def environment
    {
      "FAKE_SSH_LOG" => File.join(@tree, "ssh.log"),
      "FAKE_HOST_HOME" => @home,
      "PATH" => [@bin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR),
    }
  end

  # Runs the checks as rake gate:windows does, returning their status and
  # what they printed.
  def remote(windows)
    status = nil
    out, err = capture_subprocess_io do
      saved = environment.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
      ENV.update(environment)
      status = windows.run
    ensure
      ENV.update(saved)
    end
    [status, out, err]
  end

  def ssh_calls = File.readlines(File.join(@tree, "ssh.log"), chomp: true).map { |line| line.split("\t") }

  def test_an_unpushed_commit_is_written_there_then_checked_in_an_exclusive_job
    commit_file(@checkout, "b.txt", "b", "second")
    head = run!(@checkout, "git", "rev-parse", "HEAD").strip

    status, out, err = remote(windows)

    assert_equal 5, status, err
    assert_includes out, "windows checks: #{head[0, 12]} on agent@pc.test\n"
    assert_includes out, "checks on second\n"
    upload, job = ssh_calls
    assert_match(/WriteAllBytes/, upload.first)
    assert_match(/agent-job run --exclusive --type sh --timeout \d+ -; exit \$LASTEXITCODE\z/, job.first)
    refute_path_exists File.join(@home, "lota-prepush/push-#{head}.bundle")
  end

  def test_a_commit_origin_holds_needs_no_bundle
    status, out, err = remote(windows)

    assert_equal 5, status, err
    assert_includes out, "checks on first\n"
    assert_equal 1, ssh_calls.size
  end

  def test_the_clone_is_kept_and_reused_for_the_next_commit
    commit_file(@checkout, "b.txt", "b", "second")
    remote(windows)
    commit_file(@checkout, "c.txt", "c", "third")

    status, out, err = remote(windows)

    assert_equal 5, status, err
    assert_includes out, "checks on third\n"
    assert_path_exists File.join(@home, "lota-prepush/lota/b.txt")
  end

  def test_ssh_takes_the_key_and_batch_mode_and_the_runner_names_the_folder
    commit_file(@checkout, "b.txt", "b", "second")

    remote(windows(key: "~/.ssh/pc_key", runner: "elsewhere"))

    expected = ["-i", File.expand_path("~/.ssh/pc_key"), "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "agent@pc.test"]

    assert ssh_calls.first.first.start_with?(expected.join(" ")), ssh_calls.first.first
    assert_path_exists File.join(@home, "elsewhere/lota")
  end
end
