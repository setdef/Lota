# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require "tmpdir"

# What the gate (tasks/gate.rb) needs to see a check that never ends, and
# to end it.
class Gate
  # A process the gate started, in a process group of its own, whose output
  # (standard output and error together) is read as it comes, so that what
  # it printed is there to show even when it never ends.
  class Spawned
    # The process's ID, which is also its process group's.
    attr_reader :pid

    # Starts +command+ (an array) in +root+ with +environment+ added.
    def initialize(environment, command, root)
      reader, writer = IO.pipe
      @pid = ::Process.spawn(environment, *command, :in => File::NULL, %i[out err] => writer, :chdir => root,
        :pgroup => true)
      writer.close
      @output = +""
      @lock = Mutex.new
      @pipe = reader
      @reader = Thread.new { drain }
      @waiter = ::Process.detach(@pid)
    end

    # Waits until the monotonic clock reads +deadline+ for the process to
    # exit and its output to end, which a process it started can hold open
    # after it exits. Returns its Process::Status, or nil when either has
    # not happened by then.
    def wait(deadline)
      @waiter.join(left(deadline)) && @reader.join(left(deadline)) && @waiter.value
    end

    # The process's Process::Status once it has exited, else nil.
    def exit_status = (@waiter.value unless @waiter.alive?)

    # What it has printed so far.
    def output = @lock.synchronize { @output.dup }.force_encoding(Encoding.default_external).scrub

    # Ends the process group: TERM, then after +grace+ seconds KILL to
    # whatever of it is left. Only this process's group is signalled, the
    # one the gate started it in. Returns the output it printed.
    def terminate(grace)
      signal("TERM")
      deadline = now + grace
      sleep 0.05 while group? && now < deadline
      signal("KILL")
      @waiter.join
      # A process that left the group can still hold the output open.
      @pipe.close unless @reader.join(grace)
      @reader.join
      output
    end

    private def drain
      loop { (chunk = @pipe.readpartial(65_536)) && @lock.synchronize { @output << chunk } }
    rescue IOError
      nil
    end

    private def group?
      ::Process.kill(0, -@pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    private def signal(name)
      ::Process.kill(name, -@pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    private def left(deadline) = [deadline - now, 0].max

    private def now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end

  # What a hung check's processes are doing: the tree of processes under
  # it, from ps, and a stack of each, from the platform's sampler.
  class Diagnosis
    # The columns of ps's table.
    COLUMNS = "pid,ppid,pgid,etime,state,command"

    # How long a sampler may take, beyond its sampling, before it is ended.
    SAMPLER_SLACK = 40

    # [leader] The PID of the check's process, which leads its group.
    # [sample_seconds] How long each stack sample lasts, where the sampler
    #                  takes a duration (macOS's sample).
    def initialize(leader, sample_seconds:)
      @leader = leader
      @sample_seconds = sample_seconds
    end

    # The tree, then each process's stack, as text.
    def to_s
      header, *rows = IO.popen(["ps", "-axww", "-o", COLUMNS], &:read).lines
      members = tree(rows.map { |line| Row.parse(line) }.compact)
      [header, *members.map { |row, depth| "#{'  ' * depth}#{row.line}" }, *stacks(members.map { |row, _| row.pid })]
        .join
    rescue => e
      "could not diagnose #{@leader}: #{e.class}: #{e.message}\n"
    end

    # One line of ps's table.
    class Row < Data.define(:pid, :ppid, :pgid, :line)
      # The row +line+ shows, or nil for one that is not a process's.
      def self.parse(line)
        pid, ppid, pgid = line.split.first(3).map { |field| Integer(field, exception: false) }
        new(pid:, ppid:, pgid:, line:) if pid && ppid && pgid
      end
    end

    # The leader and its descendants, depth first, then any process left in
    # its group that is not one of them (one whose parent exited), with
    # theirs; each with its depth.
    private def tree(rows)
      children = rows.group_by(&:ppid)
      seen = {}
      walk = lambda do |row, depth|
        next [] if seen[row.pid]

        seen[row.pid] = true
        [[row, depth], *children.fetch(row.pid, []).flat_map { |child| walk.call(child, depth + 1) }]
      end
      roots = rows.select { |row| row.pid == @leader } + rows.select { |row| row.pgid == @leader }
      roots.flat_map { |row| walk.call(row, 0) }
    end

    private def stacks(pids)
      Dir.mktmpdir("lota-gate-sample") do |dir|
        pids.map { |pid| Thread.new { stack(pid, File.join(dir, "#{pid}.txt")) } }.map(&:value)
      end
    end

    private def stack(pid, file)
      command = sampler(pid, file)
      return "\nstack of #{pid}: no sampler found (sample, eu-stack, or gdb)\n" unless command

      spawned = Spawned.new({}, command, Dir.pwd)
      spawned.wait(::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + @sample_seconds + SAMPLER_SLACK) ||
        spawned.terminate(1)
      said = File.exist?(file) ? File.read(file) : spawned.output
      "\nstack of #{pid} (#{command.first(2).join(' ')}):\n#{said}"
    end

    private def sampler(pid, file)
      if RbConfig::CONFIG["host_os"].include?("darwin")
        ["/usr/bin/sample", pid.to_s, @sample_seconds.ceil.to_s, "-file", file]
      elsif (eu_stack = which("eu-stack"))
        [eu_stack, "-p", pid.to_s]
      elsif (gdb = which("gdb"))
        [gdb, "-p", pid.to_s, "-batch", "-ex", "thread apply all bt"]
      end
    end

    private def which(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
        .find { |path| File.executable?(path) }
    end
  end
end
