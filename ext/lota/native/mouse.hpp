// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_MOUSE_HPP
#define LOTA_NATIVE_MOUSE_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::mouse::Cursor as <native>::Mouse::Cursor, and the functions
// of love::mouse::Mouse that the generator cannot write, with the one that
// opens it, as module functions of <native>::Mouse. The generator adds the
// rest (ext/lota/native/generated/mouse.cpp).
void define_mouse(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_MOUSE_HPP
