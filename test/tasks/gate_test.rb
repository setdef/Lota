# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "stringio"
require_relative "../../tasks/gate"

# Runs the gate's checks through real rake processes, over a Rakefile of
# small tasks.
class GateTest < Minitest::Test
  include TreeHelper

  RAKEFILE = <<~RUBY
    task(:built) { File.write("built.log", File.read("built.log").succ) if File.exist?("built.log") }
    task(:ok) { puts "ok ran" }
    task(:slow) { sleep 1; File.write("slow.at", Time.now.to_f.to_s); puts "slow ran" }
    task(:quick) { File.write("quick.at", Time.now.to_f.to_s); puts "quick ran" }
    task(:bad) { puts "bad output"; abort "bad failed" }
    task(:needs_built => :built) { puts "needs built" }
  RUBY

  def gate(root, lanes, jobs: lanes.size)
    write(root, "Rakefile", RAKEFILE)
    out = StringIO.new
    [Gate.new(prepared: %w[built], lanes:, jobs:, root:, out:), out]
  end

  def check(*tasks) = Gate::Check.of(*tasks)

  def test_prints_each_check_whole_in_declared_order_with_timings
    in_tree do |root|
      gate, out = gate(root, [[check("slow")], [check("ok")]])
      gate.run { nil }

      report = out.string

      assert_operator report.index("gate: slow"), :<, report.index("slow ran")
      assert_operator report.index("slow ran"), :<, report.index("gate: ok")
      assert_operator report.index("gate: ok"), :<, report.index("ok ran")
      assert_match(/gate timings.*slow\s+\d+ s\s+passed.*ok\s+\d+ s\s+passed.*total/m, report)
    end
  end

  def test_lanes_run_at_the_same_time_and_a_lane_runs_in_order
    in_tree do |root|
      gate, = gate(root, [[check("slow"), check("quick")], [check("ok")]])
      gate.run { nil }

      assert_operator File.read(File.join(root, "slow.at")).to_f, :<, File.read(File.join(root, "quick.at")).to_f
    end
  end

  def test_one_job_runs_every_check_in_one_lane
    in_tree do |root|
      gate, out = gate(root, [[check("slow")], [check("quick")]], jobs: 1)
      gate.run { nil }

      assert_operator File.read(File.join(root, "slow.at")).to_f, :<, File.read(File.join(root, "quick.at")).to_f
      assert_includes out.string, "slow ran"
    end
  end

  def test_a_failure_raises_after_printing_its_output_and_starts_no_more_of_its_lane
    in_tree do |root|
      gate, out = gate(root, [[check("bad"), check("quick")], [check("ok")]])
      error = assert_raises(Gate::Failure) { gate.run { nil } }

      assert_equal "gate failed: bad", error.message
      assert_includes out.string, "❌ gate: bad"
      assert_includes out.string, "bad output"
      assert_includes out.string, "FAILED"
      refute_path_exists File.join(root, "quick.at")
    end
  end

  def test_a_prepared_task_is_not_run_again_by_a_check_that_needs_it
    in_tree do |root|
      gate, out = gate(root, [[check("needs_built")]])
      File.write(File.join(root, "built.log"), "0")
      gate.run { |name| assert_equal "built", name }

      assert_includes out.string, "needs built"
      assert_equal "0", File.read(File.join(root, "built.log"))
    end
  end
end
