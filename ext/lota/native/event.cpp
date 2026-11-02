// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/event.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "common/Variant.h"
#include "event/Event.h"
#include "event/sdl/Event.h"

#include <bit>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>
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

// luax_pushmessage (wrap_Event.cpp:42-50): +message+ as an Array of its
// name and its arguments. Event::poll and Event::wait hand over the
// message's reference, which the StrongRef releases.
Rice::Array message_array(Message *message) {
  const love::StrongRef<Message> owned(message, love::Acquire::NORETAIN);
  Rice::Array result;
  result.push(owned->name, false);
  for (const Variant &argument : owned->args) {
    push_argument(result, argument);
  }
  return result;
}

// w_poll_i (wrap_Event.cpp:52-65): the next message, as an Array of its
// name and its arguments, or nil when the queue is empty.
Rice::Object poll() {
  Message *polled = nullptr;
  if (!event().poll(polled) || polled == nullptr) {
    return {};
  }
  return message_array(polled);
}

// w_wait (wrap_Event.cpp:74-91), after the deprecation notice that
// Lota::Event.wait marks: the next message, waiting for one, as an Array
// of its name and its arguments, or nil when SDL's event is one LÖVE does
// not pass on.
Rice::Object wait() {
  Message *waited = event().wait();
  if (waited == nullptr) {
    return {};
  }
  return message_array(waited);
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

// Each of +list+, which Lota::Event.push has read as w_push reads them (up
// to the first nil, raising its error for a value an event cannot carry),
// as the Variant luax_checkvariant makes of it: a boolean, a number, or a
// string.
std::vector<Variant> variants(const Rice::Array &list) {
  std::vector<Variant> args;
  Rice::detail::From_Ruby<std::variant<bool, double, std::string>> from_ruby;
  for (const auto item : list) {
    std::visit([&args](const auto &value) { args.emplace_back(value); },
               from_ruby.convert(item.value()));
  }
  return args;
}

// w_push (wrap_Event.cpp:85-110): queues a message named +name+ with
// +arguments+.
bool push(const std::string &name, Rice::Array list) {
  const Rice::Array arguments = std::move(list);
  const love::StrongRef<Message> message(new Message(name, variants(arguments)),
                                         love::Acquire::NORETAIN);
  event().push(message.get());
  return true;
}

// w_restart (wrap_Event.cpp:138-153): queues a quit message whose first
// argument is "restart", followed by +arguments+, as Lota::Event.restart
// reads them for push.
bool restart(Rice::Array list) {
  const Rice::Array arguments = std::move(list);
  std::vector<Variant> args;
  args.emplace_back(std::string("restart"));
  for (Variant &argument : variants(arguments)) {
    args.push_back(std::move(argument));
  }
  const love::StrongRef<Message> message(new Message("quit", args), love::Acquire::NORETAIN);
  event().push(message.get());
  return true;
}

// drawCallback and cleanupCallback (wrap_Event.cpp:166-199), for a Ruby
// callable that LÖVE keeps in a Reference to a Lua function. The callable
// is a root of Ruby's garbage collector from when the event module takes
// it until the module lets go of it.
using Callable = ruby::Root;

// The Variant luax_checkvariant (without tables) makes of one of the
// values a modal draw callback returns, which is nothing, a boolean, a
// number, or a string.
Variant returned_variant(const Rice::Object &value) {
  if (ruby::is_nil(value)) {
    return {};
  }
  if (ruby::is_boolean(value)) {
    return {ruby::is_true(value)};
  }
  if (ruby::is_numeric(value)) {
    return {Rice::detail::From_Ruby<double>().convert(value.value())};
  }
  if (ruby::is_string(value)) {
    return {Rice::detail::From_Ruby<std::string>().convert(value.value())};
  }
  throw love::Exception(
      "Error in modal draw callback: it returned %s, which an event cannot carry.",
      ruby::class_name(value).c_str());
}

// drawCallback (wrap_Event.cpp:174-199): calls the callable, whose two
// results, an Array when it returns several (rule 4), go to LÖVE's quit
// message. A Ruby error it raises reaches the pump as an exception, with
// the callback's name in front, as LÖVE's does.
void draw_callback(void *context, Variant *first, Variant *second) {
  Rice::Object callable = static_cast<Callable *>(context)->value();
  try {
    const Rice::Object result = callable.vcall("call", Rice::Array());
    if (ruby::is_array(result)) {
      const std::vector<Rice::Object> values = ruby::elements(Rice::Array(result));
      *first = values.empty() ? Variant() : returned_variant(values.at(0));
      *second = values.size() < 2 ? Variant() : returned_variant(values.at(1));
    } else {
      *first = returned_variant(result);
      *second = Variant();
    }
  } catch (const Rice::Exception &error) {
    throw love::Exception("Error in modal draw callback: %s", error.what());
  }
}

void cleanup_callback(void *context) {
  const std::unique_ptr<Callable> owned(static_cast<Callable *>(context));
}

// The ModalDrawData for +callable+, or none for nil (wrap_Event.cpp:
// 201-221).
love::event::Event::ModalDrawData modal_draw_data(const Rice::Object &callable) {
  love::event::Event::ModalDrawData data = {};
  if (!ruby::is_nil(callable)) {
    data.draw = &draw_callback;
    data.cleanup = &cleanup_callback;
    data.context = std::make_unique<Callable>(callable).release();
  }
  return data;
}

// w_setModalDrawCallback (wrap_Event.cpp:201-221): the function the event
// module calls to redraw the window while the system's own loop is
// resizing it, or none.
void set_modal_draw_callback(Rice::Object given) {
  const Rice::Object callable = std::move(given);
  event().setModalDrawData(modal_draw_data(callable));
}

// SPDX-SnippetEnd

} // namespace

void define_event(const Rice::Module &native) {
  Rice::define_module_under(native, "Event")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("poll", &poll)
      .define_singleton_function("wait", &wait)
      .define_singleton_function("push", &push, Rice::Arg("name"), Rice::Arg("arguments"))
      .define_singleton_function("restart", &restart, Rice::Arg("arguments"))
      .define_singleton_function("set_modal_draw_callback", &set_modal_draw_callback,
                                 Rice::Arg("callable"))
      .define_singleton_function("quit", &quit, Rice::Arg("exit_status") = std::optional<double>());
}

} // namespace lota::native
