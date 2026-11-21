# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"

module NativeHelper
  # A process a test started that is still running past its time, and
  # what can be said of where it hung before it is killed: it and every
  # process under it, as ps lists them, and a stack sample of each, taken
  # with /usr/bin/sample on macOS, or with eu-stack or gdb on Linux where
  # either is installed, as the gate diagnoses a hung lane (tasks/
  # gate_process.rb, Gate::Diagnosis). The gate starts its tools with
  # Process.spawn, which forks; under rake test:native a forked child can
  # die before it runs its command, so these start with NativeHelper.spawn.
  #
  # Windows has neither ps nor a stack sampler, so there the report says
  # so and only the process is killed.
  class HungProcess
    # The listing of every process, with each one's arguments.
    LISTING = %w[ps -A -ww -o pid,ppid,pgid,etime,stat,command].freeze

    # How long, in seconds, the listing or one stack sample may take.
    TOOL_TIMEOUT = 30

    # [pid] The process's id.
    def initialize(pid)
      @pid = pid
      @listing, @processes = list
    end

    # The report, as lines to print.
    def to_s
      ["--- processes (ps) ---", *@listing, *stacks].join("\n")
    end

    # Kills the process and every process under it that the listing found.
    def kill
      ([@pid] | @processes.map(&:first)).each do |pid|
        Process.kill(:KILL, pid)
      rescue Errno::ESRCH
        nil
      end
    end

    # The lines to print, and the processes to sample: [pid, line] pairs.
    private def list
      return [["no ps on Windows"], []] if TestHome::WINDOWS

      ok, output = self.class.run(LISTING)
      header, *rows = output.lines.map(&:chomp)
      processes = ok ? tree(rows) : []
      return [[header, *processes.map(&:last)], processes] if processes.any?

      [["ps listed none of them; it printed:", output.chomp], [[@pid, "the process"]]]
    end

    # The process and its descendants among ps's +rows+.
    private def tree(rows)
      table = rows.filter_map do |line|
        pid, ppid = line.split.first(2).map { |field| Integer(field, exception: false) }
        [pid, ppid, line] if pid && ppid
      end
      under = [@pid]
      loop do
        more = table.filter_map { |pid, ppid| pid if under.include?(ppid) && !under.include?(pid) }
        break if more.empty?

        under.concat(more)
      end
      table.select { |pid, _| under.include?(pid) }.map { |pid, _, line| [pid, line] }
    end

    # A sample of each process, taken at the same time, each headed by its
    # command as ps listed it.
    private def stacks
      @processes.map { |pid, line| [pid, line.split(nil, 6).fetch(5, line), Thread.new { self.class.stack(pid) }] }
        .flat_map { |pid, name, thread| ["--- stack of #{pid}: #{name} ---", thread.value.chomp] }
    end

    # The stack of +pid+, from the first sampler this system has.
    def self.stack(pid)
      if File.executable?("/usr/bin/sample") then sample(pid)
      elsif (tool = which("eu-stack")) then report(*run([tool, "-p", pid.to_s]))
      elsif (tool = which("gdb")) then report(*run([tool, "-batch", "-p", pid.to_s, "-ex", "thread apply all bt"]))
      else "no stack sampler here (/usr/bin/sample, eu-stack, or gdb)"
      end
    end

    # macOS's sample, for one second, which writes its report to a file.
    # The list of loaded images that ends it is left out.
    def self.sample(pid)
      Dir.mktmpdir("lota-test-sample") do |dir|
        file = File.join(dir, "#{pid}.txt")
        ok, output = run(["/usr/bin/sample", pid.to_s, "1", "-mayDie", "-file", file])
        next report(false, output) unless ok && File.exist?(file)

        text = File.read(file)
        text[/\A.*?(?=^Binary Images:)/m] || text
      end
    end

    def self.report(ok, output) = ok ? output : "the sampler failed; it printed:\n#{output}"

    # Runs +command+ without the sanitizer runtime this process may carry
    # (TOOL_ENV), and returns whether it succeeded and what it printed. One
    # that runs past TOOL_TIMEOUT is killed.
    def self.run(command)
      variables = ENV.to_h.merge(TOOL_ENV).compact.map { |name, value| "#{name}=#{value}" }
      reader, writer = IO.pipe
      begin
        pid = NativeHelper.spawn(command, writer, variables)
      ensure
        writer.close
      end
      output = Thread.new { reader.read }
      Process.kill(:KILL, pid) unless output.join(TOOL_TIMEOUT)
      status = Process.wait2(pid).last
      [status.success?, output.value]
    rescue SystemCallError => e
      [false, e.message]
    ensure
      reader&.close
    end

    def self.which(tool)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }
        .find { |path| File.executable?(path) }
    end
  end
end
