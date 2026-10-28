// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
// go on to SDL's own.

#include <SDL3/SDL_messagebox.h>
#include <SDL3/SDL_video.h>

#include <atomic>
#include <cstddef>
#include <span>

#include <dlfcn.h>

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

// SDL's own definition of +name+: the next after this library's
// (dlsym's RTLD_NEXT), which dlsym hands back as a void *.
template <typename Function> Function *sdl(const char *name) {
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
  return reinterpret_cast<Function *>(dlsym(RTLD_NEXT, name));
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
  if (!answering() || data == nullptr) {
    static auto *const show = sdl<decltype(SDL_ShowMessageBox)>("SDL_ShowMessageBox");
    return show != nullptr && show(data, button);
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
SDL_ShowSimpleMessageBox(SDL_MessageBoxFlags flags, const char *title, const char *message,
                         SDL_Window *window) {
  if (!answering()) {
    static auto *const show = sdl<decltype(SDL_ShowSimpleMessageBox)>("SDL_ShowSimpleMessageBox");
    return show != nullptr && show(flags, title, message, window);
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
