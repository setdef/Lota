// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_AUDIO_HPP
#define LOTA_NATIVE_AUDIO_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::audio::Source as <native>::Source, and the functions that
// open LÖVE's audio module, make a Source from a sound file, and play and
// stop Sources, as module functions of <native>::Audio.
void define_audio(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_AUDIO_HPP
