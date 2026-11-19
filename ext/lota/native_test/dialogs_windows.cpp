// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Return pressed on the dialogs a program shows, and keyboard focus for
// the one test that needs it, on Windows (dialogs.hpp; dialogs.mm is
// macOS's, dialogs_linux.cpp Linux's).
//
// SDL is linked into each extension on Windows (tasks/windows_build.rb),
// so this bundle's SDL is not the one that opened Lota's windows, and
// knows none of them. What follows asks Windows itself, for the windows of
// this process that SDL registered with its class, SDL_app (SDL 3.4.10,
// src/video/windows/SDL_windowswindow.c, SDL_Appname).

#include "native_test/dialogs.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <span>
#include <string>
#include <vector>

#include <SDL3/SDL_messagebox.h>
#include <SDL3/SDL_video.h>
#include <windows.h>

namespace lota::native_test {

namespace {

// The number of dialogs Return was pressed on.
std::atomic<int> &answered() {
  static std::atomic<int> count{0};
  return count;
}

// The hook that watches for this thread's dialogs, once set.
HHOOK &dialog_hook() {
  static HHOOK hook = nullptr;
  return hook;
}

// The bytes of a function pointer, as a jump carries the address it goes
// to.
using Pointer = std::array<unsigned char, sizeof(void *)>;

// The instructions of a jump to a refusal, which replaces a function's
// start, before and after the refusal's address. On x64, a move of the
// address into rax (REX.W B8) and a jump to it (FF E0); on ARM64, a load
// of the address that follows into x16 (ldr x16, #8) and a branch to it
// (br x16), each a little-endian word.
#ifdef __aarch64__
constexpr std::array<unsigned char, 8> jump_start = {0x50, 0x00, 0x00, 0x58,
                                                     0x00, 0x02, 0x1F, 0xD6};
constexpr std::array<unsigned char, 0> jump_end{};
#else
constexpr std::array<unsigned char, 2> jump_start = {0x48, 0xB8};
constexpr std::array<unsigned char, 2> jump_end = {0xFF, 0xE0};
#endif

// The bytes of a function's start that the jump replaces.
constexpr std::size_t jump_size = jump_start.size() + sizeof(Pointer) + jump_end.size();

// The jump to +address+, as it is written over a function's start.
std::array<unsigned char, jump_size> jump_to(const Pointer &address) {
  std::array<unsigned char, jump_size> jump{};
  const std::span<unsigned char> bytes(jump);
  std::ranges::copy(jump_start, bytes.begin());
  std::ranges::copy(address, bytes.subspan(jump_start.size()).begin());
  std::ranges::copy(jump_end, bytes.subspan(jump_start.size() + address.size()).begin());
  return jump;
}

// A function of SDL's whose start was replaced, and what was there.
struct Replaced {
  unsigned char *function = nullptr;
  std::array<unsigned char, jump_size> original{};
};

// The functions SDL shows dialogs with, once replaced.
std::array<Replaced, 2> &replaced() {
  static std::array<Replaced, 2> functions;
  return functions;
}

// Writes +bytes+ over the start of +function+, which is code.
bool overwrite(unsigned char *function, const std::array<unsigned char, jump_size> &bytes) {
  DWORD protection = 0;
  if (VirtualProtect(function, jump_size, PAGE_EXECUTE_READWRITE, &protection) == FALSE) {
    return false;
  }
  std::memcpy(function, bytes.data(), jump_size);
  VirtualProtect(function, jump_size, protection, &protection);
  FlushInstructionCache(GetCurrentProcess(), function, jump_size);
  return true;
}

// Writes what a dialog said to standard error.
void say_refused(const char *title, const char *message) {
  std::fprintf(stderr, "lota_dialogs: refused a message box (no one can answer it): %s: %s\n",
               title != nullptr ? title : "", message != nullptr ? message : "");
  std::fflush(stderr);
}

// SDL_ShowMessageBox, refused.
bool refused_message_box(const SDL_MessageBoxData *data, int *button) {
  if (data == nullptr) {
    return false;
  }
  if (button != nullptr) {
    *button = -1;
  }
  say_refused(data->title, data->message);
  return false;
}

// SDL_ShowSimpleMessageBox, refused.
bool refused_simple_message_box(SDL_MessageBoxFlags /*flags*/, const char *title,
                                const char *message, SDL_Window * /*window*/) {
  say_refused(title, message);
  return false;
}

// Replaces SDL's function +name+ with +refusal+ in the one SDL3.dll every
// extension of Lota's shares, keeping its start in +slot+.
void replace(Replaced &slot, const char *name, const Pointer &refusal) {
#if defined(__x86_64__) || defined(__aarch64__)
  HMODULE sdl = GetModuleHandleW(L"SDL3.dll");
  if (sdl == nullptr) {
    sdl = LoadLibraryW(L"SDL3.dll");
  }
  FARPROC const found = sdl == nullptr ? nullptr : GetProcAddress(sdl, name);
  if (found == nullptr) {
    return;
  }
  auto *const function = reinterpret_cast<unsigned char *>(found);
  const std::array<unsigned char, jump_size> jump = jump_to(refusal);
  std::array<unsigned char, jump_size> original{};
  std::memcpy(original.data(), function, jump_size);
  if (overwrite(function, jump)) {
    slot.function = function;
    slot.original = original;
  }
#else
  static_cast<void>(slot);
  static_cast<void>(name);
  static_cast<void>(refusal);
#endif
}

// The longest name a window class can have, 256 characters
// (WNDCLASSW's lpszClassName), and the zero that ends it.
constexpr std::size_t class_name_capacity = 257;

// The name of +window+'s class, or an empty one when Windows cannot say.
std::wstring class_of(HWND window) {
  std::array<wchar_t, class_name_capacity> name{};
  const int length = GetClassNameW(window, name.data(), static_cast<int>(name.size()));
  return length > 0 ? std::wstring(name.data(), static_cast<std::size_t>(length)) : std::wstring();
}

// The first character past ASCII's, which a class name in window_state
// shows as a question mark.
constexpr wchar_t ascii_end = 0x80;

// Whether +window+ is of the window class +name+.
bool of_class(HWND window, const wchar_t *name) { return class_of(window) == name; }

// The timer that presses Return once a dialog has taken the focus, and
// how long after the dialog is activated it does, in milliseconds.
constexpr UINT_PTR return_timer = 0x10ca;
constexpr UINT return_delay = 100;

// What a WM_KEYDOWN and a WM_KEYUP of Return carry in their lParam
// (WM_KEYDOWN's and WM_KEYUP's documentation): a repeat count of 1 in
// bits 0 to 15 and Return's scan code, 0x1C, in bits 16 to 23; the key
// going up also sets bit 30, that it was down, and bit 31, that it is
// being let go.
constexpr LPARAM return_down = 0x001C0001;
constexpr LPARAM return_up = 0xC01C0001;

// Presses Return on +dialog+, in the control that holds the keyboard
// focus, as a person's Return reaches it: SDL's dialog, a task dialog or
// the dialog of its own it shows where there is none, answers Return with
// the button flagged SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, which it
// makes the default (SDL 3.4.10, src/video/windows/
// SDL_windowsmessagebox.c, WIN_ShowMessageBox's nDefaultButton, and the
// BS_DEFPUSHBUTTON and IDOK of WIN_ShowOldMessageBox and MessageBoxDialogProc).
void CALLBACK press_return(HWND dialog, UINT /*message*/, UINT_PTR timer, DWORD /*time*/) {
  KillTimer(dialog, timer);
  HWND target = GetFocus();
  if (target == nullptr || (target != dialog && IsChild(dialog, target) == FALSE)) {
    target = dialog;
  }
  PostMessageW(target, WM_KEYDOWN, VK_RETURN, return_down);
  PostMessageW(target, WM_KEYUP, VK_RETURN, return_up);
  ++answered();
}

// Watches this thread's windows as they are activated, and presses Return
// on each dialog, of Windows' dialog class, #32770, once it is up and its
// message loop runs, which dispatches the timer's message.
LRESULT CALLBACK watch_for_dialogs(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HCBT_ACTIVATE) {
    HWND window = reinterpret_cast<HWND>(wparam);
    if (of_class(window, L"#32770")) {
      SetTimer(window, return_timer, return_delay, press_return);
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

// This process's windows of SDL's class, in Windows' order, front first.
std::vector<HWND> sdl_windows() {
  std::vector<HWND> windows;
  EnumWindows(
      [](HWND window, LPARAM found) -> BOOL {
        DWORD process = 0;
        GetWindowThreadProcessId(window, &process);
        if (process == GetCurrentProcessId() && of_class(window, L"SDL_app")) {
          reinterpret_cast<std::vector<HWND> *>(found)->push_back(window);
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&windows));
  return windows;
}

// The program's first window, or nullptr when it has none.
HWND first_window() {
  const std::vector<HWND> windows = sdl_windows();
  return windows.empty() ? nullptr : windows.front();
}

} // namespace

void refuse_dialogs() {
  if (refusing_dialogs()) {
    return;
  }
  auto &[message_box, simple_message_box] = replaced();
  replace(message_box, "SDL_ShowMessageBox", std::bit_cast<Pointer>(&refused_message_box));
  replace(simple_message_box, "SDL_ShowSimpleMessageBox",
          std::bit_cast<Pointer>(&refused_simple_message_box));
}

bool refusing_dialogs() { return replaced().front().function != nullptr; }

// Answers dialogs from now on, by putting SDL's functions back, and
// presses Return on each. Calling it again changes nothing.
void press_return_on_dialogs() {
  for (Replaced &slot : replaced()) {
    if (slot.function != nullptr && overwrite(slot.function, slot.original)) {
      slot.function = nullptr;
    }
  }
  if (dialog_hook() == nullptr) {
    dialog_hook() = SetWindowsHookExW(WH_CBT, watch_for_dialogs, nullptr, GetCurrentThreadId());
  }
}

int dialogs_answered() { return answered().load(); }

// Presses and lets go of +key+, as a person's key would, which makes this
// the program that last had input, so Windows lets it take the
// foreground (SetForegroundWindow's remarks). The key goes to the window
// in front, which is not one of this program's.
namespace {
void press(WORD key) {
  std::array<INPUT, 2> inputs{};
  for (INPUT &input : inputs) {
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
  }
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}
} // namespace

// Windows lets a program bring its window to the front only while it is
// the one the person last gave input to, or shares its input with the
// thread of the window in front (SetForegroundWindow's remarks), so this
// thread shares the input of that window's thread while it asks, as the
// window's own click would give it the focus. Where Windows refuses
// still, as where the shell's own window, such as the Start menu, is in
// front, it presses Escape, which closes that, and Alt, and asks again.
void activate() {
  HWND const window = first_window();
  if (window == nullptr) {
    return;
  }
  const DWORD self = GetCurrentThreadId();
  HWND const front = GetForegroundWindow();
  const DWORD other = front == nullptr ? 0 : GetWindowThreadProcessId(front, nullptr);
  const bool shared = other != 0 && other != self && AttachThreadInput(self, other, TRUE) != FALSE;
  ShowWindow(window, SW_SHOW);
  BringWindowToTop(window);
  if (SetForegroundWindow(window) == FALSE) {
    press(VK_ESCAPE);
    press(VK_MENU);
    SetForegroundWindow(window);
  }
  SetActiveWindow(window);
  SetFocus(window);
  if (shared) {
    AttachThreadInput(self, other, FALSE);
  }
}

bool has_focus() {
  HWND const window = first_window();
  return window != nullptr && GetForegroundWindow() == window && GetFocus() == window;
}

// Nothing to do: Windows has no program to activate, only windows, which
// SDL's hints keep from activating when they are shown or raised
// (test/test_helper.rb).
void stay_in_background() {}

// Gives the foreground to the desktop's shell window, since nothing
// records which window had it before activate.
void give_up_focus() {
  HWND const shell = GetShellWindow();
  if (shell != nullptr) {
    SetForegroundWindow(shell);
  }
}

// Nothing to do: SDL learns of a window's occlusion on Windows only from
// its being minimized and restored (src/video/windows/SDL_windowsevents.c,
// WM_SIZE), which the pumps that deliver those events keep current.
void reread_occlusion() {}

// Each of the program's windows: whether it is visible and in front, and
// where it is.
std::string window_state() {
  std::string state;
  HWND const foreground = GetForegroundWindow();
  for (HWND window : sdl_windows()) {
    RECT rect{};
    GetWindowRect(window, &rect);
    state += "window " + std::to_string(reinterpret_cast<std::uintptr_t>(window)) +
             (IsWindowVisible(window) != FALSE ? " visible" : " hidden") +
             (window == foreground ? " foreground" : "") + " at " + std::to_string(rect.left) +
             "," + std::to_string(rect.top) + " " + std::to_string(rect.right - rect.left) + "x" +
             std::to_string(rect.bottom - rect.top) + "\n";
  }
  std::string in_front;
  if (foreground != nullptr) {
    for (const wchar_t c : class_of(foreground)) {
      in_front += c < ascii_end ? static_cast<char>(c) : '?';
    }
  }
  state += "in front: " +
           (foreground == nullptr ? std::string("no window")
                                  : std::to_string(reinterpret_cast<std::uintptr_t>(foreground)) +
                                        " of class " + in_front) +
           "\n";
  return state;
}

// A runner's desktop has no person at the mouse, and SDL's warp moves
// Windows' own cursor, which reaches the window under it whatever it
// accepts (src/video/windows/SDL_windowsmouse.c, WIN_WarpMouse). Nothing
// to do, as on Linux.
bool ignore_mouse_events(bool /*ignore*/) { return false; }

} // namespace lota::native_test
