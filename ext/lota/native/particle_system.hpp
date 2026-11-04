// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_PARTICLE_SYSTEM_HPP
#define LOTA_NATIVE_PARTICLE_SYSTEM_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::graphics::ParticleSystem as <native>::ParticleSystem, with
// the methods that read or write its colors, sizes, and quads. Its other
// methods are generated, so it runs before define_generated.
void define_particle_system(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_PARTICLE_SYSTEM_HPP
