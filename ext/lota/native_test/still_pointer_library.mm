// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_still_pointer: still_pointer.mm's hold_pointer for a whole
// program, loaded into it with DYLD_INSERT_LIBRARIES, for a program that
// cannot load the test extension, such as lota run from the installed gem
// (tasks/package_check.rb).

#include "native_test/still_pointer.hpp"

#import <Foundation/Foundation.h>

namespace {

// Holds the pointer still from the first time the program's main thread
// handles its events. AppKit's event queue belongs to the main thread, and
// SDL creates the application object there, before it first pumps events
// (SDL 3.4.10, src/video/cocoa/SDL_cocoaevents.m, Cocoa_RegisterApp and
// Cocoa_PumpEventsUntilDate), whose run loop runs the main queue's blocks.
__attribute__((constructor)) void hold_from_the_start() {
  dispatch_async(dispatch_get_main_queue(), ^{
    lota::native_test::hold_pointer();
  });
}

} // namespace
