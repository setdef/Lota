// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Return pressed on the dialogs a program shows, and keyboard focus for
// the one test that needs it, on Linux (dialogs.hpp; dialogs.mm is macOS's).

#include "native_test/dialogs.hpp"

#include <memory>
#include <stdexcept>

#include <SDL3/SDL_hints.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_video.h>
#include <X11/X.h>
#include <X11/Xlib.h>

// liblota_dialogs's switch and count (answer_dialogs_linux.cpp), which the
// tests and the parity harness load with LD_PRELOAD. A weak reference is
// nullptr in a process it was not loaded into.
extern "C" __attribute__((weak)) void lota_press_return_on_dialogs();
extern "C" __attribute__((weak)) int lota_dialogs_answered();

namespace lota::native_test {

namespace {

// The program's first window, or nullptr when it has none.
SDL_Window *first_window() {
  int count = 0;
  // SDL_GetWindows allocates the list, which SDL_free releases.
  const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
  return (windows && count > 0) ? *windows : nullptr;
}

} // namespace

// SDL shows its dialogs on Linux with zenity, a program of its own, when
// zenity is installed, and otherwise with a window of its own X11 toolkit
// (SDL 3.4.10, src/video/x11/SDL_x11messagebox.c, X11_ShowMessageBox), so
// no code in this process can press a button on every dialog, as dialogs.mm
// does through AppKit. liblota_dialogs answers SDL_ShowMessageBox and
// SDL_ShowSimpleMessageBox in this process instead, with the button Return
// presses, as soon as this asks it to. Calling it again changes nothing.
void press_return_on_dialogs() {
  if (lota_press_return_on_dialogs == nullptr) {
    throw std::runtime_error("liblota_dialogs is not loaded (LD_PRELOAD)");
  }
  lota_press_return_on_dialogs();
}

int dialogs_answered() { return lota_dialogs_answered == nullptr ? 0 : lota_dialogs_answered(); }

// SDL raises a window without activating it while
// SDL_WINDOW_ACTIVATE_WHEN_RAISED is off, as the tests set it
// (test/test_helper.rb), and otherwise asks the window manager to activate
// it (src/video/x11/SDL_x11window.c, X11_RaiseWindow and
// X11_SetWindowActive), so the hint is on for this one raise.
void activate() {
  SDL_Window *const window = first_window();
  if (window == nullptr) {
    return;
  }
  SDL_SetHintWithPriority(SDL_HINT_WINDOW_ACTIVATE_WHEN_RAISED, "1", SDL_HINT_OVERRIDE);
  SDL_RaiseWindow(window);
  SDL_ResetHint(SDL_HINT_WINDOW_ACTIVATE_WHEN_RAISED);
}

// Nothing to do: no dialog shows a window of this process's
// (press_return_on_dialogs), and X11 has no program to activate, only
// windows, which SDL's hints keep from activating when they are raised.
void stay_in_background() {}

// Gives keyboard focus up to whatever window the pointer is over, the
// X server's PointerRoot, since X11 keeps no program that had focus
// before activate to give it back to.
void give_up_focus() {
  SDL_Window *const window = first_window();
  if (window == nullptr) {
    return;
  }
  auto *const display = static_cast<Display *>(SDL_GetPointerProperty(
      SDL_GetWindowProperties(window), SDL_PROP_WINDOW_X11_DISPLAY_POINTER, nullptr));
  if (display == nullptr) {
    return;
  }
  XSetInputFocus(display, PointerRoot, RevertToPointerRoot, CurrentTime);
  XFlush(display);
}

} // namespace lota::native_test
