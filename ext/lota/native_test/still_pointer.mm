// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native_test/still_pointer.hpp"

#import <AppKit/AppKit.h>

#include <sstream>
#include <string>

namespace lota::native_test {

namespace {

// The monitor hold_pointer installed, or nil.
id &monitor() {
  static id installed = nil;
  return installed;
}

// The movements of the mouse, which AppKit reports to the window under the
// pointer, or to the window with keyboard focus wherever the pointer is.
constexpr NSEventMask MOVEMENTS = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
                                  NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDragged |
                                  NSEventMaskMouseEntered | NSEventMaskMouseExited;

// How long move_mouse_as_a_person_would waits for AppKit's queue to hold
// the movement it posted, in seconds.
constexpr NSTimeInterval QUEUE_WAIT = 1.0;

// Waits until AppKit's queue holds a movement like +event+, to the same
// place in the same window, looking without taking it off the queue, for
// up to QUEUE_WAIT. Each look runs the run loop for a moment, as AppKit
// does when a program waits for its next event, so that whatever puts a
// posted event on the queue has the chance to. Whether it came.
bool wait_until_queued(NSEvent *event) {
  const NSTimeInterval start = [[NSProcessInfo processInfo] systemUptime];
  while ([[NSProcessInfo processInfo] systemUptime] - start <= QUEUE_WAIT) {
    NSEvent *const queued = [NSApp nextEventMatchingMask:NSEventMaskMouseMoved
                                               untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                                  inMode:NSDefaultRunLoopMode
                                                 dequeue:NO];
    if (queued != nil && [queued windowNumber] == [event windowNumber] &&
        NSEqualPoints([queued locationInWindow], [event locationInWindow])) {
      return true;
    }
  }
  return false;
}

} // namespace

// A local monitor sees each event AppKit takes from the program's queue
// before the program does, and the event is dropped when it answers nil.
// SDL reads the pointer's place from those events, in its window's
// mouseMoved: (SDL 3.4.10, src/video/cocoa/SDL_cocoawindow.m), whenever it
// pumps events, and love.mouse.setPosition pumps them right after it warps
// the pointer (vendor/love/src/modules/mouse/sdl/Mouse.cpp, setPosition):
// a movement queued before the warp, at the pointer's old place, or one
// made after it, would then be read back. A warp makes no event; SDL
// records its place itself (SDL_cocoamouse.m, Cocoa_WarpMouseGlobal), so
// dropping every movement leaves what the program set.
void hold_pointer() {
  if (monitor() != nil) {
    return;
  }
  monitor() = [[NSEvent addLocalMonitorForEventsMatchingMask:MOVEMENTS
                                                     handler:^NSEvent *(NSEvent *) {
                                                       return nil;
                                                     }] retain];
}

void release_pointer() {
  if (monitor() == nil) {
    return;
  }
  [NSEvent removeMonitor:monitor()];
  [monitor() release];
  monitor() = nil;
}

bool move_mouse_as_a_person_would(const void *window_pointer, double x, double y) {
  @autoreleasepool {
    auto *const window = (__bridge NSWindow *)window_pointer;
    if (window == nil) {
      return false;
    }
    const NSRect content = [window contentRectForFrameRect:[window frame]];
    NSEvent *const event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved
                                              location:NSMakePoint(x, content.size.height - y)
                                         modifierFlags:0
                                             timestamp:[[NSProcessInfo processInfo] systemUptime]
                                          windowNumber:[window windowNumber]
                                               context:nil
                                           eventNumber:0
                                            clickCount:0
                                              pressure:0];
    if (event == nil) {
      return false;
    }
    [NSApp postEvent:event atStart:NO];
    return wait_until_queued(event);
  }
}

std::string window_state(const void *window_pointer) {
  @autoreleasepool {
    auto *const window = (__bridge NSWindow *)window_pointer;
    if (window == nil) {
      return "no window";
    }
    std::ostringstream state;
    state << "application " << ([NSApp isActive] ? "active" : "inactive") << ", window "
          << ([window isVisible] ? "visible" : "not visible") << ", "
          << ([window isKeyWindow] ? "key" : "not key") << ", "
          << ((([window occlusionState] & NSWindowOcclusionStateVisible) != 0) ? "unoccluded"
                                                                               : "occluded")
          << ", accepting mouse moves " << ([window acceptsMouseMovedEvents] ? "yes" : "no");
    return state.str();
  }
}

} // namespace lota::native_test
