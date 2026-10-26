// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/event.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "common/Variant.h"
#include "event/Event.h"
#include "event/sdl/Event.h"

#include <bit>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace lota::native {

using love::Variant;
using love::event::Event;
using love::event::Message;

namespace {

Event &event() {
  auto *instance = love::Module::getInstance<Event>(love::Module::M_EVENT);
  if (instance == nullptr) {
    throw love::Exception("Lota::Event is not open.");
  }
  return *instance;
}

// luaopen_love_event (vendor/love/src/modules/event/wrap_Event.cpp:
// 263-287) creates SDL's event module once; it then lives as long as the
// process, as LÖVE's lives until the game quits.
void open() { open_module<Event, love::event::sdl::Event>(love::Module::M_EVENT); }

// Whether the module is open, as boot.lua and callbacks.lua ask with
// "if love.event then".
bool is_open() { return love::Module::getInstance<Event>(love::Module::M_EVENT) != nullptr; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_pushvariant (vendor/love/src/common/runtime.cpp), for
// the kinds of value LÖVE's event module puts in a message, and changed to
// build Ruby values instead of pushing Lua ones.

// Appends one argument of a message to +result+, as Ruby sees it. Strings
// come back as bytes in Ruby's default external encoding (Rice's
// std::string conversion); Lota::Callbacks marks them as the UTF-8 SDL
// gives. A light userdata, such as a touch's id, becomes the Integer its
// pointer holds. Engine objects and tables come only from modules Lota
// does not open yet (love.joystick, love.filesystem) or from
// love.event.push, which Lota does not bind yet.
void push_argument(Rice::Array &result, const Variant &variant) {
  const Variant::Data &data = variant.getData();
  // Variant keeps its value in a union, tagged by getType(), and offers no
  // other way to read it.
  // NOLINTBEGIN(cppcoreguidelines-pro-type-union-access)
  switch (variant.getType()) {
  case Variant::BOOLEAN:
    result.push(data.boolean, false);
    break;
  case Variant::NUMBER:
    result.push(data.number, false);
    break;
  case Variant::STRING:
    result.push(std::string(data.string->str, data.string->len), false);
    break;
  case Variant::SMALLSTRING:
    result.push(std::string(&data.smallstring.str[0], data.smallstring.len), false);
    break;
  case Variant::LUSERDATA:
    result.push(std::bit_cast<std::uintptr_t>(data.userdata), false);
    break;
  case Variant::NIL:
    result.push(Rice::Object(), false);
    break;
  default:
    throw love::Exception("Lota cannot pass this event's arguments to Ruby yet.");
  }
  // NOLINTEND(cppcoreguidelines-pro-type-union-access)
}

// w_poll_i (wrap_Event.cpp:52-65) and luax_pushmessage (lines 42-50): the
// next message, as an Array of its name and its arguments, or nil when the
// queue is empty. Event::poll hands over the queue's reference, which the
// StrongRef releases.
Rice::Object poll() {
  Message *polled = nullptr;
  if (!event().poll(polled) || polled == nullptr) {
    return {};
  }
  const love::StrongRef<Message> message(polled, love::Acquire::NORETAIN);
  Rice::Array result;
  result.push(message->name, false);
  for (const Variant &argument : message->args) {
    push_argument(result, argument);
  }
  return result;
}

// w_quit (wrap_Event.cpp:123-136): queues a quit message with one
// argument, the exit status, or nil when there is none.
bool quit(std::optional<double> exit_status) {
  std::vector<Variant> args;
  if (exit_status.has_value()) {
    args.emplace_back(exit_status.value());
  } else {
    args.emplace_back();
  }
  const love::StrongRef<Message> message(new Message("quit", args), love::Acquire::NORETAIN);
  event().push(message.get());
  return true;
}

// SPDX-SnippetEnd

} // namespace

void define_event(const Rice::Module &native) {
  Rice::define_module_under(native, "Event")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("poll", &poll)
      .define_singleton_function("quit", &quit, Rice::Arg("exit_status") = std::optional<double>());
}

} // namespace lota::native
