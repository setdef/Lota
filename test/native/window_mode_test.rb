# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Window.mode and update_mode, beyond what Lövetest's tests for them
# check (test/lovetest/tests/window.rb): getMode's table as a frozen Mode
# (ADR 001, rule 10), and what updateMode keeps and refuses.
class WindowModeTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # Puts back the window Lövetest's conf.rb opens.
  def teardown
    Lota::Window.set_mode(360, 240, resizable: true, depth: true, stencil: true, usedpiscale: false)
  end

  # w_getMode (wrap_Window.cpp:177-245): LÖVE's fields, the display
  # counting from 1, the fullscreen type a symbol (rule 9).
  def test_mode_is_the_size_and_a_frozen_record_of_lovees_settings
    width, height, flags = Lota::Window.mode

    assert_equal [360, 240], [width, height]
    assert_instance_of Lota::Window::Mode, flags
    assert_predicate flags, :frozen?
    assert_equal :desktop, flags.fullscreentype
    assert_equal 1, flags.displayindex
    assert flags.resizable
    assert_kind_of Float, flags.refreshrate
  end

  # w_updateMode (wrap_Window.cpp:153-175) starts from the window's own
  # settings, so a setting left out keeps its value, where setMode would
  # take the default.
  def test_update_mode_keeps_what_it_is_not_given
    Lota::Window.update_mode(minwidth: 100)
    width, height, flags = Lota::Window.mode

    assert_equal [360, 240], [width, height]
    assert_equal 100, flags.minwidth
    assert flags.resizable
  end

  def test_update_mode_needs_a_size_or_a_setting
    error = assert_raises(RuntimeError) { Lota::Window.update_mode }

    assert_equal "Expected at least one argument", error.message
    assert_raises(TypeError) { Lota::Window.update_mode(400) }
  end
end
