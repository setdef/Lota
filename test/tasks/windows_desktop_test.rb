# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/windows_desktop"

# WindowsDesktop names the Windows tests that need the desktop to
# themselves, and gives Minitest the patterns that run only them or leave
# them out.
class WindowsDesktopTest < Minitest::Test
  def pattern(option) = Regexp.new(option[%r{\A/(.*)/\z}, 1])

  def test_the_desktop_set_runs_the_tests_it_names_and_nothing_else
    only = pattern(WindowsDesktop.only)

    assert_match only, "MouseTest#test_set_position"
    assert_match only, "MouseTest#test_set_grabbed"
    assert_match only, "WindowTest#test_is_occluded"
    assert_match only, "LotaRunTest#test_lovetest_passes_when_run_by_lota_run"
    assert_match only, "WindowStateTest#test_it_describes_sdls_window_as_macos_sees_it"
    refute_match only, "MouseTest#test_is_down"
    refute_match only, "WindowTest#test_set_position"
    refute_match only, "OtherMouseTest#test_set_position"
    refute_match only, "MouseTest#test_set_position_twice"
  end

  def test_the_shared_set_leaves_out_the_desktop_set_and_what_else_it_is_told
    alone = pattern(WindowsDesktop.leave_out)
    with_prepush = pattern(WindowsDesktop.leave_out("/\\A(?:LotaRunTest#.*)\\z/"))

    assert_match alone, "MouseTest#test_set_position"
    refute_match alone, "MouseTest#test_is_down"
    refute_match alone, "LotaRunTest#test_a_game_runs_from_the_current_directory"
    assert_match with_prepush, "MouseTest#test_set_position"
    assert_match with_prepush, "LotaRunTest#test_a_game_runs_from_the_current_directory"
    refute_match with_prepush, "MouseTest#test_is_down"
  end

  def test_the_desktop_set_runs_only_the_files_that_hold_its_tests
    assert_equal WindowsDesktop::GROUPS.map(&:file).uniq.sort, WindowsDesktop.files
    assert_includes WindowsDesktop.files, "test/lovetest/mouse_test.rb"
    refute_includes WindowsDesktop.files, "test/lovetest/keyboard_test.rb"
  end

  def test_each_group_says_why_its_tests_need_the_desktop
    WindowsDesktop::GROUPS.each do |group|
      refute_empty group.tests, group.file
      refute_empty group.reason, group.file
      group.tests.each { |name| assert_match(/\A[A-Z]\w*#test_\w+\z/, name) }
    end
  end
end
