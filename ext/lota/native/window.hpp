// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_WINDOW_HPP
#define LOTA_NATIVE_WINDOW_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::window::WindowSettings as <native>::WindowSettings, and the
// functions of love::window::Window that open and size the window as
// module functions of <native>::Window.
void define_window(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_WINDOW_HPP
