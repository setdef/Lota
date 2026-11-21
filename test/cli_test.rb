# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/cli"

# The lota program's own arguments, which it reads before any game, as
# love.cpp's runlove reads --version and --help (vendor/love/src/love.cpp,
# lines 153-187). Running a game is test/native/lota_run_test.rb's to
# prove, in a process of its own.
class CLITest < Minitest::Test
  # Runs the CLI with +argv+ and returns its standard output, standard
  # error, and what it returned.
  def lota(*argv)
    status = nil
    stdout, stderr = capture_io { status = Lota::CLI.call(argv) }
    [stdout, stderr, status]
  end

  def test_version_prints_the_version_and_quits
    stdout, _stderr, status = lota("--version")

    assert_equal 0, status
    assert_equal "Lota #{Lota::VERSION}\n", stdout
  end

  def test_help_prints_loves_usage_translated_and_quits
    stdout, _stderr, status = lota("--help")

    assert_equal 0, status
    assert_equal Lota::CLI.usage, stdout
    assert_includes stdout, "    lota path/to/gamedir            runs the game from the given directory " \
      "which contains a main.rb file\n"
    assert_includes stdout, "    lota path/to/packagedgame.lota  runs the packaged game from the provided .lota file\n"
    assert_includes stdout, "    lota path/to/file.rb            runs the game from the given .rb file\n"
  end

  # love.cpp reads --version and --help only as the program's first
  # argument, and has no short forms and no commands.
  def test_the_usage_names_no_short_forms_and_no_run_command
    refute_match(/ -v| -h|lota run/, Lota::CLI.usage)
    refute Lota::CLI.const_defined?(:COMMANDS)
  end
end
