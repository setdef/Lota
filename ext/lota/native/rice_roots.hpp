// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Where Rice's roots go on Ruby 4.0 (native/rice_roots.cpp). It goes, with
// that file and the compile definition native/CMakeLists.txt names, when
// Lota requires Ruby 4.1.

#ifndef LOTA_NATIVE_RICE_ROOTS_HPP
#define LOTA_NATIVE_RICE_ROOTS_HPP

namespace lota::native {

// Makes the object Ruby marks Rice's roots from, once, from Init_native,
// on the main Ractor, before any other Ractor can call into Lota::Native.
void install_rice_roots();

} // namespace lota::native

#endif // LOTA_NATIVE_RICE_ROOTS_HPP
