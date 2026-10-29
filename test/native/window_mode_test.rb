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

  # readWindowSettings (wrap_Window.cpp:78-108) still reads LÖVE 11's
  # forms of three settings, marking each deprecated: depth as a number,
  # display for displayindex, and highdpi, which sets whether high DPI is
  # allowed only while no window is open. The first use of each prints
  # LÖVE's notice, with where set_mode was called, as luaL_where gives it;
  # Lota::Deprecation records names for the whole process, as LÖVE does,
  # so one test uses them all.
  def test_the_deprecated_settings_still_work_and_say_what_replaced_them
    allowed = Lota::Window.high_dpi_allowed?
    line = __LINE__ + 2
    out, = capture_io do
      Lota::Window.set_mode(360, 240, depth: 0, display: 1, highdpi: !allowed)
    end
    _width, _height, flags = Lota::Window.mode

    refute flags.depth
    assert_equal 1, flags.displayindex
    assert_equal allowed, Lota::Window.high_dpi_allowed?, "highdpi changes nothing once a window is open"
    assert_raises(TypeError) { Lota::Window.set_mode(360, 240, highdpi: 1) }
    assert_raises(TypeError) { Lota::Window.update_mode(display: "1") }
    Lota::Window.set_mode(360, 240, depth: 24)
    assert Lota::Window.mode.last.depth, "a depth that is not zero"
    where = "#{__FILE__}:#{line}: "
    assert_includes out, "Lota - Warning: #{where}Using deprecated field window.depth number " \
      "(replaced by window.depth boolean field)\n"
    assert_includes out, "Lota - Warning: #{where}Using deprecated field window.display (replaced by displayindex field)\n"
    assert_includes out, "Lota - Warning: #{where}Using deprecated field window.highdpi " \
      "(replaced by t.highdpi in Lota.conf)\n"
  end
end
