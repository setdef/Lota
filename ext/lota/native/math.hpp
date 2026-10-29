// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_MATH_HPP
#define LOTA_NATIVE_MATH_HPP

#include "native/binding.hpp"

#include "common/Matrix.h"

#include <optional>
#include <string>

namespace lota::native {

// The matrix luax_checkmatrix reads (vendor/love/src/modules/math/
// wrap_Transform.cpp:33-124), from a matrix layout's name, row-major when
// nil, and an Array of the sixteen elements in that layout, as
// Lota::Math::Transform#matrix= and Lota::Graphics.projection= pass them.
love::Matrix4 matrix_of(const std::optional<std::string> &layout, const Rice::Array &elements);

// Binds the function that opens love::math::Math, and the one that reaches
// its random number generator, as module functions of <native>::Math, and
// defines <native>::Transform, whose other methods are generated.
void define_math(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_MATH_HPP
