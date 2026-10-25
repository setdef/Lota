// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_TIMER_HPP
#define LOTA_NATIVE_TIMER_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the functions of love::timer::Timer that open the module, step its
// clock, and sleep, as module functions of <native>::Timer.
void define_timer(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_TIMER_HPP
