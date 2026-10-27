// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_SOUND_HPP
#define LOTA_NATIVE_SOUND_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds <native>::Sound, which opens LÖVE's sound module, whose decoders
// love.audio reads a sound file with.
void define_sound(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_SOUND_HPP
