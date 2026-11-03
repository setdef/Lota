# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "lota"
require "lota_native_test"
require "desktop_input_lock"

# Gives the window focus for two of Lövetest's tests alone: its
# love.mouse.setGrabbed test (test/lovetest/tests/mouse.rb), which SDL
# passes only for the window with keyboard focus, for which it grabs the
# mouse (SDL 3.4.10, src/video/SDL_video.c, SDL_UpdateWindowGrab), and its
# love.window.isOccluded test (test/lovetest/tests/window.rb), which
# passes only for a window in front of the others, as focusing the window
# puts it, where the windows of the gate's other checks, centered where
# this one is, would otherwise cover it. The tests' windows stay in the
# background (test/test_helper.rb), so they take no focus from the person
# at the computer, and these two take it for the moment each runs.
# test/lovetest/mouse_test.rb, window_test.rb, and system_test.rb prepend
# it to MouseTest, WindowTest, and SystemTest, and
# test/native/lota_run_test.rb loads it with ruby -r into the lota run of
# test/lovetest/game, where it prepends itself once each is defined.
#
# It waits for the focus before the test starts, and on macOS for the
# program it took the focus from to have it back before the lock goes to
# anyone else (take_focus and give_focus_back), so a test reads only what
# it ensured, and no answer of the system to one holder arrives in the
# next one's turn. On Linux the window keeps the focus (give_focus_back).
#
# Afterward, on macOS, it gives the focus back and keeps the program in the
# background (LotaNativeTest.unfocus_window), and takes the events that
# queued off the queue, among them the key releases SDL sends as the
# window loses focus. A window left with focus would lose it whenever the
# person clicked elsewhere, and SDL would then let go of every key held
# down (SDL 3.4.10, src/events/SDL_keyboard.c, SDL_SetKeyboardFocus and
# SDL_ResetKeyboard), even one a later test holds, as the error handler's
# test of Ctrl+C holds Ctrl (test/native/error_handler_test.rb).
#
# The gate's checks run at the same time (tasks/gate.rb), and another
# process taking the focus would fail these tests, so each holds the desktop
# input lock (the desktop_input_lock gem) from setup to teardown, and, since
# what the person at the computer types would go to its window, asks them
# to step away. Every other test of MouseTest holds the lock too, silently,
# since they set the pointer, which is the computer's, and read it back,
# and another process moving it between the two fails them, but their
# windows stay in the background. So does every test of WindowTest, which
# fill the screen, minimize, and move windows, and which several programs
# doing so at once leave in states they were not in when the tests asked,
# and those that can be seen ask the person to step away as well.
#
# The windows of the gate's other checks hold no lock, and need none. On
# macOS the system puts a window that a program in the background opens or
# raises behind the windows of the active program, so it neither covers a
# window these tests focused nor takes its focus; and one that opens over
# a MouseTest window in the background changes nothing the test reads,
# since SDL sets the position it reads after a warp itself, for its own
# window at the point (SDL 3.4.10, src/video/cocoa/SDL_cocoamouse.m,
# Cocoa_WarpMouseGlobal). On Linux each lane has a display of its own
# (tasks/gate.rb).
module FocusForTests
  # The test of each class that takes focus.
  FOCUSING = { "MouseTest" => "test_set_grabbed", "WindowTest" => "test_is_occluded" }.freeze

  # The tests that ask the person at the computer to step away, though
  # they take no focus, because they fill the screen, minimize, maximize,
  # or move the window.
  SPEAKING = {
    "WindowTest" => %w[
      test_get_fullscreen
      test_set_fullscreen
      test_is_maximized
      test_maximize
      test_is_minimized
      test_minimize
      test_restore
      test_get_position
      test_set_position
],
  }.freeze

  # The classes whose every test holds the lock, silently: MouseTest's
  # set the pointer, and WindowTest's change the window's state and size
  # in ways the system finishes later, which the windows of other programs
  # on the screen disturb.
  HOLDING = %w[MouseTest WindowTest].freeze

  # The tests of other classes that hold the lock, silently: SystemTest's
  # write the clipboard, which is the computer's, and read it back, and
  # the gate's other checks run them, and the error handler's tests of
  # Ctrl+C (test/native/error_handler_test.rb), at the same time.
  HELD = { "SystemTest" => %w[test_get_clipboard_text test_set_clipboard_text] }.freeze

  # The classes it is prepended to.
  CLASSES = [*FOCUSING.keys, *HELD.keys].freeze

  # Seconds a focusing test waits for its window to have keyboard focus
  # and stand in front of the others, and then for the program it took
  # focus from to have it back. Activating a program goes through the
  # system's window server, which on a loaded machine, such as a CI runner
  # running every lane of the gate, answers in seconds, not the second
  # LotaNativeTest.focus_window waits.
  DEADLINE = 20

  def setup
    super
    focusing = name == FOCUSING[self.class.name]
    speaking = focusing || SPEAKING.fetch(self.class.name, []).include?(name)
    holding = HOLDING.include?(self.class.name) || HELD.fetch(self.class.name, []).include?(name)
    @desktop_input = DesktopInputLock.acquire(speak: speaking) if speaking || holding
    keep_the_pointer_to_the_test if self.class.name == "MouseTest"
    take_focus if focusing
  end

  def teardown
    if name == FOCUSING[self.class.name]
      give_focus_back
      Lota::Event.pump
      Lota::Event.clear
    end
    LotaNativeTest.ignore_mouse_events(false) if self.class.name == "MouseTest"
    super
  ensure
    @desktop_input&.release
  end

  # Gives the window keyboard focus and waits, holding the lock, until SDL
  # has heard that it has it, and, for WindowTest's isOccluded test, that
  # nothing covers it (LotaNativeTest.focus_window), which is what the test
  # then reads: Lövetest's setGrabbed test reads the focus SDL last heard
  # of (SDL_UpdateWindowGrab), and its isOccluded test the occlusion, and
  # neither pumps SDL's events before it reads, so a test that starts here
  # finds them as they were found. Another program can take the focus back
  # in the meantime, as a person's click does, so each try activates the
  # window again; one that never gets it fails here, saying so, and what
  # the system says of the program's windows (LotaNativeTest.window_state),
  # rather than in the test's assertion about state it never had.
  #
  # SDL's occluded flag only remembers what the system last said: SDL sets
  # it when the system says the window's occlusion changed and it cannot
  # be seen, and clears it only when the system says it can
  # (SDL 3.4.10, src/video/cocoa/SDL_cocoawindow.m,
  # windowDidChangeOcclusionState and Cocoa_SendExposedEventIfVisible). In
  # a login session that is not on the console, as a hidden test account's
  # is, the system counts nearly every window as one that cannot be seen,
  # in front or not, so a window whose occlusion the system has said
  # changed, as it does around a fullscreen window's change of space, stays
  # occluded however often this asks, and fails here, the system's answer
  # saying "seen by macOS no" of a window that is key and in front.
  private def take_focus
    seen = self.class.name == "WindowTest"
    deadline = clock + DEADLINE
    loop do
      return if LotaNativeTest.focus_window && !(seen && Lota::Window.occluded?)

      if clock > deadline
        report = LotaNativeTest.window_state
        flunk "#{name} needs its window in front with keyboard focus, and after #{DEADLINE} seconds of " \
          "asking it had focus #{Lota::Window.focus?} and was occluded #{Lota::Window.occluded?}" \
          "#{"; the system says: #{report}" unless report.empty?}"
      end
      sleep 0.05
    end
  end

  # Gives the focus back to the program that had it, and waits, still
  # holding the lock, until SDL hears that the window lost it, so that the
  # system's answer cannot arrive after the next holder of the lock has
  # taken focus for a window of its own, and take it from that one.
  #
  # On Linux there is nothing to give it back to, so it keeps it. Each
  # lane's X display holds only this program's window (tasks/gate.rb),
  # and whatever this hands the focus to, Openbox gives it straight back:
  # given to the X server's PointerRoot or to None, the focus reaches no
  # window, and Openbox then focuses the window that last had it (its
  # focus debug log says "Focus went to root or pointer root/none", then
  # "Focusing client"), which is this one. No other program on the
  # display can take the focus from it, and no person clicks there.
  private def give_focus_back
    return if Lota::System.os == "Linux"
    return if LotaNativeTest.unfocus_window

    deadline = clock + DEADLINE
    until clock > deadline
      Lota::Event.pump
      return unless Lota::Window.focus?

      sleep 0.05
    end
    raise "#{name} gave the focus back, and after #{DEADLINE} seconds its window still had it"
  end

  # Lets the system's mouse events go past the window until teardown, and
  # takes those already queued off the queue. LÖVE's setPosition pumps
  # SDL's events after it moves the pointer (mouse/sdl/Mouse.cpp:158-163),
  # and on macOS the system sends the window mouse moved events at where
  # an earlier warp, or a person's hand, put the pointer, some of them
  # after the next warp, so the pump would read the pointer back from the
  # wrong one (LotaNativeTest.ignore_mouse_events, dialogs.mm). SDL then
  # knows the position only from the test's own warps, as each test
  # expects. It runs before take_focus, whose last pump is the one the
  # test reads.
  private def keep_the_pointer_to_the_test
    LotaNativeTest.ignore_mouse_events(true)
    Lota::Event.pump
    Lota::Event.clear
  end

  private def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

unless FocusForTests::CLASSES.all? { |name| Object.const_defined?(name) }
  prepend_once = TracePoint.new(:end) do |point|
    if FocusForTests::CLASSES.include?(point.self.name) && !point.self.ancestors.include?(FocusForTests)
      point.self.prepend(FocusForTests)
      prepend_once.disable if FocusForTests::CLASSES.all? { |name| Object.const_defined?(name) }
    end
  end
  prepend_once.enable
end
