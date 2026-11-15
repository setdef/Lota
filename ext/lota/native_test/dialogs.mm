// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native_test/dialogs.hpp"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

#include <SDL3/SDL_messagebox.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_video.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <iterator>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/kern_return.h>
#include <mach/mach_init.h>
#include <mach/vm_map.h>
#include <mach/vm_prot.h>
#include <mach/vm_types.h>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>

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

// What a dialog says.
struct Said {
  const char *title;
  const char *message;
};

// Writes what a refused dialog +said+ to standard error, as
// liblota_dialogs does on Linux (answer_dialogs_linux.cpp).
void say_refused(const Said &said) {
  std::string line = "lota_dialogs: refused a message box (no one can answer it): ";
  line += said.title != nullptr ? said.title : "";
  line += ": ";
  line += said.message != nullptr ? said.message : "";
  line += '\n';
  std::fputs(line.c_str(), stderr);
  std::fflush(stderr);
}

// SDL_ShowMessageBox, refused until press_return_on_dialogs is called, and
// SDL's own from then on, with the button pressed for it. This image's
// own calls to SDL are never rebound (rebind), so the call by name here
// reaches SDL's.
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
  say_refused({.title = data->title, .message = data->message});
  return false;
}

// SDL_ShowSimpleMessageBox, as message_box.
bool simple_message_box(SDL_MessageBoxFlags flags, const char *title, const char *message,
                        SDL_Window *window) {
  if (answering()) {
    return SDL_ShowSimpleMessageBox(flags, title, message, window);
  }
  say_refused({.title = title, .message = message});
  return false;
}

// The bytes of a function pointer, as an image keeps one in a slot.
using Pointer = std::array<std::byte, sizeof(void *)>;

// A function an image imports, by its Mach-O symbol name, and the bytes
// of the pointer that go into the image's slot for it instead.
struct Rebinding {
  const char *symbol;
  Pointer replacement;
};

const std::array<Rebinding, 2> &rebindings() {
  static const std::array all{
      Rebinding{
          .symbol = "_SDL_ShowMessageBox",
          .replacement = std::bit_cast<Pointer>(&message_box),
      },
      Rebinding{
          .symbol = "_SDL_ShowSimpleMessageBox",
          .replacement = std::bit_cast<Pointer>(&simple_message_box),
      },
  };
  return all;
}

// The start of this extension's own image, whose calls rebind leaves to
// SDL, so that message_box and simple_message_box reach SDL's functions
// by name once dialogs are to be answered.
const void *own_image() {
  static const void *const start = [] {
    Dl_info info{};
    return (dladdr(&rebindings(), &info) != 0) ? info.dli_fbase : nullptr;
  }();
  return start;
}

// The T at +offset+ in +bytes+, copied out, or nothing when +bytes+ ends
// before it. An image's Mach-O structures sit at the offsets its load
// commands give, where no C++ object was made, so each is read by copying
// its bytes.
template <typename T>
std::optional<T> copy_of(std::span<const std::byte> bytes, std::size_t offset = 0) {
  if (offset > bytes.size() || bytes.size() - offset < sizeof(T)) {
    return std::nullopt;
  }
  T value{};
  std::memcpy(&value, bytes.subspan(offset, sizeof(T)).data(), sizeof(T));
  return value;
}

// The bytes +length+ long at file offset +offset+ in an image's
// __LINKEDIT segment, whose bytes are +segment+ and whose own file offset
// is +start+, or none when they are not all in it.
std::span<const std::byte> linked(std::span<const std::byte> segment, std::uint64_t start,
                                  std::uint64_t offset, std::uint64_t length) {
  if (offset < start || offset - start > segment.size() ||
      segment.size() - (offset - start) < length) {
    return {};
  }
  return segment.subspan(offset - start, length);
}

// A segment's or a section's name, which fills its 16 characters with no
// terminating NUL when it is that long (mach-o/loader.h).
template <typename Name> std::string_view name_of(const Name &name) {
  const std::string_view field(std::data(name), std::size(name));
  return field.substr(0, field.find('\0'));
}

// Whether the string table's +names+, from a symbol's name on, hold
// +symbol+ and its terminating NUL.
bool names(std::span<const std::byte> names, const char *symbol) {
  const std::size_t length = std::strlen(symbol) + 1;
  return names.size() >= length && std::memcmp(names.data(), symbol, length) == 0;
}

// An image's load commands, after its header, and how many there are.
struct Commands {
  std::span<const std::byte> bytes;
  std::uint32_t count;
};

// Calls +visit+ with the kind of each of +commands+ and its bytes on.
template <typename Visit> void each_command(const Commands &commands, Visit visit) {
  std::size_t offset = 0;
  for (std::uint32_t i = 0; i < commands.count; ++i) {
    const std::optional<load_command> command = copy_of<load_command>(commands.bytes, offset);
    if (!command || command->cmdsize < sizeof(load_command)) {
      return;
    }
    visit(command->cmd, commands.bytes.subspan(offset));
    offset += command->cmdsize;
  }
}

// An image's symbols (nlist_64), their names, and its indirect symbol
// table, whose entries name the symbol of each pointer an image calls an
// imported function through.
struct Tables {
  std::span<const std::byte> symbols;
  std::span<const std::byte> names;
  std::span<const std::byte> indirect;
};

// The symbol tables of the image +header+, whose load commands are
// +commands+, in its __LINKEDIT segment, or nothing when it has none.
std::optional<Tables> tables_of(const mach_header_64 *header, const Commands &commands) {
  std::optional<segment_command_64> linkedit;
  std::optional<symtab_command> symtab;
  std::optional<dysymtab_command> dysymtab;
  each_command(commands, [&](std::uint32_t kind, std::span<const std::byte> bytes) {
    if (kind == LC_SEGMENT_64) {
      const std::optional<segment_command_64> segment = copy_of<segment_command_64>(bytes);
      if (segment && name_of(segment->segname) == SEG_LINKEDIT) {
        linkedit = segment;
      }
    } else if (kind == LC_SYMTAB) {
      symtab = copy_of<symtab_command>(bytes);
    } else if (kind == LC_DYSYMTAB) {
      dysymtab = copy_of<dysymtab_command>(bytes);
    }
  });
  if (!linkedit || !symtab || !dysymtab || dysymtab->nindirectsyms == 0) {
    return std::nullopt;
  }
  unsigned long size = 0;
  const std::span<const std::byte> segment =
      std::as_bytes(std::span(getsegmentdata(header, SEG_LINKEDIT, &size), size));
  const std::uint64_t start = linkedit->fileoff;
  return Tables{
      .symbols = linked(segment, start, symtab->symoff,
                        static_cast<std::uint64_t>(symtab->nsyms) * sizeof(nlist_64)),
      .names = linked(segment, start, symtab->stroff, symtab->strsize),
      .indirect =
          linked(segment, start, dysymtab->indirectsymoff,
                 static_cast<std::uint64_t>(dysymtab->nindirectsyms) * sizeof(std::uint32_t)),
  };
}

// The rebinding for the pointer the indirect symbol table's entry +entry+
// names, or nullptr when it names none of SDL's two functions. A symbol's
// name is its n_strx, an offset into the string table, the first field
// of an nlist_64 (mach-o/nlist.h), which keeps it in a union of that one
// member, read here at its offset.
const Rebinding *rebinding_for(const Tables &tables, std::uint64_t entry) {
  const std::optional<std::uint32_t> index =
      copy_of<std::uint32_t>(tables.indirect, entry * sizeof(std::uint32_t));
  if (!index || (*index & (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) != 0) {
    return nullptr;
  }
  const std::optional<std::uint32_t> name =
      copy_of<std::uint32_t>(tables.symbols, (static_cast<std::size_t>(*index) * sizeof(nlist_64)) +
                                                 offsetof(nlist_64, n_un));
  if (!name || *name >= tables.names.size()) {
    return nullptr;
  }
  for (const Rebinding &rebinding : rebindings()) {
    if (names(tables.names.subspan(*name), rebinding.symbol)) {
      return &rebinding;
    }
  }
  return nullptr;
}

// Sets the protection of the page or pages that hold +bytes+, which the
// kernel rounds out to whole pages.
bool protect(std::span<std::byte> bytes, vm_prot_t protection) {
  return vm_protect(mach_task_self(), std::bit_cast<vm_address_t>(bytes.data()), bytes.size(), 0,
                    protection) == KERN_SUCCESS;
}

// Writes the pointer +replacement+ into +slot+, in a segment that dyld
// made read-only once it bound it (__DATA_CONST), or in a writable one.
void write_slot(std::span<std::byte, sizeof(void *)> slot, const Pointer &replacement,
                bool read_only) {
  if (read_only && !protect(slot, VM_PROT_READ | VM_PROT_WRITE)) {
    return;
  }
  std::ranges::copy(replacement, slot.begin());
  if (read_only) {
    protect(slot, VM_PROT_READ);
  }
}

// Points each of +section+'s symbol pointers that names one of SDL's two
// functions at its replacement.
void rebind_section(const mach_header_64 *header, const section_64 &section, const Tables &tables) {
  unsigned long size = 0;
  const std::span<std::byte> slots = std::as_writable_bytes(std::span(
      getsectiondata(header, std::data(section.segname), std::data(section.sectname), &size),
      size));
  const bool read_only = name_of(section.segname) == "__DATA_CONST";
  for (std::size_t n = 0; n < slots.size() / sizeof(void *); ++n) {
    const Rebinding *const rebinding = rebinding_for(tables, section.reserved1 + n);
    if (rebinding != nullptr) {
      write_slot(slots.subspan(n * sizeof(void *)).first<sizeof(void *)>(), rebinding->replacement,
                 read_only);
    }
  }
}

// Rebinds the sections of symbol pointers in the segment whose load
// command starts +command+.
void rebind_segment(const mach_header_64 *header, std::span<const std::byte> command,
                    const Tables &tables) {
  const std::optional<segment_command_64> segment = copy_of<segment_command_64>(command);
  if (!segment) {
    return;
  }
  for (std::uint32_t s = 0; s < segment->nsects; ++s) {
    const std::optional<section_64> section =
        copy_of<section_64>(command, sizeof(segment_command_64) + (s * sizeof(section_64)));
    if (!section) {
      return;
    }
    const std::uint32_t type = section->flags & SECTION_TYPE;
    if (type == S_NON_LAZY_SYMBOL_POINTERS || type == S_LAZY_SYMBOL_POINTERS) {
      rebind_section(header, *section, tables);
    }
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
// alone, and so is this extension's own. dyld calls this for each image
// as it loads, and at once for each already loaded
// (_dyld_register_func_for_add_image), so the order in which a process
// loads Lota and this extension does not matter. getsectiondata and
// getsegmentdata find where the image's sections and segments were
// loaded, slide included, and dladdr gives the image's start, its header,
// as the untyped pointer it is.
void rebind(const mach_header *image, std::intptr_t /*slide*/) {
  if (image->magic != MH_MAGIC_64 || (image->flags & MH_DYLIB_IN_CACHE) != 0 ||
      image == own_image()) {
    return;
  }
  Dl_info info{};
  if (dladdr(image, &info) == 0 || info.dli_fbase != image) {
    return;
  }
  const auto *const header = static_cast<const mach_header_64 *>(info.dli_fbase);
  const Commands commands{
      .bytes = std::span(static_cast<const std::byte *>(info.dli_fbase),
                         sizeof(mach_header_64) + header->sizeofcmds)
                   .subspan(sizeof(mach_header_64)),
      .count = header->ncmds,
  };
  const std::optional<Tables> tables = tables_of(header, commands);
  if (!tables) {
    return;
  }
  each_command(commands, [&](std::uint32_t kind, std::span<const std::byte> bytes) {
    if (kind == LC_SEGMENT_64) {
      rebind_segment(header, bytes, *tables);
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
