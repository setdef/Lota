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

// Keeps the program from becoming the active one. The tests start their
// programs with SDL's hints that keep a window from activating its program
// (SDL_MAC_BACKGROUND_APP, SDL_WINDOW_ACTIVATE_WHEN_SHOWN, and
// SDL_WINDOW_ACTIVATE_WHEN_RAISED, test/test_helper.rb), but AppKit
// activates a program that runs a modal dialog, as SDL's message box does
// (NSAlert's runModal, SDL 3.4.10, src/video/cocoa/SDL_cocoamessagebox.m),
// which would take keyboard focus from whatever the person at the computer
// is typing in. A program whose activation policy is prohibited is never
// activated, and still shows its windows and dialogs, so this sets it, as
// the parity harness's Lua side does in LÖVE (test/parity/lua/conf.lua).
// The program that was frontmost when activate took focus from it,
// retained, as this file is compiled without ARC.
NSRunningApplication *&previous() {
  static NSRunningApplication *application = nil;
  return application;
}

} // namespace

void stay_in_background() { [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited]; }

// A timer in AppKit's modal panel run loop mode, which runs only while a
// dialog is up, calls press_return every tenth of a second, so that a
// dialog such as LÖVE's version warning (boot.lua:378-393) does not wait
// for good. It works in the program's own process, as the key events the
// harness pushes into SDL's queue do, so it needs neither keyboard focus
// nor macOS's Accessibility permission, which System Events would need to
// press Return from another process. The parity harness's Lua side does
// the same through LuaJIT's FFI (test/parity/lua/conf.lua). It also keeps
// the program from becoming the active one (stay_in_background). Calling
// it again changes nothing.
void press_return_on_dialogs() {
  static const bool installed = [] {
    // SDL makes the application when it starts its video subsystem
    // (Cocoa_RegisterApp, src/video/cocoa/SDL_cocoaevents.m), which may come
    // after this, and tells it that it finished launching then.
    if (NSApp != nil) {
      stay_in_background();
    }
    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification * /*notification*/) {
                  stay_in_background();
                }];
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

// SDL grabs the mouse only for the window with keyboard focus (SDL
// 3.4.10, src/video/SDL_video.c, SDL_UpdateWindowGrab), and the tests'
// windows stay in the background (test/test_helper.rb), so a test of the
// grab gives its window focus first. A program SDL left out of the Dock
// (SDL_MAC_BACKGROUND_APP) must become a regular one to be activated, as
// SDL makes it otherwise (Cocoa_RegisterApp). activateIgnoringOtherApps is
// the call that takes focus from another program; its replacement,
// activate, waits for that program to yield.
void activate() {
  @autoreleasepool {
    NSRunningApplication *const front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (front != nil && ![front isEqual:[NSRunningApplication currentApplication]]) {
      [previous() release];
      previous() = [front retain];
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    NSWindow *const window = [[NSApp windows] firstObject];
    [window makeKeyAndOrderFront:nil];
  }
}

// Gives keyboard focus back to the program that had it before activate,
// as a person's click on it would, and keeps this program in the
// background from then on (stay_in_background), so that no click of the
// person at the computer gives one of its windows focus again. NSApp's
// deactivate would hand focus to whichever program macOS picks, such as
// the Finder, rather than the one the person was using.
void give_up_focus() {
  @autoreleasepool {
    NSRunningApplication *const front = previous();
    previous() = nil;
    if (front != nil) {
      [front activateWithOptions:0];
      [front release];
    } else {
      [NSApp deactivate];
    }
    stay_in_background();
  }
}

} // namespace lota::native_test
