// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_TOUCH_HPP
#define LOTA_NATIVE_TOUCH_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::touch::setTrackpadTouch, which boot.lua calls before any
// module opens, as a module function of <native>::Touch.
void define_touch(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_TOUCH_HPP
