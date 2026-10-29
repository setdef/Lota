// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_SOUND_HPP
#define LOTA_NATIVE_SOUND_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::sound::Decoder and SoundData as <native>::Decoder and
// <native>::SoundData, and, as module functions of <native>::Sound, the
// functions that open LÖVE's sound module and make Decoders and SoundData.
void define_sound(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_SOUND_HPP
