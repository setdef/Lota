// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/mouse.hpp"

#include "native/binding.hpp"
#include "native/global_position.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "image/ImageData.h"
#include "mouse/Cursor.h"
#include "mouse/Mouse.h"
#include "mouse/sdl/Mouse.h"

#include <SDL3/SDL_mouse.h>
#include <SDL3/SDL_rect.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_video.h>

#include <cstddef>
#include <memory>
#include <span>
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

// w_newCursor (wrap_Mouse.cpp:36-92): a Cursor of +images+, each an
// ImageData, which Lota::Mouse::Cursor.new reads from an image, a file,
// or an Array of them, with its hot spot at +hotx+ and +hoty+. The
// Cursor's one reference goes to the Ruby wrapper.
Cursor *new_cursor(Rice::Array images, int hotx, int hoty) {
  const Rice::Array list = std::move(images);
  std::vector<love::image::ImageData *> data;
  data.reserve(list.size());
  for (const auto item : list) {
    data.push_back(Rice::detail::From_Ruby<love::image::ImageData *>().convert(item.value()));
  }
  auto *instance = love::Module::getInstance<Mouse>(love::Module::M_MOUSE);
  if (instance == nullptr) {
    throw love::Exception("Lota::Mouse is not open.");
  }
  return instance->newCursor(data, hotx, hoty);
}

// Frees what SDL allocated, as SDL_GetDisplays' documentation says its
// caller must (SDL_video.h).
struct SDLFree {
  void operator()(void *memory) const { SDL_free(memory); }
};

// w_getGlobalPosition (wrap_Mouse.cpp:192-201) and the
// Mouse::getGlobalPosition it calls (mouse/sdl/Mouse.cpp:166-197): the
// pointer's place on the display it is on, and that display, counting
// from 1, asked of SDL as LÖVE asks. LÖVE never frees the list of displays,
// and subtracts the origin of every display before the pointer's
// (doc/contributors/upstream/022.md); this frees the list, and subtracts
// that display's origin alone (native/global_position.hpp).
Rice::Array global_position() {
  if (love::Module::getInstance<Mouse>(love::Module::M_MOUSE) == nullptr) {
    throw love::Exception("Lota::Mouse is not open.");
  }
  float globalx = 0.0F;
  float globaly = 0.0F;
  SDL_GetGlobalMouseState(&globalx, &globaly);

  int displaycount = 0;
  const std::unique_ptr<SDL_DisplayID, SDLFree> displays(SDL_GetDisplays(&displaycount));
  std::vector<SDL_Rect> bounds;
  if (displays != nullptr && displaycount > 0) {
    const std::span<const SDL_DisplayID> ids(displays.get(),
                                             static_cast<std::size_t>(displaycount));
    bounds.reserve(ids.size());
    for (const SDL_DisplayID id : ids) {
      SDL_Rect rect = {};
      SDL_GetDisplayBounds(id, &rect);
      bounds.push_back(rect);
    }
  }

  const DisplayPlace place = place_on_displays(globalx, globaly, bounds);
  Rice::Array results;
  results.push(place.x, false);
  results.push(place.y, false);
  results.push(place.displayindex + 1, false);
  return results;
}

// SPDX-SnippetEnd

} // namespace

void define_mouse(const Rice::Module &native) {
  Rice::Module mouse = Rice::define_module_under(native, "Mouse");
  define_engine_class<Cursor>(mouse, "Cursor").define_method("get_type", &cursor_type);
  mouse.define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("down?", &is_down, Rice::Arg("buttons"))
      .define_singleton_function("global_position", &global_position)
      .define_singleton_function("new_cursor", &new_cursor, Rice::Arg("images"), Rice::Arg("hotx"),
                                 Rice::Arg("hoty"), Rice::Return().takeOwnership());
}

} // namespace lota::native
