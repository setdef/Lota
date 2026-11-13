// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_dialogs: Return pressed on every dialog a program shows, on
// Linux (native_test/CMakeLists.txt). The tests and the parity harness
// load it into the reference love and into Lota with LD_PRELOAD, which
// puts its SDL_ShowMessageBox and SDL_ShowSimpleMessageBox ahead of SDL's,
// so LÖVE's Window::showMessageBox (vendor/love/src/modules/window/sdl/
// Window.cpp:1449-1492), which calls one or the other, reaches these.
//
// On macOS the harness presses the dialog's default button through AppKit
// from inside the program's own process (dialogs.mm). On Linux SDL shows a
// dialog with zenity, a program of its own, when zenity is installed, and
// otherwise in a window of its own X11 toolkit, which runs its own event
// loop on a connection of its own to the X server (SDL 3.4.10,
// src/video/x11/SDL_x11messagebox.c), so nothing in this process can find
// the dialog to press a key on it. Instead, once lota_press_return_on_dialogs
// is called, each dialog is answered as Return answers it, without being
// shown: SDL's toolkit selects the button flagged
// SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, and Return presses the button
// selected (src/video/x11/SDL_x11toolkit.c, X11Toolkit_CreateButtonControl
// and X11Toolkit_ProcessWindowEvents), whose ID SDL_ShowMessageBox then
// returns. Until then, and for a call without a dialog to answer, the calls
// are refused: a dialog a test shows has no one to press its button, and
// SDL's zenity or X11 window waits for that as long as the run lasts. A
// refused call writes the dialog's title and message to standard error,
// and fails as SDL does when it can show no dialog, so the program goes on
// with the error it would have shown.

#include <SDL3/SDL_messagebox.h>
#include <SDL3/SDL_video.h>

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <span>
#include <string>

namespace {

// Whether lota_press_return_on_dialogs has been called.
std::atomic<bool> &answering() {
  static std::atomic<bool> on{false};
  return on;
}

// The number of dialogs answered.
std::atomic<int> &answered() {
  static std::atomic<int> count{0};
  return count;
}

// What a dialog says.
struct Said {
  const char *title;
  const char *message;
};

// Fails the call of a dialog nobody can answer, after writing what it
// +said+ to standard error, as SDL fails when it can show no dialog.
bool refuse(const Said &said) {
  std::string line = "lota_dialogs: refused a message box (no one can answer it): ";
  line += said.title != nullptr ? said.title : "";
  line += ": ";
  line += said.message != nullptr ? said.message : "";
  line += '\n';
  std::fputs(line.c_str(), stderr);
  std::fflush(stderr);
  return false;
}

// The ID of the button Return presses on +data+'s dialog, or -1, the ID
// SDL gives a dialog closed without a button, when no button is flagged
// for Return, as Return then presses none.
int return_button(const SDL_MessageBoxData &data) {
  if (data.buttons == nullptr || data.numbuttons <= 0) {
    return -1;
  }
  for (const SDL_MessageBoxButtonData &button :
       std::span(data.buttons, static_cast<std::size_t>(data.numbuttons))) {
    if ((button.flags & SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT) != 0) {
      return button.buttonID;
    }
  }
  return -1;
}

} // namespace

// SDL_ShowMessageBox, answered with the button Return presses.
extern "C" __attribute__((visibility("default"))) bool
SDL_ShowMessageBox(const SDL_MessageBoxData *data, int *button) {
  if (data == nullptr) {
    return false;
  }
  if (!answering()) {
    if (button != nullptr) {
      *button = -1;
    }
    return refuse({.title = data->title, .message = data->message});
  }
  if (button != nullptr) {
    *button = return_button(*data);
  }
  ++answered();
  return true;
}

// SDL_ShowSimpleMessageBox, answered: its one button, OK, is flagged for
// Return (src/video/SDL_video.c, SDL_ShowSimpleMessageBox), so Return
// presses it, and the call succeeds.
extern "C" __attribute__((visibility("default"))) bool
SDL_ShowSimpleMessageBox(SDL_MessageBoxFlags /*flags*/, const char *title, const char *message,
                         SDL_Window * /*window*/) {
  if (!answering()) {
    return refuse({.title = title, .message = message});
  }
  ++answered();
  return true;
}

// Answers every dialog from now on. The harness calls it through LuaJIT's
// FFI in LÖVE (test/parity/lua/conf.lua) and through
// LotaNativeTest.press_return_on_dialogs in Lota (dialogs_linux.cpp).
extern "C" __attribute__((visibility("default"))) void lota_press_return_on_dialogs() {
  answering() = true;
}

// How many dialogs have been answered.
extern "C" __attribute__((visibility("default"))) int lota_dialogs_answered() {
  return answered().load();
}
