# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "lota"
require "lota_native_test"

# Gives the window keyboard focus for Lövetest's love.mouse.setGrabbed
# test alone (test/lovetest/tests/mouse.rb), which SDL passes only for the
# window with focus, for which it grabs the mouse (SDL 3.4.10,
# src/video/SDL_video.c, SDL_UpdateWindowGrab). The tests' windows stay in
# the background (test/test_helper.rb), so they take no focus from the
# person at the computer, and this one test takes it for the moment it
# runs. test/lovetest/mouse_test.rb prepends it to MouseTest, and
# test/native/lota_run_test.rb loads it with ruby -r into the lota run of
# test/lovetest/game, where it prepends itself once MouseTest is defined.
#
# Afterward it gives the focus back and keeps the program in the
# background (LotaNativeTest.unfocus_window), and takes the events that
# queued off the queue, among them the key releases SDL sends as the
# window loses focus. A window left with focus would lose it whenever the
# person clicked elsewhere, and SDL would then let go of every key held
# down (SDL 3.4.10, src/events/SDL_keyboard.c, SDL_SetKeyboardFocus and
# SDL_ResetKeyboard), even one a later test holds, as the error handler's
# test of Ctrl+C holds Ctrl (test/native/error_handler_test.rb).
module FocusForGrab
  def setup
    super
    LotaNativeTest.focus_window if name == "test_set_grabbed"
  end

  def teardown
    if name == "test_set_grabbed"
      LotaNativeTest.unfocus_window
      Lota::Event.pump
      Lota::Event.clear
    end
    super
  end
end

unless defined?(MouseTest)
  prepend_once = TracePoint.new(:end) do |point|
    if point.self.name == "MouseTest"
      point.self.prepend(FocusForGrab)
      prepend_once.disable
    end
  end
  prepend_once.enable
end
