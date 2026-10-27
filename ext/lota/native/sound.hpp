// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_SOUND_HPP
#define LOTA_NATIVE_SOUND_HPP

#include "native/binding.hpp"

#include "sound/Decoder.h"

#include <string>

namespace lota::native {

// Binds love::sound::Decoder and SoundData as <native>::Decoder and
// <native>::SoundData, and, as module functions of <native>::Sound, the
// functions that open LÖVE's sound module and make Decoders and SoundData,
// whose decoders love.audio reads a sound file with.
void define_sound(const Rice::Module &native);

// A Decoder for the file +filename+, in the game's folder or its save
// directory, as love.sound.newDecoder makes one from a filename: decoding
// from the open file as it plays, or from a copy of it in memory, by
// +source+. Lota::Native::Audio.new_source makes its Decoder here too, as
// love.audio.newSource calls love.sound.newDecoder.
love::sound::Decoder *new_decoder(const std::string &filename, int buffer_size,
                                  love::sound::Decoder::StreamSource source);

} // namespace lota::native

#endif // LOTA_NATIVE_SOUND_HPP
