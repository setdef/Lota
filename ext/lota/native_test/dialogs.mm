// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native_test/dialogs.hpp"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

#include <SDL3/SDL_messagebox.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_video.h>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <memory>
#include <string>
#include <sys/mman.h>
#include <unistd.h>

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

// Whether press_return_on_dialogs has been called, after which dialogs go
// on to SDL rather than being refused.
std::atomic<bool> &answering() {
  static std::atomic<bool> on{false};
  return on;
}

// Whether refuse_dialogs has been called.
std::atomic<bool> &refusing() {
  static std::atomic<bool> on{false};
  return on;
}

// Writes what a refused dialog said to standard error, as liblota_dialogs
// does on Linux (answer_dialogs_linux.cpp).
void say_refused(const char *title, const char *message) {
  std::fprintf(stderr, "lota_dialogs: refused a message box (no one can answer it): %s: %s\n",
               title != nullptr ? title : "", message != nullptr ? message : "");
  std::fflush(stderr);
}

// SDL's own function +name+, as SDL exports it, which no rebinding
// reaches.
template <typename Function> Function *sdl_function(const char *name) {
  return reinterpret_cast<Function *>(dlsym(RTLD_DEFAULT, name));
}

// SDL_ShowMessageBox, refused until press_return_on_dialogs is called, and
// SDL's own from then on, with the button pressed for it.
bool message_box(const SDL_MessageBoxData *data, int *button) {
  if (answering()) {
    static auto *const original = sdl_function<decltype(SDL_ShowMessageBox)>("SDL_ShowMessageBox");
    return original != nullptr && original(data, button);
  }
  if (data == nullptr) {
    return false;
  }
  if (button != nullptr) {
    *button = -1;
  }
  say_refused(data->title, data->message);
  return false;
}

// SDL_ShowSimpleMessageBox, as message_box.
bool simple_message_box(SDL_MessageBoxFlags flags, const char *title, const char *message,
                        SDL_Window *window) {
  if (answering()) {
    static auto *const original =
        sdl_function<decltype(SDL_ShowSimpleMessageBox)>("SDL_ShowSimpleMessageBox");
    return original != nullptr && original(flags, title, message, window);
  }
  say_refused(title, message);
  return false;
}

// A function an image imports, by its Mach-O symbol name, and where its
// calls go instead.
struct Rebinding {
  const char *symbol;
  void *replacement;
};

const std::array<Rebinding, 2> &rebindings() {
  static const std::array<Rebinding, 2> all{{
      {.symbol = "_SDL_ShowMessageBox", .replacement = reinterpret_cast<void *>(&message_box)},
      {.symbol = "_SDL_ShowSimpleMessageBox",
       .replacement = reinterpret_cast<void *>(&simple_message_box)},
  }};
  return all;
}

// Writes +value+ into the pointer +slot+, in a segment that dyld made
// read-only once it bound it (__DATA_CONST), or in a writable one.
void write_slot(void **slot, void *value, bool read_only) {
  if (!read_only) {
    *slot = value;
    return;
  }
  const auto page_size = static_cast<std::uintptr_t>(getpagesize());
  auto *const page =
      reinterpret_cast<void *>(reinterpret_cast<std::uintptr_t>(slot) & ~(page_size - 1));
  if (mprotect(page, page_size, PROT_READ | PROT_WRITE) != 0) {
    return;
  }
  *slot = value;
  mprotect(page, page_size, PROT_READ);
}

// Calls +visit+ with each load command of the image +header+.
template <typename Visit> void each_command(const mach_header_64 *header, Visit visit) {
  const auto *command = reinterpret_cast<const load_command *>(header + 1);
  for (std::uint32_t i = 0; i < header->ncmds; ++i) {
    visit(command);
    command = reinterpret_cast<const load_command *>(reinterpret_cast<const char *>(command) +
                                                     command->cmdsize);
  }
}

// Points the image's imports of SDL's message box functions at
// message_box and simple_message_box. An image calls a function it
// imports through a pointer dyld binds, in a section of symbol pointers
// whose entries the image's indirect symbol table names
// (mach-o/loader.h, S_NON_LAZY_SYMBOL_POINTERS and
// S_LAZY_SYMBOL_POINTERS), so rewriting that pointer changes where the
// image's calls go and nothing else. No code is written, which macOS
// refuses in a signed image, and SDL's export stays SDL's. The system's
// images, in the shared cache, import nothing of SDL's and are left
// alone. dyld calls this for each image as it loads, and at once for each
// already loaded (_dyld_register_func_for_add_image), so the order in
// which a process loads Lota and this extension does not matter.
void rebind(const mach_header *mach, intptr_t slide) {
  if (mach->magic != MH_MAGIC_64 || (mach->flags & MH_DYLIB_IN_CACHE) != 0) {
    return;
  }
  const auto *header = reinterpret_cast<const mach_header_64 *>(mach);
  const segment_command_64 *linkedit = nullptr;
  const symtab_command *symtab = nullptr;
  const dysymtab_command *dysymtab = nullptr;
  each_command(header, [&](const load_command *command) {
    if (command->cmd == LC_SEGMENT_64) {
      const auto *segment = reinterpret_cast<const segment_command_64 *>(command);
      if (std::strcmp(segment->segname, SEG_LINKEDIT) == 0) {
        linkedit = segment;
      }
    } else if (command->cmd == LC_SYMTAB) {
      symtab = reinterpret_cast<const symtab_command *>(command);
    } else if (command->cmd == LC_DYSYMTAB) {
      dysymtab = reinterpret_cast<const dysymtab_command *>(command);
    }
  });
  if (linkedit == nullptr || symtab == nullptr || dysymtab == nullptr ||
      dysymtab->nindirectsyms == 0) {
    return;
  }
  const std::uintptr_t base =
      static_cast<std::uintptr_t>(slide) + linkedit->vmaddr - linkedit->fileoff;
  const auto *symbols = reinterpret_cast<const nlist_64 *>(base + symtab->symoff);
  const auto *names = reinterpret_cast<const char *>(base + symtab->stroff);
  const auto *indirect = reinterpret_cast<const std::uint32_t *>(base + dysymtab->indirectsymoff);
  each_command(header, [&](const load_command *command) {
    if (command->cmd != LC_SEGMENT_64) {
      return;
    }
    const auto *segment = reinterpret_cast<const segment_command_64 *>(command);
    const bool read_only = std::strcmp(segment->segname, "__DATA_CONST") == 0;
    const auto *sections = reinterpret_cast<const section_64 *>(segment + 1);
    for (std::uint32_t s = 0; s < segment->nsects; ++s) {
      const section_64 &section = sections[s];
      const std::uint32_t type = section.flags & SECTION_TYPE;
      if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) {
        continue;
      }
      auto **slots = reinterpret_cast<void **>(static_cast<std::uintptr_t>(slide) + section.addr);
      for (std::uint64_t n = 0; n < section.size / sizeof(void *); ++n) {
        const std::uint32_t index = indirect[section.reserved1 + n];
        if ((index & (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) != 0 ||
            index >= symtab->nsyms) {
          continue;
        }
        const char *const name = names + symbols[index].n_un.n_strx;
        for (const Rebinding &rebinding : rebindings()) {
          if (std::strcmp(name, rebinding.symbol) == 0) {
            write_slot(&slots[n], rebinding.replacement, read_only);
          }
        }
      }
    }
  });
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

// SDL shows a dialog with NSAlert's runModal (SDL 3.4.10,
// src/video/cocoa/SDL_cocoamessagebox.m), which waits for a button no one
// in an unattended run can press, so a test whose game fails to start
// would hold the run until its timeout. The calls the images of this
// process make to SDL's two message box functions go to message_box and
// simple_message_box instead (rebind), which refuse them until
// press_return_on_dialogs. Only a process that loads the test extension
// is changed, never another program a test starts.
void refuse_dialogs() {
  static const bool installed = [] {
    _dyld_register_func_for_add_image(&rebind);
    return true;
  }();
  static_cast<void>(installed);
  refusing() = true;
}

bool refusing_dialogs() { return refusing() && !answering(); }

void stay_in_background() { [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited]; }

// A timer in AppKit's modal panel run loop mode, which runs only while a
// dialog is up, calls press_return every tenth of a second, so that a
// dialog such as LÖVE's version warning (boot.lua:378-393) does not wait
// for good. It works in the program's own process, as the key events the
// harness pushes into SDL's queue do, so it needs neither keyboard focus
// nor macOS's Accessibility permission, which System Events would need to
// press Return from another process. The parity harness's Lua side does
// the same through LuaJIT's FFI (test/parity/lua/conf.lua). It also keeps
// the program from becoming the active one (stay_in_background), and lets
// the dialogs refuse_dialogs refuses go on to SDL. Calling it again
// changes nothing.
void press_return_on_dialogs() {
  answering() = true;
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
