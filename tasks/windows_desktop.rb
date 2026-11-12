# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The tests of the Windows checks (.github/windows_checks.rb tests) that
# need the visible desktop to themselves: each moves Windows' pointer,
# confines it, takes the keyboard focus or activates a window, writes the
# clipboard, or asks which window is in front, and reads back what it
# did. The pointer, the focus, and the clipboard are the desktop's, not
# the test's, so another program on the same desktop doing the same
# between the two fails the test, and the test does the same to that
# program. The desktop input lock (the desktop_input_lock gem,
# test/native/focus_for_tests.rb) keeps Lota's own checks from doing so
# to each other, but not the programs of other projects. On a desktop of
# the run's own that is not on the screen, Windows refuses the calls they
# make outright: SendInput, Get- and SetCursorPos, and
# SetForegroundWindow fail, and GetForegroundWindow answers no window. So
# the checks before a push, which may share the desktop or have one that
# is not on the screen, leave these out (--shared), and a session on the
# visible desktop, with nothing else using its keyboard, mouse, or focus,
# runs exactly them (--desktop). CI's runners are a job's alone, and run
# both.
#
# Every other test the Windows checks run keeps to its own process and
# makes none of those calls: it pushes its key, mouse, and touch events
# into SDL's queue (ext/lota/native_test/native_test.cpp, push), writes
# SDL's own keyboard state (hold), changes only its own window without
# activating it, as moving it does (SDL 3.4.10,
# src/video/windows/SDL_windowswindow.c, WIN_SetWindowPosition, with
# SWP_NOACTIVATE), and reads its frames back from OpenGL, not the screen.
module WindowsDesktop
  # Tests of one file that need the desktop for one reason: +file+ runs
  # +tests+, each "Class#test", and +reason+ says why.
  class Group < Data.define(:file, :tests, :reason)
  end

  GROUPS = [
    Group.new(
      file: "test/lovetest/mouse_test.rb",
      tests: %w[
        MouseTest#test_get_position
        MouseTest#test_get_x
        MouseTest#test_get_y
        MouseTest#test_set_position
        MouseTest#test_set_x
        MouseTest#test_set_y
      ],
      reason: "they move Windows' pointer, which SDL warps with SetCursorPos (SDL 3.4.10, " \
        "src/video/windows/SDL_windowsmouse.c, WIN_WarpMouse), and read it back"
    ),
    Group.new(
      file: "test/lovetest/mouse_test.rb",
      tests: %w[MouseTest#test_set_grabbed],
      reason: "it takes the keyboard focus (test/native/focus_for_tests.rb), pressing Escape and Alt " \
        "with SendInput where Windows refuses (dialogs_windows.cpp, activate), and SDL then confines " \
        "the pointer to the window with ClipCursor (SDL_windowswindow.c, WIN_UpdateClipCursor)"
    ),
    Group.new(
      file: "test/lovetest/mouse_test.rb",
      tests: %w[MouseTest#test_get_relative_mode MouseTest#test_set_relative_mode],
      reason: "relative mode confines the pointer with ClipCursor whenever the window has the focus " \
        "(WIN_UpdateClipCursor), which Windows may give it when the window in front closes"
    ),
    Group.new(
      file: "test/native/cursor_test.rb",
      tests: %w[CursorTest#test_the_global_position_is_the_pointer_on_its_display],
      reason: "it moves Windows' pointer and reads where it is on the desktop"
    ),
    Group.new(
      file: "test/lovetest/window_test.rb",
      tests: %w[WindowTest#test_is_occluded],
      reason: "it takes the keyboard focus (focus_for_tests.rb) and raises the window with " \
        "SetForegroundWindow (SDL_windowswindow.c, WIN_RaiseWindow)"
    ),
    Group.new(
      file: "test/lovetest/window_test.rb",
      tests: %w[
        WindowTest#test_is_maximized
        WindowTest#test_maximize
        WindowTest#test_is_minimized
        WindowTest#test_minimize
        WindowTest#test_restore
      ],
      reason: "ShowWindow's SW_MAXIMIZE and SW_RESTORE activate the window, and SW_MINIMIZE the one " \
        "behind it, whatever program's it is (SDL_windowswindow.c, WIN_MaximizeWindow, " \
        "WIN_RestoreWindow, and WIN_MinimizeWindow)"
    ),
    Group.new(
      file: "test/lovetest/window_test.rb",
      tests: %w[WindowTest#test_get_fullscreen WindowTest#test_set_fullscreen],
      reason: "the window fills the screen, over every other program's (WIN_SetWindowFullscreen)"
    ),
    Group.new(
      file: "test/lovetest/system_test.rb",
      tests: %w[SystemTest#test_get_clipboard_text SystemTest#test_set_clipboard_text],
      reason: "they write the clipboard, which is the desktop's, and read it back"
    ),
    Group.new(
      file: "test/native/error_handler_test.rb",
      tests: %w[
        ErrorHandlerTest#test_ctrl_c_copies_the_error_and_its_traceback
        ErrorHandlerTest#test_c_alone_copies_nothing
        ErrorHandlerTest#test_an_error_whose_text_is_not_utf8_is_shown_without_its_stray_bytes
      ],
      reason: "they write the clipboard, which is the desktop's, and read it back"
    ),
    Group.new(
      file: "test/native/lota_run_test.rb",
      tests: %w[LotaRunTest#test_lovetest_passes_when_run_by_lota_run],
      reason: "it runs all of Lövetest under lota run, the tests above among them"
    ),
    Group.new(
      file: "test/native/window_state_test.rb",
      tests: %w[WindowStateTest#test_it_describes_sdls_window_as_macos_sees_it],
      reason: "it asks which window is in front, with GetForegroundWindow " \
        "(ext/lota/native_test/dialogs_windows.cpp, window_state), which a desktop not on the screen answers with none"
    ),
  ].freeze

  extend self

  # Every test of the desktop set.
  def names = GROUPS.flat_map(&:tests)

  # The files that hold the desktop set, the only ones --desktop runs.
  def files = GROUPS.map(&:file).uniq.sort

  # Minitest's --include pattern for the desktop set.
  def only = "/#{alternatives}/"

  # Minitest's --exclude pattern for the desktop set and, when given,
  # +also+, another --exclude pattern, such as PREPUSH_EXCLUDE.
  def leave_out(also = nil)
    inner = [alternatives, *(also && also[%r{\A/(.*)/\z}, 1])]
    "/#{inner.map { |pattern| "(?:#{pattern})" }.join('|')}/"
  end

  private def alternatives = "\\A(?:#{names.map { |name| Regexp.escape(name) }.join('|')})\\z"
end
