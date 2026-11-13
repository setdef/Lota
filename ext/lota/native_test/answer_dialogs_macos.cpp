// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_dialogs on macOS (native_test/CMakeLists.txt): the dialogs a
// program shows are refused, unless the program has asked for them to be
// answered. The tests and the parity harness load it into the reference
// love and into Lota with DYLD_INSERT_LIBRARIES, and dyld sends the calls
// every other image makes to SDL_ShowMessageBox and SDL_ShowSimpleMessageBox
// to these (its __interpose section), which LÖVE's Window::showMessageBox
// calls (vendor/love/src/modules/window/sdl/Window.cpp:1449-1492).
//
// SDL shows a dialog with NSAlert's runModal (SDL 3.4.10,
// src/video/cocoa/SDL_cocoamessagebox.m), which waits for a button no one
// in an unattended run can press, so a test whose game fails to start would
// hold the run until its timeout. A dialog the harness asked to answer
// (lota_press_return_on_dialogs, which the test extension and the harness's
// Lua call when they install the timer that presses its default button,
// dialogs.mm and test/parity/lua/conf.lua) goes on to SDL's own; any other
// is written, with its title and message, to standard error, and fails as
// SDL fails when it can show none.

#include <SDL3/SDL_messagebox.h>
#include <SDL3/SDL_video.h>

#include <atomic>
#include <cstdio>
#include <string>

namespace {

// Whether lota_press_return_on_dialogs has been called.
std::atomic<bool> &answering() {
  static std::atomic<bool> on{false};
  return on;
}

// What a dialog says.
struct Said {
  const char *title;
  const char *message;
};

// Fails the call of a dialog nobody can answer, after writing what it
// +said+ to standard error.
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

// SDL_ShowMessageBox, interposed. dyld interposes calls from every image
// but this one, so this library reaches SDL's own by name.
bool message_box(const SDL_MessageBoxData *data, int *button) {
  if (answering()) {
    return SDL_ShowMessageBox(data, button);
  }
  if (data == nullptr) {
    return false;
  }
  if (button != nullptr) {
    *button = -1;
  }
  return refuse({.title = data->title, .message = data->message});
}

// SDL_ShowSimpleMessageBox, interposed.
bool simple_message_box(SDL_MessageBoxFlags flags, const char *title, const char *message,
                        SDL_Window *window) {
  if (answering()) {
    return SDL_ShowSimpleMessageBox(flags, title, message, window);
  }
  return refuse({.title = title, .message = message});
}

// One of dyld's interpose tuples (mach-o/dyld-interposing.h): where calls
// to the second function go instead.
template <typename Function> struct Interpose {
  Function *replacement;
  Function *replacee;
};

[[gnu::used,
  gnu::section("__DATA,__interpose")]] const Interpose<decltype(SDL_ShowMessageBox)> interpose_box{
    .replacement = &message_box,
    .replacee = &SDL_ShowMessageBox,
};
[[gnu::used,
  gnu::section(
      "__DATA,__interpose")]] const Interpose<decltype(SDL_ShowSimpleMessageBox)> interpose_simple{
    .replacement = &simple_message_box,
    .replacee = &SDL_ShowSimpleMessageBox,
};

} // namespace

// Lets every dialog from now on go on to SDL, whose NSAlert the caller's
// timer presses a button on. The harness calls it through LuaJIT's FFI in
// LÖVE (test/parity/lua/conf.lua) and dialogs.mm calls it for Lota.
extern "C" __attribute__((visibility("default"))) void lota_press_return_on_dialogs() {
  answering() = true;
}
