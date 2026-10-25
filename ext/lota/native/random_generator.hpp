// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_RANDOM_GENERATOR_HPP
#define LOTA_NATIVE_RANDOM_GENERATOR_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::math::RandomGenerator as <native>::RandomGenerator.
void define_random_generator(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_RANDOM_GENERATOR_HPP
