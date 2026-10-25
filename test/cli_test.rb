# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/cli"

# The lota executable's argument handling, as rooibos's CLI handles its
# own. Running a game is test/native/lota_run_test.rb's to prove, in a
# process of its own.
class CLITest < Minitest::Test
  # Runs the CLI with +argv+ and returns its standard output, standard
  # error, and exit status, or nil when it did not exit.
  def lota(*argv)
    status = nil
    stdout, stderr = capture_io do
      Lota::CLI.call(argv)
    rescue SystemExit => e
      status = e.status
    end
    [stdout, stderr, status]
  end

  def test_version_flag
    %w[--version -v].each do |flag|
      stdout, _stderr, status = lota(flag)

      assert_nil status
      assert_equal "Lota #{Lota::VERSION}\n", stdout
    end
  end

  def test_help_flag_and_no_arguments_show_usage
    [["--help"], ["-h"], []].each do |argv|
      stdout, _stderr, status = lota(*argv)

      assert_nil status
      assert_includes stdout, "Usage: lota <command>"
      assert_includes stdout, "run [path] [arguments]"
    end
  end

  def test_unknown_command_exits_with_error
    _stdout, stderr, status = lota("unknown")

    assert_equal 1, status
    assert_includes stderr, "Unknown command: unknown"
    assert_includes stderr, "Usage: lota <command>"
  end

  def test_run_help
    %w[--help -h].each do |flag|
      stdout, _stderr, status = lota("run", flag)

      assert_equal 0, status
      assert_includes stdout, "Usage: lota run [path] [arguments]"
    end
  end

  def test_run_reports_a_path_that_is_not_a_folder_as_love_does
    missing = File.expand_path("no/such/game")

    _stdout, stderr, status = lota("run", "no/such/game")

    assert_equal 1, status
    assert_equal "Error: Cannot load game at path '#{missing}'.\nMake sure a folder exists at the specified path.\n",
      stderr
  end

  def test_run_reports_a_file_as_not_a_folder
    _stdout, stderr, status = lota("run", __FILE__)

    assert_equal 1, status
    assert_includes stderr, "Cannot load game at path '#{File.expand_path(__FILE__)}'."
  end

  def test_the_command_list_names_every_command
    assert_equal ["run"], Lota::CLI::COMMANDS.keys
  end
end
