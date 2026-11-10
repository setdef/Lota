# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "fake_machines"
require_relative "../../tasks/machines_run"
require "shellwords"
require "stringio"

# MachinesRun builds the machines run commands Lota's checks take, and
# runs them at once against a fake machines program that answers as the
# real one does.
class MachinesRunTest < Minitest::Test
  include TreeHelper
  include FakeMachines

  OLD = "b" * 40
  NEW = "a" * 40

  def setup
    @tree = File.realpath(Dir.mktmpdir("lota-machines-run"))
    @bin = File.join(@tree, "bin")
  end

  def teardown
    FileUtils.rm_rf(@tree)
  end

  def machines(env = {}, program: "/bin/machines") = MachinesRun.new(env:, program:)

  # The command line +run+ runs, as a shell would read it.
  def line(run) = Shellwords.join(run.argv)

  # Runs +runs+ through the fake machines, answering as +config+ says.
  def run_all(config, runs, prefix: true)
    program = fake_machines(@bin, config)
    out = StringIO.new
    runs = runs.map { |run| run.with(argv: [program, *run.argv.drop(1)]) }
    results = MachinesRun.new(env: {}, program:).run_all(runs, output: out, chdir: @tree, prefix:)
    [results, out.string]
  end

  def test_the_linux_prepush_ships_the_commit_with_its_base_and_runs_the_gate_script_on_both
    run = machines({ "AGENT_NAME" => "sample-agent" }).linux_prepush(old: OLD, new: NEW)

    assert_equal "linux", run.name
    assert_equal "/bin/machines run linux --project lota --commit #{NEW} --base #{OLD} --label lota\\ prepush " \
      "--agent sample-agent --timeout 2700 -- script/remote-gate prepush #{OLD} #{NEW}", line(run)
  end

  def test_the_windows_prepush_takes_the_whole_machine_for_the_commit
    run = machines.windows_prepush(new: NEW)

    assert_equal "windows", run.name
    assert_equal "/bin/machines run windows --exclusive --project lota --commit #{NEW} " \
      "--label lota\\ windows\\ prepush --agent agent --timeout 3600 -- bash .github/windows_prepush.sh", line(run)
  end

  def test_a_gpu_mode_needs_a_node_with_the_gpu_and_tells_the_script
    %w[opengl vulkan].each do |mode|
      argv = machines({ "LOTA_GATE_GPU" => mode }).linux_prepush(old: OLD, new: NEW).argv

      assert_equal ["--require", "gpu=radeon", "--env", "LOTA_GATE_GPU=#{mode}"], argv[5, 4], mode
    end
    refute_includes machines({ "LOTA_GATE_GPU" => "off" }).gate.argv, "--require"
    refute_includes machines({ "LOTA_GATE_GPU" => "vulkan" }).windows_prepush(new: NEW).argv, "--require"
  end

  def test_the_gate_ships_the_working_tree_and_names_its_tasks
    assert_equal "/bin/machines run linux --project lota --label lota\\ gate\\ prepush\\ lint --agent agent " \
      "--timeout 3600 -- script/remote-gate full prepush lint", line(machines.gate(%w[prepush lint]))
    assert_equal ["--label", "lota gate"], machines.gate.argv[5, 2]
    assert_equal "/bin/machines run windows --exclusive --project lota --label lota\\ windows\\ checks " \
      "--agent agent --timeout 3600 -- bash .github/windows_prepush.sh", line(machines.windows_gate)
  end

  def test_the_command_is_found_on_path
    write(@tree, "plain/machines", "not executable")
    program = fake_machines(@bin)

    assert_equal program, MachinesRun.find({ "PATH" => [File.join(@tree, "plain"), @bin].join(File::PATH_SEPARATOR) })
    assert_nil MachinesRun.find({ "PATH" => File.join(@tree, "plain") })
    assert_nil MachinesRun.find({})
  end

  def test_the_command_is_found_and_run_outside_the_bundle
    skip "the tests run outside a bundle" unless defined?(Bundler)

    path, rubyopt = MachinesRun.outside_bundle { [ENV.fetch("PATH", nil), ENV.fetch("RUBYOPT", nil)] }

    assert_equal Bundler.original_env["PATH"], path
    refute_match(%r{bundler/setup}, rubyopt.to_s)
  end

  def test_runs_go_at_once_and_each_line_carries_its_runs_name
    results, out = run_all({ "together" => %w[linux windows] },
      [machines.linux_prepush(old: OLD, new: NEW), machines.windows_prepush(new: NEW)])

    assert_equal [true, true], results.map(&:passed?)
    assert_equal %w[linux windows], results.map(&:name)
    assert_includes out, "[linux] hello from linux\n"
    assert_includes out, "[windows] hello from windows\n"
    assert_includes out, "[linux] RUN_EXIT=0 id=fake-linux"
    assert(out.each_line.all? { |line| line.start_with?("[linux] ", "[windows] ") }, out)
  end

  def test_the_commands_failure_is_its_run_exit_code
    results, = run_all({ "linux" => { "code" => 3 } }, [machines.gate])

    refute_predicate results.first, :passed?
    assert_equal 3, results.first.code
    assert_equal "the command failed (exit 3)", results.first.reason
  end

  def test_machines_trouble_without_a_run_exit_line_is_the_machines_being_unavailable
    trouble = { "machines" => 75, "why" => "the connection dropped", "partial" => "cut off" }
    results, out = run_all({ "linux" => trouble }, [machines.gate], prefix: false)

    assert_nil results.first.code
    assert_equal "build machines unavailable (machines run exited 75)", results.first.reason
    assert_equal "hello from linux\nmachines: the connection dropped\ncut off\n", out
  end

  def test_a_refused_call_is_not_the_commands_failure
    results, = run_all({ "linux" => { "machines" => 1 } }, [machines.gate])

    assert_equal "machines run refused the call (exit 1)", results.first.reason
  end

  def test_without_the_command_nothing_runs_and_it_says_so
    results = MachinesRun.new(env: { "PATH" => @tree }).run_all([machines.gate], output: StringIO.new, chdir: @tree)

    refute_predicate results.first, :passed?
    assert_equal "the machines command is not on PATH", results.first.reason
  end
end
