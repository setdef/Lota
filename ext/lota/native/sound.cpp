// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/sound.hpp"

#include "native/binding.hpp"

#include "common/Module.h"
#include "sound/Sound.h"
#include "sound/lullaby/Sound.h"

namespace lota::native {

namespace {

using love::sound::Sound;

// luaopen_love_sound (vendor/love/src/modules/sound/wrap_Sound.cpp:
// 128-150) creates the lullaby sound module once, as boot.lua requires
// love.sound before love.audio (boot.lua:348-368).
void open() { open_module<Sound, love::sound::lullaby::Sound>(love::Module::M_SOUND); }

bool is_open() { return love::Module::getInstance<Sound>(love::Module::M_SOUND) != nullptr; }

} // namespace

void define_sound(const Rice::Module &native) {
  Rice::define_module_under(native, "Sound")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open);
}

} // namespace lota::native
