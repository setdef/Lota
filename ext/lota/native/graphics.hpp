// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_GRAPHICS_HPP
#define LOTA_NATIVE_GRAPHICS_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::graphics::Texture as <native>::Texture, and the functions of
// love::graphics::Graphics that Lota::Graphics translates as module
// functions of <native>::Graphics.
void define_graphics(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_GRAPHICS_HPP
