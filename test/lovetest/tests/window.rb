# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.window tests (vendor/love/testing/tests/window.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/window_test.rb) and under lota run (test/lovetest/game).
class WindowTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.window.isOpen
  # (vendor/love/testing/tests/window.lua:209-213): isOpen becomes open?
  # (rule 8).
  def test_is_open
    # check open initially
    assert_true(Lota::Window.open?, "check window open")
    # we check closing in test.window.close
  end

  # Translated to Ruby from love.test.window.getDesktopDimensions
  # (window.lua:36-40): getDesktopDimensions becomes desktop_dimensions
  # (rule 3), and its two results an Array (rule 4).
  def test_get_desktop_dimensions
    w, h = Lota::Window.desktop_dimensions
    assert_not_nil(w)
    assert_not_nil(h)
  end

  # Translated to Ruby from love.test.window.getSafeArea
  # (window.lua:119-125): getSafeArea becomes safe_area (rule 3), and its
  # four results an Array (rule 4).
  def test_get_safe_area
    x, y, w, h = Lota::Window.safe_area
    assert_not_nil(x)
    assert_not_nil(y)
    assert_not_nil(w)
    assert_not_nil(h)
  end

  # Translated to Ruby from love.test.window.getMode
  # (window.lua:99-104): getMode becomes mode (rule 3), its three results
  # an Array (rule 4), and its table a frozen Mode (rule 10), whose fields
  # Ruby reads with a dot where Lua indexes with a string.
  def test_get_mode
    w, h, flags = Lota::Window.mode
    assert_equal(360, w, "check w")
    assert_equal(240, h, "check h")
    assert_false(flags.fullscreen, "check fullscreen")
  end

  # Translated to Ruby from love.test.window.setMode
  # (window.lua:315-331): setMode becomes set_mode (rule 7), with its
  # table's settings as keywords (rule 10).
  def test_set_mode
    # set window mode
    Lota::Window.set_mode(512, 512, fullscreen: false, resizable: false)
    # check what we set is returned
    width, height, flags = Lota::Window.mode
    assert_equal(512, width, "check window w match")
    assert_equal(512, height, "check window h match")
    assert_false(flags.fullscreen, "check window not fullscreen")
    assert_false(flags.resizable, "check window not resizeable")
    Lota::Window.set_mode(360, 240, fullscreen: false, resizable: true)
  end

  # Translated to Ruby from love.test.window.updateMode
  # (window.lua:377-405): updateMode becomes update_mode (rule 13), with
  # its table's settings as keywords (rule 10), so its nil table is no
  # keywords at all.
  def test_update_mode
    # set initial mode
    Lota::Window.set_mode(512, 512, fullscreen: false, resizable: false)
    # update mode with some props but not others
    Lota::Window.update_mode(360, 240)
    # check only changed values changed
    width, height, flags = Lota::Window.mode
    assert_equal(360, width, "check window w match")
    assert_equal(240, height, "check window h match")
    assert_false(flags.fullscreen, "check window not fullscreen")
    assert_false(flags.resizable, "check window not resizeable")
    Lota::Window.set_mode(360, 240, fullscreen: false, resizable: true) # reset

    # test different combinations of the backbuffer depth/stencil buffer.
    wait_frames(1)
    Lota::Window.update_mode(360, 240, depth: false, stencil: false)
    wait_frames(1)
    Lota::Window.update_mode(360, 240, depth: true, stencil: true)
    wait_frames(1)
    Lota::Window.update_mode(360, 240, depth: true, stencil: false)
    wait_frames(1)
    Lota::Window.update_mode(360, 240, depth: false, stencil: true)
  end
  # SPDX-SnippetEnd
end
