// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/mouse.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "mouse/Cursor.h"
#include "mouse/Mouse.h"
#include "mouse/sdl/Mouse.h"

#include <string>

namespace lota::native {

using love::mouse::Cursor;
using love::mouse::Mouse;

namespace {

// luaopen_love_mouse (vendor/love/src/modules/mouse/wrap_Mouse.cpp:301-319)
// creates SDL's mouse module once; it then lives as long as the process,
// as LÖVE's lives until the game quits. Its constructor starts SDL's video
// subsystem, which the cursors it makes need (mouse/sdl/Mouse.cpp:85-91).
void open() { open_module<Mouse, love::mouse::sdl::Mouse>(love::Module::M_MOUSE); }

// Whether the module is open, as a game asks with "if love.mouse".
bool is_open() { return love::Module::getInstance<Mouse>(love::Module::M_MOUSE) != nullptr; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w_getSystemCursor (vendor/love/src/modules/mouse/wrap_Mouse.cpp:94-107):
// the name is checked before the module is asked, and the module keeps
// each system cursor it makes (mouse/sdl/Mouse.cpp:98-110), so the Ruby
// wrapper retains one more reference, as luax_pushtype does.
Cursor *system_cursor(const std::string &name) {
  Cursor::SystemCursor type = Cursor::CURSOR_ARROW;
  if (!Cursor::getConstant(name.c_str(), type)) {
    raise_enum_error("system cursor type", name);
  }
  auto *instance = love::Module::getInstance<Mouse>(love::Module::M_MOUSE);
  if (instance == nullptr) {
    throw love::Exception("Lota::Mouse is not open.");
  }
  return instance->getSystemCursor(type);
}

// SPDX-SnippetEnd

} // namespace

void define_mouse(const Rice::Module &native) {
  Rice::Module mouse = Rice::define_module_under(native, "Mouse");
  Rice::define_class_under<Cursor>(mouse, "Cursor");
  mouse.define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("system_cursor", &system_cursor, Rice::Arg("name"));
}

} // namespace lota::native
