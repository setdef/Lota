// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native_test/dialogs.hpp"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

#include <atomic>

namespace lota::native_test {

namespace {

// The number of dialogs press_return has pressed Return on.
std::atomic<int> &answered() {
  static std::atomic<int> count{0};
  return count;
}

// Presses Return on the dialog up, if one is. SDL shows its message box
// with NSAlert's runModal (SDL_ShowMessageBox, as LÖVE's
// Window::showMessageBox calls it in
// vendor/love/src/modules/window/sdl/Window.cpp), whose window is the
// application's modal window, and Return presses that window's default
// button (NSWindow's defaultButtonCell), which NSAlert makes its first.
void press_return(CFRunLoopTimerRef /*timer*/, void * /*info*/) {
  NSWindow *const dialog = [NSApp modalWindow];
  NSButtonCell *const button = [dialog defaultButtonCell];
  if (button == nil) {
    return;
  }
  [button performClick:nil];
  ++answered();
}

} // namespace

// A timer in AppKit's modal panel run loop mode, which runs only while a
// dialog is up, calls press_return every tenth of a second, so that a
// dialog such as LÖVE's version warning (boot.lua:378-393) does not wait
// for good. It works in the program's own process, as the key events the
// harness pushes into SDL's queue do, so it needs neither keyboard focus
// nor macOS's Accessibility permission, which System Events would need to
// press Return from another process. The parity harness's Lua side does
// the same through LuaJIT's FFI (test/parity/lua/conf.lua). Calling it
// again changes nothing.
void press_return_on_dialogs() {
  static const bool installed = [] {
    constexpr CFTimeInterval interval = 0.1;
    CFRunLoopTimerRef timer =
        CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval,
                             0, 0, &press_return, nullptr);
    // The run loop keeps the timer, which lasts as long as the program.
    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, static_cast<CFStringRef>(NSModalPanelRunLoopMode));
    CFRelease(timer);
    return true;
  }();
  static_cast<void>(installed);
}

int dialogs_answered() { return answered().load(); }

} // namespace lota::native_test
