# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"
require_relative "../unseen_desktop"

# Lövetest's love.window tests (vendor/love/testing/tests/window.lua),
# translated to Ruby by ADR 001's rules. Like the graphics tests, they run
# in the test suite's own process (test/lovetest/window_test.rb) and under
# lota run (test/lovetest/game).
#
# The tests that fill the screen, or maximize, minimize, raise, or move
# the window, change what the person at the computer sees, so each runs
# holding the desktop input lock (the desktop_input_lock gem) and, with it,
# asks them to step away: test/native/focus_for_tests.rb does so around
# the tests in the suite's process and under lota run, and package:install
# does around its whole run. None of them moves the pointer or types.
class WindowTest < Lovetest::TestMethod
  # getIcon checks that no icon is set until setIcon sets one, and LÖVE
  # has no way to unset it, so getIcon's test runs before setIcon's in
  # the process's one window: alphabetical order puts the one first. No
  # other test of Lota sets an icon.
  i_suck_and_my_tests_are_order_dependent!

  # Lets frames go by until the block is true, for at most ten seconds, and
  # returns whether it was. Lövetest lets ten go by (waitFrames(10)) and
  # then checks, which suffices when a frame takes its sixtieth of a
  # second. The system minimizes, maximizes, restores, and fills the
  # screen with a window with an animation of its own, which a frame that
  # does not wait for the display, as one with vsync off or with the window
  # hidden, outruns, and which takes seconds when several programs do it
  # at once. A wait is over as soon as the block is true, and, with +stay+
  # seconds, once it has stayed true that long, for a state the system
  # reports before it has finished changing.
  def wait_for(stay = 0, timeout = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    since = nil
    loop do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      since = yield ? (since || now) : nil
      return true if since && now - since >= stay
      return false if now > deadline

      wait_frames(1)
      sleep(0.01)
    end
  end

  # Goes fullscreen and lets the system finish, which on macOS takes the
  # animation of a Space, until the window has the size of the screen. A
  # window sent back before it arrives is sent back to a transition still
  # under way, and arrives later, in the middle of the next test.
  def enter_fullscreen(size)
    Lota::Window.set_fullscreen(true)
    wait_for(0.5) { Lota::Window.fullscreen.first && Lota::Window.mode.first(2) != size }
  end

  # Leaves fullscreen and lets the system finish, until the window has the
  # size it had.
  def leave_fullscreen(size)
    Lota::Window.set_fullscreen(false)
    wait_for(0.5) { !Lota::Window.fullscreen.first && Lota::Window.mode.first(2) == size && Lota::Window.visible? }
  end

  # Restores the window and lets the system finish: not minimized, not
  # maximized, and visible, so the next test finds the window as the last
  # one found it.
  def restore_window
    Lota::Window.restore
    wait_for(0.5) { !Lota::Window.minimized? && !Lota::Window.maximized? && Lota::Window.visible? }
  end

  # Lövetest skips a test on a GitHub runner on Linux, where xvfb has no
  # window manager to do what it asks, with +reason+.
  def skip_on_linux_runner(reason)
    skip(reason) if Lovetest::GITHUB_RUNNER && Lovetest.os?("Linux")
  end

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

  # Translated to Ruby from love.test.window.focus
  # (window.lua:12-15): focus stays focus (rule 13). Lövetest cannot test
  # it, as the function returns nothing, and only checks that it exists.
  def test_focus
    assert_equal(true, Lota::Window.respond_to?(:focus), "check method exists")
  end

  # Translated to Ruby from love.test.window.fromPixels and
  # love.test.window.toPixels (window.lua:19-24 and 368-373):
  # fromPixels becomes from_pixels and toPixels to_pixels (rule 13), and
  # getDPIScale dpi_scale.
  def test_from_pixels
    # check dpi/pixel ratio as expected
    dpi = Lota::Window.dpi_scale
    pixels = Lota::Window.from_pixels(100)
    assert_equal(100 / dpi, pixels, "check dpi ratio")
  end

  def test_to_pixels
    # check dpi/pixel ratio is as expected
    dpi = Lota::Window.dpi_scale
    pixels = Lota::Window.to_pixels(50)
    assert_equal(50 * dpi, pixels, "check dpi ratio")
  end

  # Translated to Ruby from love.test.window.getDPIScale
  # (window.lua:29-31): dependent on hardware, so the best it can do is
  # not nil. Lövetest's test asserts assertNotNil(test), that its own
  # test object is not nil, and never calls getDPIScale, a slip in
  # Lövetest; this asserts what its comment means, that dpi_scale is not
  # nil.
  def test_get_dpi_scale
    assert_not_nil(Lota::Window.dpi_scale)
  end

  # Translated to Ruby from love.test.window.getDisplayCount
  # (window.lua:45-47): getDisplayCount becomes display_count (rule 3).
  def test_get_display_count
    assert_operator(Lota::Window.display_count, :>=, 1, "check 1 display")
  end

  # Translated to Ruby from love.test.window.getDisplayName
  # (window.lua:52-54): getDisplayName becomes display_name.
  def test_get_display_name
    assert_not_nil(Lota::Window.display_name(1))
  end

  # Translated to Ruby from love.test.window.getDisplayOrientation
  # (window.lua:59-61): getDisplayOrientation becomes display_orientation
  # and its name a symbol (rule 9).
  def test_get_display_orientation
    assert_not_nil(Lota::Window.display_orientation(1))
  end

  # Translated to Ruby from love.test.window.getFullscreen
  # (window.lua:65-76): getFullscreen becomes fullscreen (rule 3), whose
  # two values are an Array (rule 4). setFullscreen returns whether the
  # system agreed, so it stays a method (rule 7).
  def test_get_fullscreen
    skip_on_linux_runner("xvfb on Linux doesn't support fullscreen")

    size = Lota::Window.mode.first(2)
    # check not fullscreen to start
    assert_false(Lota::Window.fullscreen.first, "check not fullscreen")
    enter_fullscreen(size)
    # check now fullscreen
    assert_true(Lota::Window.fullscreen.first, "check now fullscreen")
    leave_fullscreen(size) # reset
  end

  # Translated to Ruby from love.test.window.getFullscreenModes
  # (window.lua:81-83): getFullscreenModes becomes fullscreen_modes.
  def test_get_fullscreen_modes
    assert_not_nil(Lota::Window.fullscreen_modes(1))
  end

  # Translated to Ruby from love.test.window.getIcon
  # (window.lua:87-94): getIcon becomes icon (rule 3), and setIcon, which
  # returns whether the system took the icon, set_icon (rule 7).
  # newImageData becomes ImageData.new (rule 2), reading the file from
  # Lövetest's resources.
  def test_get_icon
    # check icon nil by default if not set
    assert_nil(Lota::Window.icon, "check nil by default")
    icon = Lota::Image::ImageData.new("resources/love.png")
    # check getting icon not nil after setting
    Lota::Window.set_icon(icon)
    assert_not_nil(Lota::Window.icon)
  end

  # Translated to Ruby from love.test.window.getPosition and
  # love.test.window.setPosition (window.lua:109-114 and 334-341):
  # getPosition becomes position, whose three values are an Array
  # (rules 3 and 4), and setPosition the writer position= (rules 5 and 6).
  # Lövetest leaves the window where it put it; these put it back, so the
  # person at the computer finds it where it was.
  def test_get_position
    x0, y0, display = Lota::Window.position
    Lota::Window.position = 100, 100, 1
    x, y, = Lota::Window.position
    assert_equal(100, x, "check position x")
    assert_equal(100, y, "check position y")
    Lota::Window.position = x0, y0, display
  end

  def test_set_position
    x0, y0, display = Lota::Window.position
    # check position is returned
    Lota::Window.position = 100, 100, 1
    # Lövetest lets ten frames go by (waitFrames(10)); the system moves
    # the window when it gets to it, and can report a move an earlier test
    # made after this one, so the frames go by until it reports this one.
    wait_for { Lota::Window.position.first(2) == [100, 100] }
    x, y, = Lota::Window.position
    assert_equal(100, x, "check position x")
    assert_equal(100, y, "check position y")
    Lota::Window.position = x0, y0, display
  end

  # Translated to Ruby from love.test.window.getTitle and
  # love.test.window.setTitle (window.lua:129-134 and 345-350): getTitle
  # becomes title and setTitle the writer title= (rules 3 and 5). They put
  # back the title they found, where Lövetest sets "love.test", so a test
  # that reads the window's title finds it as the settings made it.
  def test_get_title
    title = Lota::Window.title
    # check title returned is what was set
    Lota::Window.title = "love.testing"
    assert_equal("love.testing", Lota::Window.title, "check title match")
    Lota::Window.title = title
  end

  def test_set_title
    title = Lota::Window.title
    # check setting title val is returned
    Lota::Window.title = "love.testing"
    assert_equal("love.testing", Lota::Window.title, "check title matches")
    Lota::Window.title = title
  end

  # Translated to Ruby from love.test.window.getVSync and
  # love.test.window.setVSync (window.lua:138-140 and 354-357): getVSync
  # becomes vsync (rule 13: the V stands for "vertical", so VSync is one
  # word) and setVSync the writer vsync= (rule 5). Lövetest leaves vsync
  # off; this puts it back.
  def test_get_vsync
    assert_not_nil(Lota::Window.vsync)
  end

  def test_set_vsync
    before = Lota::Window.vsync
    Lota::Window.vsync = 0
    assert_not_nil(Lota::Window.vsync)
    Lota::Window.vsync = before
  end

  # Translated to Ruby from love.test.window.hasFocus and
  # love.test.window.hasMouseFocus (window.lua:145-154): hasFocus becomes
  # the predicate focus? and hasMouseFocus mouse_focus? (rule 8). Neither
  # can force focus, so they only check for an answer.
  def test_has_focus
    assert_not_nil(Lota::Window.focus?)
  end

  def test_has_mouse_focus
    assert_not_nil(Lota::Window.mouse_focus?)
  end

  # Translated to Ruby from love.test.window.isDisplaySleepEnabled and
  # love.test.window.setDisplaySleepEnabled (window.lua:158-166 and
  # 278-285): isDisplaySleepEnabled becomes display_sleep_enabled? and
  # setDisplaySleepEnabled the writer display_sleep_enabled= (rules 8
  # and 5).
  def test_is_display_sleep_enabled
    assert_not_nil(Lota::Window.display_sleep_enabled?)
    # check disabled
    Lota::Window.display_sleep_enabled = false
    assert_false(Lota::Window.display_sleep_enabled?, "check sleep disabled")
    # check enabled
    Lota::Window.display_sleep_enabled = true
    assert_true(Lota::Window.display_sleep_enabled?, "check sleep enabled")
  end

  def test_set_display_sleep_enabled
    # check disabling sleep
    Lota::Window.display_sleep_enabled = false
    assert_false(Lota::Window.display_sleep_enabled?, "check sleep disabled")
    # check setting it back to enabled
    Lota::Window.display_sleep_enabled = true
    assert_true(Lota::Window.display_sleep_enabled?, "check sleep enabled")
  end

  # Translated to Ruby from love.test.window.isMaximized and
  # love.test.window.maximize (window.lua:170-181 and 224-236):
  # isMaximized becomes maximized? (rule 8). On macOS the window is
  # not maximized at once, so the test waits a few frames.
  def test_is_maximized
    skip_on_linux_runner("xvfb on Linux doesn't support window maximization")

    assert_false(Lota::Window.maximized?, "check window not maximized")
    Lota::Window.maximize
    wait_frames(10)
    # on MACOS maximize wont get recognised immedietely so wait a few frames
    wait_for { Lota::Window.maximized? }
    assert_true(Lota::Window.maximized?, "check window now maximized")
    restore_window
  end

  def test_maximize
    skip_on_linux_runner("xvfb on Linux doesn't support window maximization")

    assert_false(Lota::Window.maximized?, "check window not maximized")
    # check maximizing is set
    Lota::Window.maximize
    wait_frames(10)
    # on macos we need to wait a few frames
    wait_for { Lota::Window.maximized? }
    assert_true(Lota::Window.maximized?, "check window maximized")
    restore_window
  end

  # Translated to Ruby from love.test.window.isMinimized,
  # love.test.window.minimize, and love.test.window.restore
  # (window.lua:185-198, 240-252, and 262-274): isMinimized becomes
  # minimized? (rule 8).
  def test_is_minimized
    skip_on_linux_runner("xvfb on Linux doesn't support window minimization")

    # check not minimized to start
    assert_false(Lota::Window.minimized?, "check window not minimized")
    # try to minimize
    Lota::Window.minimize
    wait_frames(10)
    # on linux minimize won't get recognized immediately, so wait a few frames
    wait_for { Lota::Window.minimized? }
    assert_true(Lota::Window.minimized?, "check window minimized")
    restore_window
  end

  def test_minimize
    skip_on_linux_runner("xvfb on Linux doesn't support window minimization")

    assert_false(Lota::Window.minimized?, "check window not minimized")
    # check minimizing is set
    Lota::Window.minimize
    wait_frames(10)
    # on linux we need to wait a few frames
    wait_for { Lota::Window.minimized? }
    assert_true(Lota::Window.minimized?, "check window maximized")
    restore_window
  end

  def test_restore
    skip_on_linux_runner("xvfb on Linux doesn't support window minimization")

    # check minimized to start
    Lota::Window.minimize
    wait_frames(10)
    wait_for { Lota::Window.minimized? }
    Lota::Window.restore
    wait_frames(10)
    # check restoring the state of the window
    wait_for { !Lota::Window.minimized? }
    assert_false(Lota::Window.minimized?, "check window restored")
    restore_window
  end

  # Translated to Ruby from love.test.window.isOccluded
  # (window.lua:202-205): isOccluded becomes occluded? (rule 8). Focusing
  # the window is what puts it in front, so test/native/focus_for_tests.rb
  # gives it focus for this test, holding the desktop input lock, where
  # the tests' windows otherwise stay in the background. On a desktop that
  # macOS does not draw (LOTA_DESKTOP_UNSEEN, test/lovetest/unseen_desktop.rb)
  # no window can be seen, so it skips, as Lövetest skips what its
  # machine cannot do.
  def test_is_occluded
    skip(UnseenDesktop::REASON) if UnseenDesktop.on?
    Lota::Window.focus
    wait_for { !Lota::Window.occluded? }
    assert_false(Lota::Window.occluded?, "check window not occluded")
  end

  # Translated to Ruby from love.test.window.isVisible
  # (window.lua:217-220): isVisible becomes visible? (rule 8).
  def test_is_visible
    # check visible initially
    assert_true(Lota::Window.visible?, "check window visible")
  end

  # Translated to Ruby from love.test.window.requestAttention
  # (window.lua:256-258): test:skipTest becomes Minitest's skip, as
  # Lövetest skips it.
  def test_request_attention
    skip("cant test this worked")
  end

  # Translated to Ruby from love.test.window.setFullscreen
  # (window.lua:289-300). setFullscreen returns whether the system agreed
  # (rule 7), so it stays set_fullscreen.
  def test_set_fullscreen
    skip_on_linux_runner("xvfb on Linux doesn't support fullscreen")

    size = Lota::Window.mode.first(2)
    # check fullscreen is set
    enter_fullscreen(size)
    assert_true(Lota::Window.fullscreen.first, "check fullscreen")
    # check setting back to normal
    leave_fullscreen(size)
    assert_false(Lota::Window.fullscreen.first, "check not fullscreen")
  end

  # Translated to Ruby from love.test.window.setIcon
  # (window.lua:305-310): setIcon becomes set_icon (rule 7). It runs
  # after getIcon's test (see the order above), so the icon is set already,
  # which changes nothing it checks.
  def test_set_icon
    # check setting an icon returns the val
    icon = Lota::Image::ImageData.new("resources/love.png")
    Lota::Window.set_icon(icon)
    refute_equal(nil, Lota::Window.icon, "check icon not nil")
  end

  # Translated to Ruby from love.test.window.showMessageBox
  # (window.lua:362-364): test:skipTest becomes Minitest's skip, as
  # Lövetest skips it.
  def test_show_message_box
    skip("cant test this worked")
  end
  # SPDX-SnippetEnd
end
