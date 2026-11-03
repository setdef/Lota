// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native_test/dialogs.hpp"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_video.h>
#include <atomic>
#include <memory>
#include <string>

namespace lota::native_test {

namespace {

// The number of dialogs press_return has pressed Return on.
std::atomic<int> &answered() {
  static std::atomic<int> count{0};
  return count;
}

// The button in +view+ that answers Return: the one whose key equivalent
// is Return, which SDL gives the button flagged
// SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT (SDL_cocoamessagebox.m), or nil.
// It looks through the views level by level, without recursion.
NSButton *return_button(NSView *view) {
  if (view == nil) {
    return nil;
  }
  NSMutableArray<NSView *> *const pending = [NSMutableArray arrayWithObject:view];
  while ([pending count] > 0) {
    NSView *const current = [pending firstObject];
    [pending removeObjectAtIndex:0];
    if ([current isKindOfClass:[NSButton class]] &&
        [[static_cast<NSButton *>(current) keyEquivalent] isEqualToString:@"\r"]) {
      return static_cast<NSButton *>(current);
    }
    [pending addObjectsFromArray:[current subviews]];
  }
  return nil;
}

// Presses Return on the dialog up, if one is. SDL shows its message box
// with NSAlert's runModal (SDL_ShowMessageBox, as LÖVE's
// Window::showMessageBox calls it in
// vendor/love/src/modules/window/sdl/Window.cpp), whose window is the
// application's modal window, and Return presses that window's default
// button (NSWindow's defaultButtonCell), which NSAlert makes its first.
// A dialog with buttons of its own makes none its window's default, and
// marks the button Return presses by its key equivalent instead. A dialog
// attached to a window of the program's is a sheet of that window, which
// is then the modal one (SDL3MessageBoxPresenter, SDL_cocoamessagebox.m).
void press_return(CFRunLoopTimerRef /*timer*/, void * /*info*/) {
  NSWindow *const modal = [NSApp modalWindow];
  NSWindow *const dialog = ([modal attachedSheet] != nil) ? [modal attachedSheet] : modal;
  NSButtonCell *const default_button = [dialog defaultButtonCell];
  if (default_button != nil) {
    [default_button performClick:nil];
    ++answered();
    return;
  }
  NSButton *const button = return_button([dialog contentView]);
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

// SDL clears a window's occluded flag only on its exposed event, which it
// sends when the system says the window's occlusion changed, and when the
// window's view redraws its layer, if the system says the window can be
// seen (SDL 3.4.10, src/video/cocoa/SDL_cocoawindow.m,
// windowDidChangeOcclusionState, updateLayer, and
// Cocoa_SendExposedEventIfVisible). After a minimize and a restore the
// system can leave the window in front without saying so again, and SDL
// would call it occluded for good; redrawing the view at once has SDL ask.
void reread_occlusion() {
  @autoreleasepool {
    NSWindow *const window = [[NSApp windows] firstObject];
    NSView *const view = [window contentView];
    [view setNeedsDisplay:YES];
    [view displayIfNeeded];
  }
}

// What the system says of each of the program's windows, in the order
// AppKit lists them, for a test to say why its window was not as it
// expected: its window number (the one CGWindowListCopyWindowInfo
// lists), whether it is SDL's first window, whether the system counts
// it as seen (occlusionState's NSWindowOcclusionStateVisible, the bit
// SDL reads, src/video/cocoa/SDL_cocoawindow.m), whether it is ordered
// in, key, main, on the active space, or minimized, its alpha, level,
// and frame, and the screen it is on; then whether the program is the
// active one, and its activation policy.
std::string window_state() {
  @autoreleasepool {
    int count = 0;
    const std::unique_ptr<SDL_Window *, void (*)(void *)> sdl_windows(SDL_GetWindows(&count),
                                                                      SDL_free);
    const void *const sdl_window =
        (sdl_windows && count > 0)
            ? SDL_GetPointerProperty(SDL_GetWindowProperties(*sdl_windows),
                                     SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, nullptr)
            : nullptr;
    NSMutableString *const state = [NSMutableString string];
    for (NSWindow *window in [NSApp windows]) {
      const NSRect frame = [window frame];
      [state appendFormat:@"window %ld%s: seen by macOS %s, ordered in %s, key %s, main %s, "
                          @"on the active space %s, minimized %s, alpha %.2f, level %ld, "
                          @"frame (%.0f, %.0f, %.0f, %.0f), screen %@; ",
                          static_cast<long>([window windowNumber]),
                          (static_cast<const void *>(window) == sdl_window) ? " (SDL's)" : "",
                          (([window occlusionState] & NSWindowOcclusionStateVisible) != 0) ? "yes"
                                                                                           : "no",
                          [window isVisible] ? "yes" : "no", [window isKeyWindow] ? "yes" : "no",
                          [window isMainWindow] ? "yes" : "no",
                          [window isOnActiveSpace] ? "yes" : "no",
                          [window isMiniaturized] ? "yes" : "no", [window alphaValue],
                          static_cast<long>([window level]), frame.origin.x, frame.origin.y,
                          frame.size.width, frame.size.height,
                          ([window screen] != nil) ? [[window screen] localizedName] : @"none"];
    }
    [state appendFormat:@"program active %s, activation policy %ld",
                        [NSApp isActive] ? "yes" : "no",
                        static_cast<long>([NSApp activationPolicy])];
    const char *const text = [state UTF8String];
    return (text != nullptr) ? std::string(text) : std::string();
  }
}

// SDL moves the pointer with CGWarpMouseCursorPosition, which sends no
// event, and tells itself of the move (SDL 3.4.10,
// src/video/cocoa/SDL_cocoamouse.m, Cocoa_WarpMouseGlobal); but the
// system then sends the window under the pointer mouse moved events of
// its own, some of them a while later, at where an earlier warp put the
// pointer, and SDL's mouseMoved (src/video/cocoa/SDL_cocoawindow.m) sets
// the position from each, so a pump after a second warp can leave the
// position at the first. A person moving the mouse over the window does
// the same. A window that ignores mouse events gets none of them, and SDL
// then knows the position only from its warps.
bool ignore_mouse_events(bool ignore) {
  @autoreleasepool {
    NSArray<NSWindow *> *const windows = [NSApp windows];
    for (NSWindow *window in windows) {
      [window setIgnoresMouseEvents:ignore ? YES : NO];
    }
    return [windows count] > 0;
  }
}

} // namespace lota::native_test
