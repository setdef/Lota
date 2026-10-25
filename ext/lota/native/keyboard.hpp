// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_KEYBOARD_HPP
#define LOTA_NATIVE_KEYBOARD_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the function that opens love::keyboard::Keyboard, as a module
// function of <native>::Keyboard.
void define_keyboard(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_KEYBOARD_HPP
