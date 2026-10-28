// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_DATA_HPP
#define LOTA_NATIVE_DATA_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::Data, the root of every Data class, as <native>::Data, with
// the methods every Data has (vendor/love/src/modules/data/wrap_Data.cpp),
// for the classes bound after it to inherit.
void define_data(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_DATA_HPP
