# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "shellwords"
require "tempfile"
require_relative "remote_gate"

# Runs Lota's Windows checks (.github/windows_prepush.sh) on a Windows
# computer before a push (rake gate:windows, and the pre-push hook when
# LOTA_WINDOWS_HOST is set), as RemoteGate runs the gate on a Linux one:
# leased capacity for whoever has it, so a Windows break is found before
# trunk instead of by CI.
#
# The computer is reached over ssh, whose shell there is Windows
# PowerShell, and runs heavy work through a desktop job runner,
# agent-job, which runs each job in the signed-in desktop session, where
# windows open and the GPU draws; a job submitted with --exclusive runs
# alone, as tests that take the keyboard focus must. The commit goes as a
# git bundle of what +base+ lacks, written as base64, since PowerShell's
# pipes mangle binary data, into +runner+, a folder under the account's
# home; the job then clones Lota's origin into +runner+/lota if it is not
# there, fetches the bundle, checks the commit out, and runs the checks
# from it. The job's exit status comes back.
class RemoteWindows
  # Raised when the commit cannot be made, bundled, or sent.
  class Failure < StandardError; end

  # Where the clone and the bundles live, under the account's home.
  RUNNER = "lota-prepush"

  # The repository the runner's clone fetches from, over https, since the
  # account there needs no GitHub login to read it.
  ORIGIN = "https://github.com/setdef/Lota.git"

  # How long the job may run, in seconds: the checks take about five
  # minutes with the dependencies built, and building them about four
  # more.
  TIMEOUT = 2700

  # [repository] The checkout whose commit is sent.
  # [host] The ssh destination.
  # [key] An identity file for ssh's -i, or nil for ssh's own choice.
  # [runner] The folder under the account's home that holds the clone.
  # [commit] The commit to check, such as the tip of a push; HEAD, or a
  #          commit of the working tree, when nil.
  # [origin] The repository the clone is made from.
  # [ssh] The ssh program.
  def initialize(repository:, host:, key: nil, runner: RUNNER, commit: nil, origin: ORIGIN, ssh: "ssh")
    @gate = RemoteGate.new(repository:, host:, key:, ssh:, commit:)
    @host = host
    @key = key
    @runner = runner
    @origin = origin
    @ssh = ssh
  end

  # The commit the checks run on.
  def commit = @gate.commit

  # Sends the commit and runs the checks on it, printing what they print,
  # and returns the job's exit status, or ssh's own when ssh fails.
  def run
    $stdout.puts "windows checks: #{commit[0, 12]} on #{@host}"
    $stdout.flush
    Tempfile.create(["lota-remote-windows", ".bundle"]) do |bundle|
      bundled = @gate.bundle(bundle.path)
      if bundled
        status = send_bundle(File.binread(bundle.path))
        return status unless status.zero?
      end
      Tempfile.create(["lota-remote-windows", ".sh"]) do |job|
        job.write(script(bundled))
        job.close
        system(*command("agent-job run --exclusive --type sh --timeout #{TIMEOUT} -; exit $LASTEXITCODE"), in: job.path)
        $?.exitstatus || 1
      end
    end
  end

  # The ssh command, for Kernel#system, that runs the PowerShell
  # +powershell+ on the host.
  def command(powershell)
    options = @key ? ["-i", File.expand_path(@key)] : []
    [@ssh, *options, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", @host, powershell]
  end

  # The PowerShell that writes the base64 bundle on its standard input to
  # the runner's folder.
  def upload_command
    folder = "(Join-Path $env:USERPROFILE '#{@runner}')"
    "New-Item -ItemType Directory -Force #{folder} | Out-Null; " \
      "[IO.File]::WriteAllBytes((Join-Path #{folder} '#{bundle_name}'), " \
      "[Convert]::FromBase64String([Console]::In.ReadToEnd()))"
  end

  # The job's bash script, run in MSYS2's UCRT64 environment: it makes or
  # updates the clone, fetches the bundle when +bundled+, checks the commit
  # out, and runs the checks the commit holds.
  def script(bundled)
    runner = %("$(cygpath -u "$USERPROFILE")/#{@runner}")
    fetch = if bundled
      %(git fetch --quiet "$runner/#{bundle_name}" "+#{RemoteGate::REF}:refs/heads/prepush/#{commit}" && ) +
        %(rm -f "$runner/#{bundle_name}"\n)
    else
      ""
    end
    <<~SH
      set -eu
      runner=#{runner}
      mkdir -p "$runner"
      [ -d "$runner/lota/.git" ] || git -c core.autocrlf=false -c core.symlinks=true clone --quiet #{Shellwords.escape(@origin)} "$runner/lota"
      cd "$runner/lota"
      git fetch --quiet origin
      #{fetch.chomp}
      git -c advice.detachedHead=false checkout --quiet --force --detach #{commit}
      git clean --quiet --force -d -- test
      if git config --file .gitmodules --get submodule.vendor/love.path > /dev/null; then
        git submodule update --quiet --init --depth 1 vendor/love
      fi
      exec bash .github/windows_prepush.sh
    SH
  end

  private def bundle_name = "push-#{commit}.bundle"

  private def send_bundle(bytes)
    IO.popen(command(upload_command), "w") { |pipe| pipe.write([bytes].pack("m0")) }
    $?.exitstatus || 1
  rescue SystemCallError => e
    raise Failure, "sending the commit to #{@host} failed: #{e.message}"
  end
end
