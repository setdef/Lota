// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_SYSTEM_HPP
#define LOTA_NATIVE_SYSTEM_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the functions of love::system::System that open the module, as
// module functions of <native>::System. Its clipboard functions are
// generated (native/generated/system.cpp).
void define_system(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_SYSTEM_HPP
