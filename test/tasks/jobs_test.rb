# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/jobs"

# Jobs counts how many processes the builds and clang-tidy run at once:
# LOTA_JOBS when given, else the cores, and fewer when a real cgroup
# folder's limits leave less CPU or memory.
class JobsTest < Minitest::Test
  include TreeHelper

  def test_lota_jobs_says_how_many
    assert_equal 3, Jobs.count(env: { "LOTA_JOBS" => "3" }, cores: 24, cgroup: nil)
    assert_equal 40, Jobs.count(env: { "LOTA_JOBS" => "40" }, cores: 24, cgroup: nil)
  end

  def test_lota_jobs_must_be_a_whole_number_of_one_or_more
    %w[0 -2 two 1.5 3x].each do |given|
      error = assert_raises(Jobs::Failure) { Jobs.count(env: { "LOTA_JOBS" => given }, cores: 24, cgroup: nil) }

      assert_includes error.message, "LOTA_JOBS is #{given.inspect}"
    end
  end

  def test_without_lota_jobs_it_is_the_cores
    assert_equal 24, Jobs.count(env: {}, cores: 24, cgroup: nil)
    assert_equal 24, Jobs.count(env: { "LOTA_JOBS" => "" }, cores: 24, cgroup: nil)
  end

  def test_a_cgroup_with_no_limits_leaves_the_cores
    in_tree do |dir|
      write(dir, "cpu.max", "max 100000\n")
      write(dir, "memory.max", "max\n")

      assert_equal 24, Jobs.count(env: {}, cores: 24, cgroup: dir)
    end
  end

  def test_a_cgroups_cpu_quota_rounds_up_to_whole_cores
    in_tree do |dir|
      write(dir, "cpu.max", "250000 100000\n")

      assert_equal 3, Jobs.count(env: {}, cores: 24, cgroup: dir)
    end
  end

  def test_a_cgroups_memory_gives_each_job_its_share
    in_tree do |dir|
      write(dir, "memory.max", "#{5 * Jobs::MEMORY}\n")

      assert_equal 5, Jobs.count(env: {}, cores: 24, cgroup: dir)
    end
  end

  def test_a_cgroup_too_small_for_one_job_still_runs_one
    in_tree do |dir|
      write(dir, "memory.max", "#{Jobs::MEMORY / 2}\n")

      assert_equal 1, Jobs.count(env: {}, cores: 24, cgroup: dir)
    end
  end

  def test_lota_jobs_outranks_the_cgroup
    in_tree do |dir|
      write(dir, "cpu.max", "100000 100000\n")

      assert_equal 6, Jobs.count(env: { "LOTA_JOBS" => "6" }, cores: 24, cgroup: dir)
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
