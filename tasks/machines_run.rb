# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# Runs Lota's checks on build machines, for whoever has them, through the
# machines command (machines run), which ships a commit or the working
# tree to a queue over the machines, streams the command's output back,
# and ends with a line RUN_EXIT=CODE before it exits with CODE. This file
# builds the commands the pre-push hook runs with LOTA_PREPUSH=machines
# (tasks/prepush.rb), and rake gate:remote and gate:windows
# (tasks/gate.rake), and runs one or more of them at once, each line of
# each prefixed with the run's name.
#
# A run's status is the command's when machines printed RUN_EXIT, and
# otherwise machines' own: 75 when the machines could not take or finish
# the run, 1 or 2 when it refused the call. Nothing runs here instead:
# whoever asks for the machines asks not to run the checks here.
class MachinesRun
  # The command, found on PATH.
  COMMAND = "machines"

  # The status machines exits with when the machines, not the command,
  # failed.
  UNAVAILABLE = 75

  # The project its workspaces are kept under, the same from every clone
  # and worktree, so each run finds the last one's build warm.
  PROJECT = "lota"

  # How long each run may take, in seconds.
  PREPUSH_TIMEOUT = 2700
  WINDOWS_TIMEOUT = 3600
  GATE_TIMEOUT = 3600

  # The LOTA_GATE_GPU modes that draw on a GPU (script/remote-gate), and
  # what a node needs to have one.
  GPU_MODES = %w[opengl vulkan].freeze
  GPU_REQUIREMENT = "gpu=radeon"

  # The variables that point git at a repository, as git rev-parse
  # --local-env-vars lists them. git exports some of them to its hooks,
  # GIT_DIR among them in a linked worktree, and machines, which reads each
  # submodule's commit with git -C, would then look for it in the
  # superproject's repository and refuse the run. machines runs without
  # them, and finds the repository from the folder it runs in.
  GIT_REPOSITORY_VARIABLES = %w[
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY
    GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS
    GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR
  ].freeze

  # The last line machines prints.
  RUN_EXIT = /^RUN_EXIT=(\d+)\b/

  # A command to run, and the name its lines are prefixed with.
  class Run < Data.define(:name, :argv)
  end

  # How a Run ended: +status+ is machines' exit status (nil when there is
  # no machines command), and +code+ the command's, from its RUN_EXIT line
  # (nil when it printed none).
  class Result < Data.define(:name, :status, :code)
    # Whether the command ran and passed.
    def passed? = code&.zero? || false

    # Why it did not pass, for a person to read.
    def reason
      return "the command failed (exit #{code})" if code
      return "the #{COMMAND} command is not on PATH" if status.nil?
      return "build machines unavailable (machines run exited #{UNAVAILABLE})" if status == UNAVAILABLE

      "machines run refused the call (exit #{status})"
    end
  end

  # Runs the block in the environment from before bundle exec, which the
  # hook and the rake tasks run under. Bundler puts its own bin folders at
  # the front of PATH, and a gem's stale stub named machines there would
  # stand in for the real command, and its RUBYOPT would load Lota's bundle
  # into a command of another project.
  def self.outside_bundle(&)
    defined?(Bundler) ? Bundler.with_original_env(&) : yield
  end

  # The machines command on +env+'s PATH, or nil.
  def self.find(env)
    env.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, COMMAND) }
      .find { |path| File.file?(path) && File.executable?(path) }
  end

  # [env] The environment: PATH, where the machines command is found;
  #       AGENT_NAME, who asks; and LOTA_GATE_GPU (off, opengl or vulkan),
  #       where the Linux displays draw.
  # [program] The machines command, or nil for none.
  def initialize(env:, program: self.class.find(env))
    @env = env
    @program = program
  end

  # The Linux pre-push checks on the commit +new+, with +old+ in its
  # history for red_before_green.
  def linux_prepush(old:, new:)
    options = ["--commit", new, "--base", old, "--label", "lota prepush", *who]
    Run.new(name: "linux", argv: [*linux, *options, *timed(PREPUSH_TIMEOUT), "script/remote-gate", "prepush", old, new])
  end

  # The Windows pre-push checks on the commit +new+.
  def windows_prepush(new:)
    options = ["--commit", new, "--label", "lota windows prepush", *who]
    Run.new(name: "windows", argv: [*windows, *options, *timed(WINDOWS_TIMEOUT), "bash", ".github/windows_prepush.sh"])
  end

  # The gate, or the rake tasks +rake_args+, on the working tree.
  def gate(rake_args = [])
    options = ["--label", ["lota gate", *rake_args].join(" "), *who]
    Run.new(name: "linux", argv: [*linux, *options, *timed(GATE_TIMEOUT), "script/remote-gate", "full", *rake_args])
  end

  # The Windows checks on the working tree.
  def windows_gate
    options = ["--label", "lota windows checks", *who]
    Run.new(name: "windows", argv: [*windows, *options, *timed(WINDOWS_TIMEOUT), "bash", ".github/windows_prepush.sh"])
  end

  # Runs +runs+ at once from +chdir+, writing each line they print to
  # +output+, prefixed with "[name] " when +prefix+, and returns their
  # Results in the same order.
  def run_all(runs, output:, chdir:, prefix: true)
    lock = Mutex.new
    runs.map { |run| Thread.new { follow(run, output:, chdir:, lock:, prefix:) } }.map(&:value)
  end

  private def linux = [@program || COMMAND, "run", "linux", "--project", PROJECT, *gpu]

  private def windows = [@program || COMMAND, "run", "windows", "--exclusive", "--project", PROJECT]

  private def who = ["--agent", @env.fetch("AGENT_NAME", "").then { |name| name.empty? ? "agent" : name }]

  # The run's time limit, and the end of machines' own options.
  private def timed(seconds) = ["--timeout", seconds.to_s, "--"]

  private def gpu
    mode = @env.fetch("LOTA_GATE_GPU", "")
    GPU_MODES.include?(mode) ? ["--require", GPU_REQUIREMENT, "--env", "LOTA_GATE_GPU=#{mode}"] : []
  end

  private def follow(run, output:, chdir:, lock:, prefix:)
    return Result.new(name: run.name, status: nil, code: nil) unless @program

    lines = Lines.new(output, prefix ? "[#{run.name}] " : "", lock)
    unset = GIT_REPOSITORY_VARIABLES.to_h { |name| [name, nil] }
    status = Open3.popen2e(unset, *run.argv, chdir:) do |stdin, out, waiter|
      stdin.close
      out.binmode.each_line { |line| lines << line }
      waiter.value
    end
    Result.new(name: run.name, status: status.exitstatus || 1, code: lines.code)
  end

  # Writes a run's lines to an output another run's lines share, each
  # whole and with the run's prefix, and keeps the code from RUN_EXIT.
  class Lines
    # The command's exit status, from the RUN_EXIT line, or nil.
    attr_reader :code

    # [output] Where the lines go.
    # [prefix] What each line starts with.
    # [lock] Held while a line is written, so lines never interleave.
    def initialize(output, prefix, lock)
      @output = output
      @prefix = prefix
      @lock = lock
      @code = nil
    end

    # Writes +line+, adding the newline a last line may lack.
    def <<(line)
      @code = Integer(Regexp.last_match(1)) if line =~ RUN_EXIT
      text = "#{@prefix}#{line.end_with?("\n") ? line : "#{line}\n"}"
      @lock.synchronize do
        @output.write(text)
        @output.flush
      end
      self
    end
  end
end
