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

#include <array>
#include <atomic>
#include <cstdint>
#include <cwchar>
#include <iterator>
#include <string>
#include <vector>

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

// Whether +window+ is of the window class +name+.
bool of_class(HWND window, const wchar_t *name) {
  wchar_t found[32] = {};
  return GetClassNameW(window, found, static_cast<int>(std::size(found))) > 0 &&
         std::wcscmp(found, name) == 0;
}

// The timer that presses Return once a dialog has taken the focus.
constexpr UINT_PTR return_timer = 0x10ca;

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
  // The scan code of Return, 0x1C, and a repeat count of 1, in the first
  // message; the second also says the key was down and is now up.
  PostMessageW(target, WM_KEYDOWN, VK_RETURN, 0x001C0001);
  PostMessageW(target, WM_KEYUP, VK_RETURN, static_cast<LPARAM>(0xC01C0001));
  ++answered();
}

// Watches this thread's windows as they are activated, and presses Return
// on each dialog, of Windows' dialog class, #32770, once it is up and its
// message loop runs, which dispatches the timer's message.
LRESULT CALLBACK watch_for_dialogs(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HCBT_ACTIVATE) {
    HWND window = reinterpret_cast<HWND>(wparam);
    if (of_class(window, L"#32770")) {
      SetTimer(window, return_timer, 100, press_return);
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

// Calling it again changes nothing.
void press_return_on_dialogs() {
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
  wchar_t name[64] = {};
  if (foreground != nullptr) {
    GetClassNameW(foreground, name, static_cast<int>(std::size(name)));
  }
  std::string in_front;
  for (const wchar_t *c = name; *c != 0; ++c) {
    in_front += *c < 128 ? static_cast<char>(*c) : '?';
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
