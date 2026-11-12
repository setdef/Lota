# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/jobs"

# Jobs counts how many processes the builds and clang-tidy run at once:
# LOTA_JOBS when given, else the cores, and fewer when a real cgroup
# folder's limits leave less CPU or memory, or the computer has less
# memory available than its compile jobs want.
class JobsTest < Minitest::Test
  include TreeHelper

  def test_lota_jobs_says_how_many
    assert_equal 3, Jobs.count(env: { "LOTA_JOBS" => "3" }, cores: 24, cgroup: nil, memory: nil)
    assert_equal 40, Jobs.count(env: { "LOTA_JOBS" => "40" }, cores: 24, cgroup: nil, memory: nil)
  end

  def test_lota_jobs_must_be_a_whole_number_of_one_or_more
    %w[0 -2 two 1.5 3x].each do |given|
      error = assert_raises(Jobs::Failure) { Jobs.count(env: { "LOTA_JOBS" => given }, cores: 24, cgroup: nil, memory: nil) }

      assert_includes error.message, "LOTA_JOBS is #{given.inspect}"
    end
  end

  def test_without_lota_jobs_it_is_the_cores
    assert_equal 24, Jobs.count(env: {}, cores: 24, cgroup: nil, memory: nil)
    assert_equal 24, Jobs.count(env: { "LOTA_JOBS" => "" }, cores: 24, cgroup: nil, memory: nil)
  end

  def test_available_memory_gives_each_compile_job_two_gigabytes
    gib = 1 << 30

    assert_equal 8, Jobs.count(env: {}, cores: 24, cgroup: nil, memory: 17 * gib)
    assert_equal 24, Jobs.count(env: {}, cores: 24, cgroup: nil, memory: 64 * gib)
    assert_equal 4, Jobs.count(env: {}, cores: 4, cgroup: nil, memory: 64 * gib)
  end

  def test_too_little_available_memory_still_runs_one_job
    assert_equal 1, Jobs.count(env: {}, cores: 24, cgroup: nil, memory: 1 << 30)
    assert_equal 1, Jobs.count(env: {}, cores: 24, cgroup: nil, memory: 0)
  end

  def test_memory_that_cannot_be_read_leaves_the_cores
    assert_equal 24, Jobs.count(env: {}, cores: 24, cgroup: nil, memory: nil)
  end

  def test_lota_jobs_outranks_available_memory
    assert_equal 12, Jobs.count(env: { "LOTA_JOBS" => "12" }, cores: 24, cgroup: nil, memory: 1 << 30)
  end

  def test_memory_available_is_what_meminfo_says_in_kilobytes
    assert_equal 2048 * 1024, Jobs.meminfo("MemTotal: 9999 kB\nMemFree: 10 kB\nMemAvailable:    2048 kB\n")
  end

  def test_meminfo_without_memavailable_falls_back_to_memfree
    assert_equal 30_701_140 * 1024, Jobs.meminfo("MemTotal:       66227436 kB\nMemFree:        30701140 kB\nSwapFree: 1 kB\n")
    assert_nil Jobs.meminfo("MemTotal: 66227436 kB\n")
    assert_nil Jobs.meminfo("")
  end

  def test_memory_available_on_macos_is_the_free_inactive_and_speculative_pages
    vm_stat = <<~TEXT
      Mach Virtual Memory Statistics: (page size of 16384 bytes)
      Pages free:                               1000.
      Pages active:                             5000.
      Pages inactive:                           2000.
      Pages speculative:                         500.
      Pages wired down:                         3000.
    TEXT

    assert_equal 3500 * 16_384, Jobs.vm_stat(vm_stat)
    assert_nil Jobs.vm_stat("")
  end

  def test_memory_available_on_windows_is_the_free_physical_memory_in_kilobytes
    assert_equal 21_385_128 * 1024, Jobs.free_physical_memory("21385128\r\n")
    assert_nil Jobs.free_physical_memory("")
    assert_nil Jobs.free_physical_memory("Get-CimInstance : not found")
  end

  def test_memory_is_read_from_the_first_source_that_has_it
    in_tree do |dir|
      path = write(dir, "meminfo", "MemAvailable: 4 kB\n")

      assert_equal 4096, Jobs.memory(meminfo: path, others: -> { raise "not asked" })
      assert_equal 7, Jobs.memory(meminfo: File.join(dir, "missing"), others: -> { 7 })
      assert_nil Jobs.memory(meminfo: File.join(dir, "missing"), others: -> {})
    end
  end

  def test_a_cgroup_with_no_limits_leaves_the_cores
    in_tree do |dir|
      write(dir, "cpu.max", "max 100000\n")
      write(dir, "memory.max", "max\n")

      assert_equal 24, Jobs.count(env: {}, cores: 24, cgroup: dir, memory: nil)
    end
  end

  def test_a_cgroups_cpu_quota_rounds_up_to_whole_cores
    in_tree do |dir|
      write(dir, "cpu.max", "250000 100000\n")

      assert_equal 3, Jobs.count(env: {}, cores: 24, cgroup: dir, memory: nil)
    end
  end

  def test_a_cgroups_memory_gives_each_job_its_share
    in_tree do |dir|
      write(dir, "memory.max", "#{5 * Jobs::MEMORY}\n")

      assert_equal 5, Jobs.count(env: {}, cores: 24, cgroup: dir, memory: nil)
    end
  end

  def test_a_cgroup_too_small_for_one_job_still_runs_one
    in_tree do |dir|
      write(dir, "memory.max", "#{Jobs::MEMORY / 2}\n")

      assert_equal 1, Jobs.count(env: {}, cores: 24, cgroup: dir, memory: nil)
    end
  end

  def test_lota_jobs_outranks_the_cgroup
    in_tree do |dir|
      write(dir, "cpu.max", "100000 100000\n")

      assert_equal 6, Jobs.count(env: { "LOTA_JOBS" => "6" }, cores: 24, cgroup: dir, memory: nil)
    end
  end

  def test_the_cgroup_is_the_one_proc_names_under_the_unified_hierarchy
    in_tree do |dir|
      group = File.join(dir, "sys/fs/cgroup/app.slice/run.scope")
      FileUtils.mkdir_p(group)
      proc = write(dir, "self-cgroup", "0::/app.slice/run.scope\n")

      assert_equal group, Jobs.cgroup(proc:, root: File.join(dir, "sys/fs/cgroup"))
      assert_nil Jobs.cgroup(proc: File.join(dir, "missing"), root: File.join(dir, "sys/fs/cgroup"))
      write(dir, "v1-cgroup", "12:cpu,cpuacct:/app.slice\n")

      assert_nil Jobs.cgroup(proc: File.join(dir, "v1-cgroup"), root: File.join(dir, "sys/fs/cgroup"))
    end
  end

  def test_cmake_builds_as_many_jobs_unless_told_otherwise
    assert_equal({ "CMAKE_BUILD_PARALLEL_LEVEL" => "4" }, Jobs.environment({}, 4))
    assert_equal({}, Jobs.environment({ "CMAKE_BUILD_PARALLEL_LEVEL" => "2" }, 4))
    assert_equal({ "CMAKE_BUILD_PARALLEL_LEVEL" => "4" },
      Jobs.environment({ "CMAKE_BUILD_PARALLEL_LEVEL" => "2", "LOTA_JOBS" => "4" }, 4))
  end
end
