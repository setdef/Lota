// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_DEPRECATION_HPP
#define LOTA_NATIVE_DEPRECATION_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the engine's record of deprecated names, which the engine draws
// over each frame it presents, as module functions of <native>::Deprecation.
void define_deprecation(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_DEPRECATION_HPP
