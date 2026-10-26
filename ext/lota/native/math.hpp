// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_MATH_HPP
#define LOTA_NATIVE_MATH_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the function that opens love::math::Math, and the one that reaches
// its random number generator, as module functions of <native>::Math.
void define_math(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_MATH_HPP
