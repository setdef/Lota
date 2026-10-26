// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_FILESYSTEM_HPP
#define LOTA_NATIVE_FILESYSTEM_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::Data as <native>::Data and love::filesystem::FileData as
// <native>::FileData, with the functions that make one from a string or
// read one from a file, and the ones that open LÖVE's filesystem module,
// as module functions of <native>::Filesystem.
void define_filesystem(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_FILESYSTEM_HPP
