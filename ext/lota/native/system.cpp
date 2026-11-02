// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/system.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "system/System.h"
#include "system/sdl/System.h"

#include <string>

namespace lota::native {

namespace {

// luaopen_love_system (vendor/love/src/modules/system/wrap_System.cpp:
// 141-159) creates SDL's system module once; it then lives as long as the
// process, as LÖVE's lives until the game quits. boot.lua opens it before
// conf.lua runs, whatever the settings say (boot.lua:48-49).
void open() {
  open_module<love::system::System, love::system::sdl::System>(love::Module::M_SYSTEM);
}

// Whether the module is open, as a game asks with "if love.system".
bool is_open() {
  return love::Module::getInstance<love::system::System>(love::Module::M_SYSTEM) != nullptr;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to build a Ruby
// Array instead of a Lua table.

// w_getPreferredLocales (vendor/love/src/modules/system/wrap_System.cpp:
// 110-122): the player's preferred locales, as an Array of Strings.
Rice::Array preferred_locales() {
  const auto *instance = love::Module::getInstance<love::system::System>(love::Module::M_SYSTEM);
  if (instance == nullptr) {
    throw love::Exception("Lota::System is not open.");
  }
  Rice::Array locales;
  for (const std::string &locale : instance->getPreferredLocales()) {
    locales.push(locale, false);
  }
  return locales;
}

// SPDX-SnippetEnd

} // namespace

void define_system(const Rice::Module &native) {
  Rice::define_module_under(native, "System")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("preferred_locales", &preferred_locales);
}

} // namespace lota::native
