// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/keyboard.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "keyboard/Keyboard.h"
#include "keyboard/sdl/Keyboard.h"

#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::keyboard::Keyboard;

namespace {

// luaopen_love_keyboard (vendor/love/src/modules/keyboard/
// wrap_Keyboard.cpp:224-242) creates SDL's keyboard module once; it then
// lives as long as the process, as LÖVE's lives until the game quits. The
// event module asks it whether to pass on repeated key presses
// (event/sdl/Event.cpp:284-290), and it starts with key repeat off.
void open() { open_module<Keyboard, love::keyboard::sdl::Keyboard>(love::Module::M_KEYBOARD); }

// Whether the module is open, as a game asks with "if love.keyboard then".
bool is_open() { return love::Module::getInstance<Keyboard>(love::Module::M_KEYBOARD) != nullptr; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w_isDown with its keys as arguments (vendor/love/src/modules/keyboard/
// wrap_Keyboard.cpp:46-84): every name is checked before the module is
// asked, and one that names no key raises. The names arrive as a Ruby Array
// of Strings, as Lota::Native::Graphics.set_renderers takes its names.
bool is_down(Rice::Array names) {
  const Rice::Array list = std::move(names);
  std::vector<Keyboard::Key> keys;
  keys.reserve(list.size());
  for (const auto item : list) {
    const std::string name = Rice::String(item.value()).str();
    Keyboard::Key key = Keyboard::KEY_UNKNOWN;
    if (!Keyboard::getConstant(name.c_str(), key)) {
      raise_enum_error("key constant", name);
    }
    keys.push_back(key);
  }
  const auto *instance = love::Module::getInstance<Keyboard>(love::Module::M_KEYBOARD);
  if (instance == nullptr) {
    throw love::Exception("Lota::Keyboard is not open.");
  }
  return instance->isDown(keys);
}

// SPDX-SnippetEnd

} // namespace

void define_keyboard(const Rice::Module &native) {
  Rice::define_module_under(native, "Keyboard")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("down?", &is_down, Rice::Arg("names"));
}

} // namespace lota::native
