# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "desktop_input_lock"
require "rbconfig"
require "tmpdir"

# A game that restarts in the same process, as LÖVE's does (src/love.cpp,
# main), with Lota::Restart::IN_PROCESS set: each test runs the lota
# executable on a game in a Ruby of its own, under rake test:native under
# the sanitizers, and reads the log the game's runs append to. Each run
# must find the engine and the game's own definitions fresh, as LÖVE's
# runs find a fresh Lua state.
class InProcessRestartTest < Minitest::Test
  include NativeHelper

  RESTART = File.join(ROOT, "test/games/restart")
  FRESH = File.join(ROOT, "test/games/restart_fresh")

  def setup
    super
    @directory = Dir.mktmpdir("lota-in-process-restart-test")
    @log = File.join(@directory, "log")
    @marker = File.join(@directory, "restart_marker.rb")
    File.write(@marker, <<~RUBY)
      # Counts the runs of a game in this Ruby, which a new Ruby starts
      # again from 1.
      module RestartMarker
        @count = 0
        def self.count = @count += 1
      end
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@directory)
    super
  end

  # Runs <tt>lota run</tt> on +game+ with +arguments+, restarting in the
  # same process, and returns its output and Process::Status. Ruby loads
  # RestartMarker first, so each run logs how many runs its Ruby has seen,
  # which tells a run in the same Ruby from one in a Ruby of its own, as
  # exec starts, though both keep the process id on Linux and macOS.
  def lota_run(game, *, environment: {})
    native = File.dirname(File.dirname(loaded("lota/native")))
    load_path = [native, File.join(ROOT, "lib")].uniq.map { |path| "-I#{path}" }.push("-r#{@marker}").join(" ")
    variables = { "RUBYOPT" => load_path, "LOTA_RESTART_LOG" => @log, "LOTA_IN_PROCESS_RESTART" => "always" }
    capture2e(variables.merge(environment), RbConfig.ruby, "-w", File.join(ROOT, "exe/lota"), "run", game, *)
  end

  # The lines of the log: [kind, fields] for each, with the fields as a
  # Hash of String to the text after the equals sign.
  def log(only: %w[load at_exit])
    File.readlines(@log, chomp: true).filter_map do |line|
      kind, rest = line.split(" ", 2)
      [kind, rest.scan(/(\w+)=(.*?)(?= \w+=|\z)/).to_h] if only.include?(kind)
    end
  end

  def test_a_restart_runs_the_game_again_in_the_same_process_and_hands_over_its_value
    output, status = lota_run(RESTART, "string")

    assert_equal 3, status.exitstatus, output
    assert_equal %w[load at_exit load at_exit], log.map(&:first), "the first run ended before the second began"
    first, first_exit, second, second_exit = log.map(&:last)

    assert_equal [first["pid"]] * 4, [first, first_exit, second, second_exit].map { |fields| fields["pid"] }
    assert_equal %w[1 2], [first["ruby_runs"], second["ruby_runs"]], "the same Ruby"
    assert_equal ["nil", "\"café\\nline\""], [first["restart"], second["restart"]]
    assert_equal %w[false false], [first["variable"], second["variable"]], "nothing crosses in the environment"
    assert_equal [%(["string"])] * 2, [first["arguments"], second["arguments"]], "the same arguments"
  end

  # The value crosses as it crosses exec (test/native/restart_run_test.rb).
  def test_every_kind_of_value_arrives_as_the_event_queue_carries_it
    expected = {
      "nil" => "nil",
      "none" => "nil",
      "true" => "true",
      "false" => "false",
      "number" => "2.5",
      "integer" => "7.0",
      "symbol" => '"name"',
      "empty" => '""',
      "extra" => '"first"',
      "binary" => '"\xFF\u0000"',
      "table" => '[1.0, {"name" => "ada"}]',
    }
    output, status = lota_run(RESTART, "chain", *expected.keys)

    assert_equal 3, status.exitstatus, output
    loads = log.filter_map { |kind, fields| fields if kind == "load" }

    assert_equal ["nil", *expected.values], loads.map { |fields| fields["restart"] }, output
    assert_equal Array.new(loads.size) { |index| (index + 1).to_s }, loads.map { |fields| fields["ruby_runs"] }, "the same Ruby"
  end

  # Each run opens its window, draws, plays a sound, steps a world, and
  # runs a thread, and the next finds none of what it defined or changed:
  # not its constants, files, callbacks, globals, or named channels, and
  # the graphics state is the engine's own again. Ruby warns of nothing
  # defined twice.
  def test_each_run_finds_the_engine_and_the_games_definitions_fresh
    output, status = DesktopInputLock.hold(speak: false) do
      lota_run(FRESH, environment: { "LOTA_RESTARTS" => "3" })
    end

    assert_equal 3, status.exitstatus, output
    refute_match(/warning: (already initialized constant|method redefined)/, output)
    assert_equal %w[load at_exit] * 4, log.map(&:first), output
    loads = log.filter_map { |kind, fields| fields if kind == "load" }

    assert_equal %w[1 2 3 4], loads.map { |fields| fields["run"] }
    assert_equal %w[1 2 3 4], loads.map { |fields| fields["ruby_runs"] }, "the same Ruby"
    assert_equal [loads.first["pid"]] * 4, loads.map { |fields| fields["pid"] }
    assert_equal [loads.first["color"]] * 4, loads.map { |fields| fields["color"] }
    assert_equal [{ "helper" => "1", "global" => "nil", "keypressed" => "false", "channel" => "0", "window" => "true" }] * 4,
      loads.map { |fields| fields.slice("helper", "global", "keypressed", "channel", "window") }
  end
end
