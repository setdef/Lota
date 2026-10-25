// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/keyboard.hpp"

#include "native/binding.hpp"

#include "common/Module.h"
#include "keyboard/Keyboard.h"
#include "keyboard/sdl/Keyboard.h"

namespace lota::native {

using love::keyboard::Keyboard;

namespace {

// luaopen_love_keyboard (vendor/love/src/modules/keyboard/
// wrap_Keyboard.cpp:224-242) creates SDL's keyboard module once; it then
// lives as long as the process, as LÖVE's lives until the game quits. The
// event module asks it whether to pass on repeated key presses
// (event/sdl/Event.cpp:284-290), and it starts with key repeat off.
void open() { open_module<Keyboard, love::keyboard::sdl::Keyboard>(love::Module::M_KEYBOARD); }

} // namespace

void define_keyboard(const Rice::Module &native) {
  Rice::define_module_under(native, "Keyboard").define_singleton_function("open", &open);
}

} // namespace lota::native
