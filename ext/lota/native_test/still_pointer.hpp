// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The pointer held still against the person at the computer, for the tests
// that move it and read it back (still_pointer.mm).

#ifndef LOTA_NATIVE_TEST_STILL_POINTER_HPP
#define LOTA_NATIVE_TEST_STILL_POINTER_HPP

#include <string>

namespace lota::native_test {

// From now on, drops every movement of the mouse the system reports to
// this program, before SDL reads it, so the pointer's place in SDL is only
// ever where the program put it.
void hold_pointer();

// Undoes hold_pointer.
void release_pointer();

// Queues a movement of the mouse to +x+, +y+ in +window+, an NSWindow,
// counting from its top left, as the system queues one when the person at
// the computer moves the mouse, and waits, for up to a second, until
// AppKit's queue holds it. Whether it does.
bool move_mouse_as_a_person_would(const void *window, double x, double y);

// What AppKit says of +window+, an NSWindow, and this program, for a test
// whose movement did not arrive: whether the program is active, and the
// window visible, key, unoccluded, and accepting mouse movements.
std::string window_state(const void *window);

} // namespace lota::native_test

#endif // LOTA_NATIVE_TEST_STILL_POINTER_HPP
