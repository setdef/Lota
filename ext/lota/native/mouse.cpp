// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/mouse.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "mouse/Cursor.h"
#include "mouse/Mouse.h"
#include "mouse/sdl/Mouse.h"

#include <string>
#include <utility>
#include <vector>

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

// w_isDown (wrap_Mouse.cpp:203-232): whether any of the buttons, each an
// Integer, is held down, read from one Array where LÖVE reads them from
// every argument or from a table.
bool is_down(Rice::Array buttons) {
  const Rice::Array list = std::move(buttons);
  std::vector<int> numbers;
  numbers.reserve(list.size());
  for (const auto item : list) {
    numbers.push_back(Rice::detail::From_Ruby<int>().convert(item.value()));
  }
  const auto *instance = love::Module::getInstance<Mouse>(love::Module::M_MOUSE);
  if (instance == nullptr) {
    throw love::Exception("Lota::Mouse is not open.");
  }
  return instance->isDown(numbers);
}

// w_Cursor_getType (vendor/love/src/modules/mouse/wrap_Cursor.cpp:34-54):
// an image cursor's kind, or a system cursor's shape.
std::string cursor_type(const Cursor &cursor) {
  const Cursor::CursorType ctype = cursor.getType();
  const char *typestr = nullptr;

  if (ctype == Cursor::CURSORTYPE_IMAGE) {
    Cursor::getConstant(ctype, typestr);
  } else if (ctype == Cursor::CURSORTYPE_SYSTEM) {
    const Cursor::SystemCursor systype = cursor.getSystemType();
    Cursor::getConstant(systype, typestr);
  }

  if (typestr == nullptr) {
    throw love::Exception("Unknown cursor type.");
  }
  return typestr;
}

// SPDX-SnippetEnd

} // namespace

void define_mouse(const Rice::Module &native) {
  Rice::Module mouse = Rice::define_module_under(native, "Mouse");
  define_engine_class<Cursor>(mouse, "Cursor").define_method("get_type", &cursor_type);
  mouse.define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("down?", &is_down, Rice::Arg("buttons"));
}

} // namespace lota::native
