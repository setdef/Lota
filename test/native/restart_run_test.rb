# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../../tasks/desktop_input"
require "rbconfig"
require "tmpdir"

# A game that restarts, end to end (Lota::Restart): each test runs the lota
# executable on test/games/restart in a Ruby of its own, which opens a real
# window, and reads the log the game's runs append to. LÖVE restarts in the
# same process (src/love.cpp, main); Lota replaces the process with
# itself, so the pid stays the same and a new Ruby, with a new Lota, runs.
class RestartRunTest < Minitest::Test
  include NativeHelper

  GAME = File.join(ROOT, "test/games/restart")

  def setup
    super
    @desktop_input = DesktopInput.acquire(speak: false)
    @directory = Dir.mktmpdir("lota-restart-test")
    @log = File.join(@directory, "log")
  end

  def teardown
    FileUtils.remove_entry(@directory)
    super
  ensure
    @desktop_input&.release
  end

  # Runs <tt>lota run</tt> on the game with +arguments+ and returns its
  # output and Process::Status. The load path travels in RUBYOPT, which a
  # restarted process inherits, as Ruby's own flags are not repeated but
  # for -w.
  def lota_run(*, environment: {})
    native = File.dirname(File.dirname(loaded("lota/native")))
    native_test = File.dirname(loaded("lota_native_test"))
    load_path = [native, File.join(ROOT, "lib"), native_test].uniq.map { |path| "-I#{path}" }.join(" ")
    capture2e({ "RUBYOPT" => load_path, "LOTA_RESTART_LOG" => @log }.merge(environment), RbConfig.ruby, "-w",
      File.join(ROOT, "exe/lota"), "run", GAME, *)
  end

  # The lines of the log: [kind, fields] for each, with the fields as a
  # Hash of String to the text after the equals sign.
  def log
    File.readlines(@log, chomp: true).map do |line|
      kind, rest = line.split(" ", 2)
      [kind, rest.scan(/(\w+)=(.*?)(?= \w+=|\z)/).to_h]
    end
  end

  def test_a_restart_runs_the_game_again_in_the_same_process_and_hands_over_its_value
    output, status = lota_run("string")

    assert_equal 3, status.exitstatus, output
    kinds = log.map(&:first)

    assert_equal %w[load at_exit load at_exit], kinds, "the first run ended before the second began"
    first, first_exit, second, second_exit = log.map(&:last)

    assert_equal first["pid"], second["pid"], "exec keeps the process"
    assert_equal [first["pid"]] * 2, [first_exit["pid"], second_exit["pid"]]
    assert_equal "nil", first["restart"]
    assert_equal "\"café\\nline\"", second["restart"]
    assert_equal %w[false false], [first["variable"], second["variable"]], "the value is read once and removed"
    assert_equal [%(["string"])] * 2, [first["arguments"], second["arguments"]], "the same arguments"
    assert_equal %w[true true], [first["verbose"], second["verbose"]], "-w is kept"
  end

  def test_every_kind_of_value_arrives_as_the_event_queue_carries_it
    {
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
    }.each do |name, expected|
      FileUtils.rm_f(@log)
      output, status = lota_run(name)

      assert_equal 3, status.exitstatus, "#{name}: #{output}"
      assert_equal expected, log.fetch(2).last["restart"], name
    end
  end

  def test_a_game_that_quits_does_not_start_again
    output, status = lota_run("never")

    assert_predicate status, :success?, output
    assert_equal %w[load at_exit], log.map(&:first)
  end

  def test_the_value_a_game_starts_with_is_read_once_whoever_wrote_it
    text = Lota::Restart.encode("hello")
    _, status = lota_run("never", environment: { "LOTA_RESTART_VALUE" => text })

    assert_predicate status, :success?
    assert_equal ['"hello"', "false"], log.first.last.values_at("restart", "variable")

    FileUtils.rm_f(@log)
    lota_run("never", environment: { "LOTA_RESTART_VALUE" => "eval:exit!(9)" })

    assert_equal ["nil", "false"], log.first.last.values_at("restart", "variable")
  end

  def test_nothing_is_left_to_restart_when_the_game_is_not_run_by_lota_run
    code = <<~RUBY
      require "lota"
      Lota::Restart.take
      p Lota.restart
    RUBY
    native = File.dirname(File.dirname(loaded("lota/native")))
    output, status = capture2e({ "LOTA_RESTART_VALUE" => Lota::Restart.encode(4) }, RbConfig.ruby,
      "-I#{native}", "-I#{File.join(ROOT, 'lib')}", "-e", code)

    assert_predicate status, :success?, output
    assert_equal "4.0\n", output
  end
end
