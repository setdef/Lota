# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"

# How many processes Lota's builds and clang-tidy each run at once.
#
# LOTA_JOBS, a whole number of 1 or more, says how many. Without it, it is
# the cores this process may use (Etc.nprocessors, which on Linux counts
# the ones its CPU affinity allows), and fewer when the Linux cgroup it runs
# in gives it less CPU time (cpu.max) or less memory than MEMORY for each
# (memory.max), as a container or a CI runner may. A computer that runs
# several checkouts' checks at once, which none of those limits sees, sets
# LOTA_JOBS to its share, since each clang-tidy takes some 600 MB and
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

  # How many jobs run at once, given +env+, the +cores+ this process may
  # use, and the +cgroup+ folder whose limits apply, or nil.
  def self.count(env: ENV, cores: Etc.nprocessors, cgroup: self.cgroup)
    given = env.fetch("LOTA_JOBS", "")
    return whole(given) unless given.empty?

    [cores, *limits(cgroup)].min.clamp(1, nil)
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

  private_class_method def self.read(cgroup, name)
    File.read(File.join(cgroup, name)).strip
  rescue SystemCallError
    ""
  end
end
