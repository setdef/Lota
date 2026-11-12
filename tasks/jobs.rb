# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"
require "rbconfig"

# How many processes Lota's builds and clang-tidy each run at once.
#
# LOTA_JOBS, a whole number of 1 or more, says how many. Without it, it is
# the cores this process may use (Etc.nprocessors, which on Linux counts
# the ones its CPU affinity allows), and fewer when the Linux cgroup it runs
# in gives it less CPU time (cpu.max) or less memory than MEMORY for each
# (memory.max), as a container or a CI runner may, and fewer when the
# computer has less memory available right now than COMPILE_MEMORY for each,
# since the engine's largest sources take a gigabyte or more of a compiler.
# The available memory comes from /proc/meminfo, where there is one (Linux,
# and MSYS2, whose meminfo has MemFree but no MemAvailable), or from vm_stat
# on macOS, or from Win32_OperatingSystem through PowerShell on native
# Windows; where none can be read, it limits nothing. A computer that
# runs several checkouts' checks at once, which none of those limits sees,
# sets LOTA_JOBS to its share, since each clang-tidy takes some 600 MB and
# every source starts one.
#
# The gate's lanes run side by side (tasks/gate.rake), so while one lane
# builds the sanitized extension another runs clang-tidy, each with this
# many processes.
module Jobs
  # Raised when LOTA_JOBS is not a whole number of 1 or more.
  class Failure < StandardError; end

  # The memory, in bytes, each job is given: a clang-tidy of one of Lota's
  # sources, which parses Rice's headers, or a compiler at the engine's
  # largest file.
  MEMORY = 1 << 30

  # The memory, in bytes, each job is given out of the memory the computer
  # has available: twice MEMORY, since a compiler at the engine's largest
  # file (spirv_glsl.cpp) takes a gigabyte or more and the computer's other
  # work shares the rest.
  COMPILE_MEMORY = 2 * MEMORY

  # How many jobs run at once, given +env+, the +cores+ this process may
  # use, the +cgroup+ folder whose limits apply, or nil, and the +memory+
  # in bytes the computer has available, or nil where it is not known.
  def self.count(env: ENV, cores: Etc.nprocessors, cgroup: self.cgroup, memory: self.memory)
    given = env.fetch("LOTA_JOBS", "")
    return whole(given) unless given.empty?

    [cores, *limits(cgroup), (memory / COMPILE_MEMORY if memory)].compact.min.clamp(1, nil)
  end

  # The bytes of memory available to start new work, from the file at
  # +meminfo+ or else from +others+, a callable that asks the system as
  # macOS and Windows do; nil where none can be read.
  def self.memory(meminfo: "/proc/meminfo", others: method(:ask))
    from_file = self.meminfo(File.read(meminfo)) if File.file?(meminfo)
    from_file || others.call
  rescue SystemCallError
    nil
  end

  # The bytes +text+, a /proc/meminfo, says are available: MemAvailable, or
  # else MemFree, which is all MSYS2 gives and, there, counts the memory
  # Windows could hand out; nil when it says neither.
  def self.meminfo(text)
    kilobytes = %w[MemAvailable MemFree].filter_map { |key| text[/^#{key}:\s+(\d+) kB/, 1] }.first
    Integer(kilobytes, 10) * 1024 if kilobytes
  end

  # The bytes +text+, the kilobytes of free physical memory Windows'
  # Win32_OperatingSystem reports, makes; nil when it is not a whole number.
  def self.free_physical_memory(text)
    kilobytes = text.strip
    Integer(kilobytes, 10) * 1024 if kilobytes.match?(/\A\d+\z/)
  end

  # The bytes +text+, the output of macOS's vm_stat, says are free,
  # inactive, or speculative, which the system takes back for new work; nil
  # when it says no page size.
  def self.vm_stat(text)
    size = text[/page size of (\d+) bytes/, 1]
    return unless size

    pages = ["free", "inactive", "speculative"].sum { |kind| text[/^Pages #{kind}:\s+(\d+)\./, 1].to_i }
    Integer(size, 10) * pages
  end

  # The cgroup folder this process runs in, under cgroup v2's unified
  # hierarchy at +root+, as +proc+ names it; nil where there is none.
  def self.cgroup(proc: "/proc/self/cgroup", root: "/sys/fs/cgroup")
    path = File.readlines(proc, chomp: true).find { |line| line.start_with?("0::") }&.delete_prefix("0::")
    folder = path && File.join(root, path)
    folder if folder && File.directory?(folder)
  rescue SystemCallError
    nil
  end

  # What the builds' environment gains from +env+ so that CMake's builds,
  # which otherwise run as many jobs as their generator likes, run +count+:
  # CMAKE_BUILD_PARALLEL_LEVEL, unless +env+ sets it and not LOTA_JOBS.
  def self.environment(env, count)
    return {} if env.key?("CMAKE_BUILD_PARALLEL_LEVEL") && env.fetch("LOTA_JOBS", "").empty?

    { "CMAKE_BUILD_PARALLEL_LEVEL" => count.to_s }
  end

  private_class_method def self.whole(given)
    count = Integer(given, 10, exception: false)
    return count if count&.positive?

    raise Failure, "LOTA_JOBS is #{given.inspect}; give a whole number of 1 or more, or leave it unset"
  end

  # The jobs the cgroup's CPU time and memory leave room for.
  private_class_method def self.limits(cgroup)
    return [] unless cgroup

    quota, period = read(cgroup, "cpu.max").split
    memory = read(cgroup, "memory.max")
    [
      (Integer(quota, 10).fdiv(Integer(period, 10)).ceil if quota&.match?(/\A\d+\z/) && period&.match?(/\A\d+\z/)),
      (Integer(memory, 10) / MEMORY if memory.match?(/\A\d+\z/)),
    ].compact
  end

  # What macOS's vm_stat or Windows' PowerShell says is available, run
  # only there; nil elsewhere or when it fails.
  private_class_method def self.ask
    case RbConfig::CONFIG["host_os"]
    when /darwin/ then vm_stat(run("vm_stat"))
    when /mingw|mswin|cygwin/
      free_physical_memory(run("powershell", "-NoProfile", "-NonInteractive", "-Command",
        "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"))
    end
  rescue SystemCallError
    nil
  end

  private_class_method def self.run(*command)
    IO.popen(command, err: File::NULL, &:read)
  end

  private_class_method def self.read(cgroup, name)
    File.read(File.join(cgroup, name)).strip
  rescue SystemCallError
    ""
  end
end
