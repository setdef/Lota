// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/touch.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "touch/Touch.h"
#include "touch/sdl/Touch.h"

#include <cstdint>
#include <optional>
#include <string>

namespace lota::native {

using love::touch::Touch;

namespace {

// luaopen_love_touch (vendor/love/src/modules/touch/wrap_Touch.cpp:
// 138-156) creates SDL's touch module once; it then lives as long as the
// process, as LÖVE's lives until the game quits. The event module keeps
// its list of touches (event/sdl/Event.cpp:413-416), and keeps none while
// it is not open.
void open() { open_module<Touch, love::touch::sdl::Touch>(love::Module::M_TOUCH); }

// Whether the module is open, as a game asks with "if love.touch then".
bool is_open() { return love::Module::getInstance<Touch>(love::Module::M_TOUCH) != nullptr; }

// w__setTrackpadTouch (vendor/love/src/modules/love/love.cpp:447-453):
// whether a trackpad reports touches (touch/sdl/Touch.cpp:37-40).
void set_trackpad_touch(bool enable) { love::touch::setTrackpadTouch(enable); }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from w_getTouches (vendor/love/src/modules/touch/
// wrap_Touch.cpp:44-76), and changed to take its filter from Rice and to
// return a Ruby Array instead of a Lua table.

// The ids of the touches now pressed, of the device type +filter+ names
// when one is given, in the order they were pressed. LÖVE pushes each id
// as a light userdata holding the id, and the event module's messages
// hold the same pointer, which Lota gives Ruby as the Integer it holds
// (native/event.cpp, push_value), so an id from one equals the id from
// the other.
Rice::Array touches(const std::optional<std::string> &filter) {
  std::optional<Touch::DeviceType> type;
  if (filter.has_value()) {
    Touch::DeviceType value = Touch::DEVICE_MAX_ENUM;
    if (!Touch::getConstant(filter->c_str(), value)) {
      raise_enum_error("touch device type", Touch::getConstants(value), filter.value());
    }
    type = value;
  }

  const auto *instance = love::Module::getInstance<Touch>(love::Module::M_TOUCH);
  if (instance == nullptr) {
    throw love::Exception("Lota::Touch is not open.");
  }

  Rice::Array ids;
  for (const Touch::TouchInfo &touch : instance->getTouches()) {
    if (!type.has_value() || type.value() == touch.deviceType) {
      ids.push(static_cast<std::uintptr_t>(static_cast<std::intptr_t>(touch.id)), false);
    }
  }
  return ids;
}

// SPDX-SnippetEnd

} // namespace

void define_touch(const Rice::Module &native) {
  Rice::define_module_under(native, "Touch")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("set_trackpad_touch", &set_trackpad_touch, Rice::Arg("enable"))
      .define_singleton_function("touches", &touches,
                                 Rice::Arg("filter") = std::optional<std::string>());
}

} // namespace lota::native
