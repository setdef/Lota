// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_IMAGE_HPP
#define LOTA_NATIVE_IMAGE_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::image::ImageData as <native>::ImageData, and the functions of
// love::image::Image that Lota::Image translates as module functions of
// <native>::Image.
void define_image(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_IMAGE_HPP
