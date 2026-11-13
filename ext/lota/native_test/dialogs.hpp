// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Return pressed on the dialogs a program shows, for the tests and the
// parity harness (dialogs.mm).

#ifndef LOTA_NATIVE_TEST_DIALOGS_HPP
#define LOTA_NATIVE_TEST_DIALOGS_HPP

#include <string>

namespace lota::native_test {

// Presses Return on every dialog the program shows from now on, and keeps
// the program from becoming the active one when it shows one.
void press_return_on_dialogs();

// How many dialogs press_return_on_dialogs has pressed Return on.
int dialogs_answered();

// Makes this program the active one, with its first window in front and
// holding keyboard focus, as a player's click on it would.
void activate();

// Keeps this program from ever becoming the active one, so none of its
// windows can take keyboard focus, while it still shows them.
void stay_in_background();

// Undoes activate: gives keyboard focus back to the program that had it,
// and keeps this one in the background from then on.
void give_up_focus();

#ifdef _WIN32
// Whether the program's first window is the foreground one and holds the
// keyboard focus, as Windows says.
bool has_focus();
#endif

// Has SDL ask the system again whether the program's first window can be
// seen, which SDL otherwise learns only when the system says it changed.
void reread_occlusion();

// What the system says of the program's windows: whether each can be
// seen, is in front, has focus, and where it is; for a test's failure
// message.
std::string window_state();

// Makes the program's windows let the system's mouse events through to
// whatever is under them, or, with +ignore+ false, take them again.
// Whether it could.
bool ignore_mouse_events(bool ignore);

} // namespace lota::native_test

#endif // LOTA_NATIVE_TEST_DIALOGS_HPP
