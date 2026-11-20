# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/package_check"

# What the delivery check says of a game that runs tests, such as
# Lövetest's: the summary Minitest printed, so the log of every delivery
# says how many tests ran and skipped.
class PackageSummaryTest < Minitest::Test
  def test_the_summary_is_the_line_minitest_ends_with
    printed = "love.conf\nRun options: --seed 1\n\n362 runs, 1496 assertions, 0 failures, 0 errors, 13 skips\n"

    assert_equal "362 runs, 1496 assertions, 0 failures, 0 errors, 13 skips", PackageCheck.summary(printed)
  end

  def test_a_game_that_runs_no_tests_has_no_summary
    assert_nil PackageCheck.summary("window 800x600\n")
  end

  def game(output)
    PackageCheck::Game.new(name: "probe", folder: nil, files: {}, gems: [], arguments: [], output:, status: 0)
  end

  def test_a_games_output_is_its_pattern
    assert_equal(/\Awindow\n\z/, game(/\Awindow\n\z/).expected({}))
  end

  def test_a_game_can_expect_what_an_earlier_game_found_out
    expect = game(-> (printed) { /^#{printed.fetch('facts')[/\d+/]} runs/ })

    assert_equal(/^7 runs/, expect.expected("facts" => "sensors 7\n"))
  end

  def test_only_a_whole_line_is_a_summary
    assert_nil PackageCheck.summary("it said 3 runs, 4 assertions, 0 failures, 0 errors, 0 skips once\n")
  end
end
