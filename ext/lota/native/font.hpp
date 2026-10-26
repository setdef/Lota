// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_FONT_HPP
#define LOTA_NATIVE_FONT_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the functions of love::font::Font that open the module, as module
// functions of <native>::Font. The graphics module makes its fonts with
// it (native/graphics.cpp).
void define_font(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_FONT_HPP
