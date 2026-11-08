// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_SHADER_HPP
#define LOTA_NATIVE_SHADER_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::graphics::Shader as <native>::Shader, with the methods that
// send it uniforms, and the functions of love.graphics that compile and
// validate shaders, as module functions of <native>::Graphics. Its other
// methods are generated, so it runs before define_generated.
void define_shader(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_SHADER_HPP
