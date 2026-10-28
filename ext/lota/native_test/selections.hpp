// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// X11's clipboard, as the tests share one display (selections_linux.cpp).

#ifndef LOTA_NATIVE_TEST_SELECTIONS_HPP
#define LOTA_NATIVE_TEST_SELECTIONS_HPP

namespace lota::native_test {

// Lets an error about another program's window, such as one that asked
// this program for the clipboard and went away before SDL answered, pass
// without ending the program, as Xlib's default handler would.
void tolerate_vanished_requestors();

// Asks for the clipboard's TARGETS from a window of a connection of its
// own, as another program's SDL does, then closes the connection before
// the owner can answer, as a program that exits does. Whether it could
// open the display.
bool request_clipboard_and_vanish();

} // namespace lota::native_test

#endif // LOTA_NATIVE_TEST_SELECTIONS_HPP
