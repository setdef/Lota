// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_TEXTURE_HPP
#define LOTA_NATIVE_TEXTURE_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::graphics::Texture::Settings as <native>::TextureSettings,
// the functions of love.graphics that make textures from them, read them
// back, and draw into them, as module functions of <native>::Graphics, and
// the methods of Texture that read a mipmap or replace its pixels. It runs
// after define_graphics, which defines <native>::Texture.
void define_texture(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_TEXTURE_HPP
