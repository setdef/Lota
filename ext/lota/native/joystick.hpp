// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_JOYSTICK_HPP
#define LOTA_NATIVE_JOYSTICK_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the functions of love.joystick the generator cannot write, and the
// one that opens it, as module functions of <native>::Joystick, and
// LÖVE's Joystick as <native>::Joystick::Joystick, with the methods the
// generator cannot write; the generator binds the rest beside them.
void define_joystick(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_JOYSTICK_HPP
