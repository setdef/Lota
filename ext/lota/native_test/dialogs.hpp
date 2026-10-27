// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Return pressed on the dialogs a program shows, for the tests and the
// parity harness (dialogs.mm).

#ifndef LOTA_NATIVE_TEST_DIALOGS_HPP
#define LOTA_NATIVE_TEST_DIALOGS_HPP

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

} // namespace lota::native_test

#endif // LOTA_NATIVE_TEST_DIALOGS_HPP
