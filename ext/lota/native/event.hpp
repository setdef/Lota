// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_EVENT_HPP
#define LOTA_NATIVE_EVENT_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the functions of love::event::Event that open the module, pump
// and poll its queue, and push a quit message, as module functions of
// <native>::Event.
void define_event(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_EVENT_HPP
