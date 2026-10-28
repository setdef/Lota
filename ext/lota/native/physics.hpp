// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_PHYSICS_HPP
#define LOTA_NATIVE_PHYSICS_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds LÖVE's physics module, as Lota's physics patch leaves it
// (ext/lota/engine/physics.patch): World, Body, Contact, Shape and its
// subclasses, and Joint and its subclasses as <native>::World and the rest,
// and the functions that open the module and make its objects as module
// functions of <native>::Physics.
void define_physics(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_PHYSICS_HPP
