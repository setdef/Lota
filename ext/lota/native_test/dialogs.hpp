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

} // namespace lota::native_test

#endif // LOTA_NATIVE_TEST_DIALOGS_HPP
