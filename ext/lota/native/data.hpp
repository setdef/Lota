// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_DATA_HPP
#define LOTA_NATIVE_DATA_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love.data's module as <native>::Data, with its functions
// (vendor/love/src/modules/data/wrap_DataModule.cpp), and love::Data, the
// root of every Data class, as <native>::Data::Data, with the methods
// every Data has (wrap_Data.cpp), for the classes bound after it to
// inherit, and love.data's own ByteData, CompressedData, and DataView.
void define_data(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_DATA_HPP
