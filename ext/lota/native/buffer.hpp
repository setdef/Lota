// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_BUFFER_HPP
#define LOTA_NATIVE_BUFFER_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::graphics::Buffer and love::graphics::Mesh as <native>::Buffer
// and <native>::Mesh, with the methods that read and write their data, and
// the functions of love.graphics that make them, as module functions of
// <native>::Graphics. Their other methods are generated, so it runs before
// define_generated.
void define_buffer(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_BUFFER_HPP
