// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native_test/selections.hpp"

#include <X11/X.h>
#include <X11/Xlib.h>
// struct _XDisplay, the Display that foreign reads the resource range of.
#include <X11/Xlibint.h> // IWYU pragma: keep
#include <X11/Xproto.h>

namespace lota::native_test {

namespace {

// The handler Xlib had before tolerate_vanished_requestors, which handles
// every other error: Xlib's default, which prints it and ends the program.
XErrorHandler &previous() {
  static XErrorHandler handler = nullptr;
  return handler;
}

// Whether +error+ is about a window of another program's: one whose
// resource ID is not from the range the X server gave this connection,
// which Xlib keeps in its Display (Xlibint.h, struct _XDisplay's
// resource_base and resource_mask).
bool foreign(const Display *display, const XErrorEvent &error) {
  return (error.resourceid & ~display->resource_mask) != display->resource_base;
}

// Lets BadWindow pass when SDL answered another program's request for the
// clipboard after that program's window was gone, and hands every other
// error to the handler before it, through Xlib's XErrorHandler, which
// takes both as pointers to non-const (Xlib.h).
// NOLINTNEXTLINE(misc-const-correctness)
int handle(Display *display, XErrorEvent *error) {
  const bool answer = error->request_code == X_ChangeProperty || error->request_code == X_SendEvent;
  if (error->error_code == BadWindow && answer && foreign(display, *error)) {
    return 0;
  }
  return previous() != nullptr ? previous()(display, error) : 0;
}

} // namespace

// SDL answers another program's request for the clipboard this program
// owns by writing to that program's window and telling it so (SDL
// 3.4.10, src/video/x11/SDL_x11events.c, X11_HandleClipboardEvent,
// XChangeProperty and XSendEvent), without guarding against the window
// having gone. Every SDL program on a display asks the owner for what
// the clipboard holds whenever another takes it (X11_DispatchEvent, on
// XFixesSetSelectionOwnerNotify), so when the tests, which copy to the
// clipboard (Lövetest's love.system.setClipboardText, and the error
// screen's Ctrl+C), share one display with the games they start, a game
// can ask and exit before this program answers, and the answer's
// BadWindow, under Xlib's default handler, would end the test run.
// LÖVE's own tests run as one program and never meet it. Errors about
// this program's own windows still end it. Calling it again changes
// nothing.
void tolerate_vanished_requestors() {
  static const bool installed = [] {
    previous() = XSetErrorHandler(&handle);
    return true;
  }();
  static_cast<void>(installed);
}

bool request_clipboard_and_vanish() {
  Display *const display = XOpenDisplay(nullptr);
  if (display == nullptr) {
    return false;
  }
  const Window window =
      XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 1, 1, 0, 0, 0);
  XConvertSelection(display, XInternAtom(display, "CLIPBOARD", False),
                    XInternAtom(display, "TARGETS", False),
                    XInternAtom(display, "LOTA_VANISHED", False), window, CurrentTime);
  XSync(display, False);
  XCloseDisplay(display);
  return true;
}

} // namespace lota::native_test
