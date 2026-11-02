# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "lota"
require "lota_native_test"
require_relative "../../tasks/desktop_input"

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
# test/lovetest/mouse_test.rb and window_test.rb prepend it to MouseTest
# and WindowTest, and test/native/lota_run_test.rb loads it with ruby -r
# into the lota run of test/lovetest/game, where it prepends itself once
# each is defined.
#
# Afterward it gives the focus back and keeps the program in the
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
# input lock (tasks/desktop_input.rb) from setup to teardown, and, since
# what the person at the computer types would go to its window, asks them
# to step away. Every other test of MouseTest holds the lock too, silently,
# since they set the pointer, which is the computer's, and read it back,
# and another process moving it between the two fails them, but their
# windows stay in the background. So does every test of WindowTest, which
# fill the screen, minimize, and move windows, and which several programs
# doing so at once leave in states they were not in when the tests asked,
# and those that can be seen ask the person to step away as well.
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

  def setup
    super
    focusing = name == FOCUSING.fetch(self.class.name)
    speaking = focusing || SPEAKING.fetch(self.class.name, []).include?(name)
    @desktop_input = DesktopInput.acquire(speak: speaking) if speaking || HOLDING.include?(self.class.name)
    LotaNativeTest.focus_window if focusing
  end

  def teardown
    if name == FOCUSING.fetch(self.class.name)
      LotaNativeTest.unfocus_window
      Lota::Event.pump
      Lota::Event.clear
    end
    super
  ensure
    @desktop_input&.release
  end
end

unless FocusForTests::FOCUSING.keys.all? { |name| Object.const_defined?(name) }
  prepend_once = TracePoint.new(:end) do |point|
    if FocusForTests::FOCUSING.key?(point.self.name) && !point.self.ancestors.include?(FocusForTests)
      point.self.prepend(FocusForTests)
      prepend_once.disable if FocusForTests::FOCUSING.keys.all? { |name| Object.const_defined?(name) }
    end
  end
  prepend_once.enable
end
