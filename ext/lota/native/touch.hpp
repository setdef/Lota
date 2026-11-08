// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_TOUCH_HPP
#define LOTA_NATIVE_TOUCH_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the touch module's opening, love.touch.getTouches, and
// love::touch::setTrackpadTouch, which boot.lua calls before any module
// opens, as module functions of <native>::Touch; the generator binds the
// rest of love.touch beside them.
void define_touch(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_TOUCH_HPP
