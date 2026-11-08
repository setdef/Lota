# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"

class Gate
  # A process the gate starts in a process group of its own, whose output
  # (standard output and error together) it collects as it arrives, so that
  # what a check has printed so far can be read while it still runs, and
  # the whole group can be ended at once.
  class Child
    # How long, in seconds, finish_by waits at a time before it asks the
    # clock again.
    POLL = 0.1

    # How long, in seconds, finish_by gives the threads that watch the
    # process to notice an end that came as the deadline passed: the
    # process's exit and the close of its output reach them a moment after
    # they happen.
    SETTLE = 0.2

    # The process's id, which is also its process group's.
    attr_reader :pid

    # Starts +command+ in +chdir+ with +environment+ added, reading nothing.
    def initialize(command, environment: {}, chdir: Dir.pwd)
      reader, writer = IO.pipe
      @pid = Process.spawn(environment, *command, :in => File::NULL, %i[out err] => writer, :chdir => chdir, :pgroup => true)
      writer.close
      @reader = reader
      @output = String.new(encoding: Encoding::BINARY)
      @lock = Mutex.new
      @collector = Thread.new { collect }
      @waiter = Process.detach(@pid)
    end

    # What the process, and anything holding its output, has printed so far.
    def output = @lock.synchronize { @output.dup }.force_encoding(Encoding.default_external)

    # The process's Process::Status once it has exited, or nil.
    def status = @waiter.alive? ? nil : @waiter.value

    # Whether something, the process or what it started, still holds its
    # output open.
    def open? = @collector.alive?

    # Whether the process has exited and its output has closed by
    # +deadline+, a time on +clock+ (anything whose +now+ gives seconds),
    # waiting until then for both. Something the process started can hold
    # its output open after it exits, and then the check has not finished.
    #
    # The thread to wait on is the one found alive, never a second look:
    # both can end while the clock is asked, between two looks.
    def finish_by(deadline, clock: Gate)
      threads = [@waiter, @collector]
      while (thread = threads.find(&:alive?))
        remaining = deadline - clock.now
        break if remaining <= 0

        thread.join([remaining, POLL].min)
      end
      threads.map { |thread| thread.join(SETTLE) }.all?
    end

    # Ends the process group: TERM, and after +grace+ seconds KILL, which
    # also ends whatever in the group outlived the process. Stops reading
    # output that something outside the group still holds open.
    def end_group(grace: 5)
      signal("TERM")
      @waiter.join(grace)
      signal("KILL")
      @waiter.join
      @reader.close unless @collector.join(grace)
      @collector.join
    end

    private def collect
      loop do
        chunk = @reader.readpartial(65_536)
        @lock.synchronize { @output << chunk }
      end
    rescue IOError # EOFError at the end, or IOError once end_group closes the pipe
      nil
    end

    private def signal(name)
      Process.kill(name, -@pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
  end

  # What a diagnostic tool did: its output (standard output and error
  # together), its Process::Status, or nil if it could not be started or
  # was ended, and whether it ran past its time and was ended.
  class Tool < Data.define(:command, :output, :status, :timed_out)
    # Runs +command+, ending it if it takes longer than +timeout+ seconds
    # on +clock+.
    def self.run(command, timeout:, clock: Gate)
      child = Child.new(command)
      finished = child.finish_by(clock.now + timeout, clock:)
      child.end_group(grace: 1) unless finished
      new(command:, output: child.output, status: child.status, timed_out: !finished)
    rescue SystemCallError => e
      new(command:, output: e.message, status: nil, timed_out: false)
    end

    # Whether it ran to the end and succeeded.
    def ok? = (!timed_out && status&.success?) || false

    # A line saying how it failed, with what it printed.
    def failure
      how = if timed_out then "took more than its time and was ended"
      elsif status then "failed (#{status})"
      else "could not run"
      end
      "#{command.first} #{how}; it printed #{output.empty? ? 'nothing' : "this:\n#{output.chomp}"}"
    end
  end

  # What the gate prints about a check that ran past its lane's budget,
  # before it ends the check: whether its process still runs, its output
  # so far, every process under it or in its group, and a stack sample of
  # each, taken with /usr/bin/sample on macOS, or eu-stack or gdb on Linux
  # where either is installed.
  #
  # Under load, or with a process stuck in the kernel, ps itself can take
  # long or fail; the diagnosis then says so, lists the processes again
  # without their arguments, which ps reads from each process, and if that
  # fails too, samples the check's own process.
  class Diagnosis
    # How long one listing of processes may take, in seconds.
    PS_TIMEOUT = 30

    # How long one stack sample may take, in seconds.
    SAMPLE_TIMEOUT = 60

    # The listings tried in order: with each process's arguments, then
    # with only its name.
    LISTINGS = [
      %w[ps -A -ww -o pid,ppid,pgid,etime,stat,command],
      %w[ps -A -o pid,ppid,pgid,etime,stat,comm],
    ].freeze

    # The tools whose time limits +timeouts+ may set, and their defaults.
    TIMEOUTS = { ps: PS_TIMEOUT, sample: SAMPLE_TIMEOUT }.freeze

    # [child] The check's Child, whose state is taken now, as the lane
    #         times out.
    # [lane] The lane's number, as the gate's lines name it.
    # [name] The check's name.
    # [timeouts] Seconds each tool may take, by its key in TIMEOUTS; those
    #            not given keep their defaults.
    def initialize(child, lane:, name:, timeouts: {})
      @timeouts = self.class.timeouts(timeouts)
      @child = child
      @lane = lane
      @name = name
      @state = state
      @output = child.output
    end

    # The diagnosis, as lines to print.
    def to_s
      listing, processes = list
      [
        "--- lane #{@lane} diagnostics: #{@name} ---",
        @state,
        "--- its output so far ---",
        @output.chomp,
        "--- its processes (ps) ---",
        *listing,
        *stacks(processes),
        "--- end of lane #{@lane} diagnostics ---",
      ].join("\n")
    end

    private def state
      status = @child.status
      return "the check's process, #{@child.pid}, is still running" unless status
      return "the check's process exited (#{status}), but its output is still open" if @child.open?

      "the check's process exited (#{status}) as its time ran out"
    end

    # The lines to print for the processes, and the processes to sample:
    # [pid, line] pairs. A listing that fails is printed as its failure,
    # and the next one tried.
    private def list
      printed = []
      LISTINGS.each do |command|
        tool = Tool.run(command, timeout: @timeouts.fetch(:ps))
        header, *rows = tool.output.lines.map(&:chomp)
        processes = tree(rows) if tool.ok?
        return [printed + [header, *processes.map { |_, line| line }], processes] if processes&.any?

        printed << (tool.ok? ? "#{command.first} listed none of its processes; it printed:\n#{tool.output.chomp}" : tool.failure)
      end
      [printed, [[@child.pid, "the check's process"]]]
    end

    # The check's process and its descendants, and every process left in
    # its group, whose parent may have exited, from ps's +rows+ for every
    # process: [pid, line] pairs, the line as ps printed it.
    private def tree(rows)
      table = rows.filter_map do |line|
        pid, ppid, pgid = line.split.first(3).map { |field| Integer(field, exception: false) }
        [pid, ppid, pgid, line] if pid && ppid && pgid
      end
      under = [@child.pid]
      loop do
        more = table.filter_map { |pid, ppid| pid if under.include?(ppid) && !under.include?(pid) }
        break if more.empty?

        under.concat(more)
      end
      table.select { |pid, _, pgid| under.include?(pid) || pgid == @child.pid }.map { |pid, *, line| [pid, line] }
    end

    # A sample of each process, taken at the same time, each headed by the
    # command ps listed for it, its sixth column on.
    private def stacks(processes)
      timeout = @timeouts.fetch(:sample)
      processes.map { |pid, line| [pid, line.split(nil, 6).fetch(5, line), Thread.new { self.class.stack(pid, timeout:) }] }
        .flat_map { |pid, name, thread| ["--- stack of #{pid}: #{name} ---", thread.value.chomp] }
    end

    # TIMEOUTS with +given+ in place of the defaults, refusing a tool it
    # does not know, so that a misspelled key fails as the gate starts,
    # not as a lane times out.
    def self.timeouts(given)
      unknown = given.keys - TIMEOUTS.keys
      raise ArgumentError, "unknown tool timeouts: #{unknown.join(', ')}" if unknown.any?

      TIMEOUTS.merge(given)
    end

    # The stack of +pid+, from the first sampler this system has, which
    # may take +timeout+ seconds.
    def self.stack(pid, timeout: SAMPLE_TIMEOUT)
      if File.executable?("/usr/bin/sample")
        sample(pid, timeout:)
      elsif (tool = which("eu-stack"))
        report(Tool.run([tool, "-p", pid.to_s], timeout:))
      elsif (tool = which("gdb"))
        report(Tool.run([tool, "-batch", "-p", pid.to_s, "-ex", "thread apply all bt"], timeout:))
      else
        "no stack sampler here (/usr/bin/sample, eu-stack, or gdb)"
      end
    end

    # macOS's sample, for one second, which writes its report to a file
    # and says only where on its output. The list of loaded images that
    # ends the report, hundreds of lines for each process, is left out.
    def self.sample(pid, timeout: SAMPLE_TIMEOUT)
      Dir.mktmpdir("lota-gate-sample") do |dir|
        file = File.join(dir, "#{pid}.txt")
        tool = Tool.run(["/usr/bin/sample", pid.to_s, "1", "-mayDie", "-file", file], timeout:)
        next tool.failure unless tool.ok? && File.exist?(file)

        text = File.read(file)
        text[/\A.*?(?=^Binary Images:)/m] || text
      end
    end

    def self.report(tool) = tool.ok? ? tool.output : tool.failure

    def self.which(tool)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }
        .find { |path| File.executable?(path) }
    end
  end
end
