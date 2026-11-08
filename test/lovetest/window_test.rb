# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's love.window tests, translated in tests/window.rb, in the
# test suite's own process. test/native/lota_run_test.rb runs them again
# through lota run.
require_relative "../test_helper"
require_relative "tests/window"
require_relative "../native/native_helper"
require_relative "../native/focus_for_tests"

WindowTest.prepend(FocusForTests)

# Lövetest's window tests call setMode and updateMode with only the
# settings they check, which LÖVE answers by making the window with its
# defaults for the rest (no depth buffer, usedpiscale on), and the tests of
# display sleep leave it enabled, which LÖVE starts disabled. WindowTest
# puts the window back as test/lovetest/conf.rb opens it after each test,
# so that a suite run after them, in the same process, draws into the
# window it expects. Without that, this fails with the last call's mode.
class WindowStateTest < Minitest::Test
  MODE = { fullscreen: false, resizable: true, depth: true, stencil: true, usedpiscale: false }.freeze

  def test_a_window_test_leaves_the_window_as_it_found_it
    EngineHelper.open_window
    Lota::Window.set_mode(360, 240, **MODE) unless window == [360, 240, MODE]
    Lota::Window.display_sleep_enabled = false

    %w[test_set_mode test_update_mode test_is_display_sleep_enabled test_set_display_sleep_enabled].each do |name|
      assert_predicate WindowTest.new(name).run, :passed?, name
    end

    assert_equal [360, 240, MODE, false], window + [Lota::Window.display_sleep_enabled?]
  ensure
    Lota::Window.set_mode(360, 240, **MODE) unless window == [360, 240, MODE]
    Lota::Window.display_sleep_enabled = false
  end

  private def window
    width, height, flags = Lota::Window.mode
    [width, height, flags.to_h.slice(*MODE.keys)]
  end
end
