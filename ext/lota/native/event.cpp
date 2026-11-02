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
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
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

// Appends +variant+ to +result+ as Ruby sees it, unless it is a table,
// whose SharedTable it returns instead for push_table to write. Strings
// come back as bytes in Ruby's default external encoding (Rice's
// std::string conversion); Lota::Variant marks them as the UTF-8 SDL
// gives. A light userdata, such as a touch's id, becomes the Integer its
// pointer holds, and a value of unknown type, which love.event.restart and
// a modal draw callback make of a function, becomes nil, as
// luax_pushvariant's default pushes. Engine objects come only from modules
// Lota does not open yet (love.joystick, love.filesystem), and Lota's own
// love.event functions do not put them in a message yet.
const Variant::SharedTable *push_value(Rice::Array &result, const Variant &variant) {
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
  case Variant::TABLE:
    return data.table;
  case Variant::NIL:
  case Variant::UNKNOWN:
    result.push(Rice::Object(), false);
    break;
  default:
    throw love::Exception("Lota cannot pass this event's arguments to Ruby yet.");
  }
  // NOLINTEND(cppcoreguidelines-pro-type-union-access)
  return nullptr;
}

// The Symbol that starts a table among Lota::Variant's tokens.
Rice::Symbol table_token() { return {"table"}; }

// luax_pushvariant for a table (runtime.cpp:837-853), which sets each of
// its pairs, key and then value, in the table's order: appends to +result+
// one Array of Lota::Variant's tokens for +table+, the Symbol :table and
// the number of its pairs, then each key and value, a table among them
// written so in its place. Lota::Variant reads it as an Array or a Hash.
// It keeps its place in each table it is inside of, rather than calling
// itself, so a table nests as deep as Ruby built it.
void push_table(Rice::Array &result, const Variant::SharedTable *table) {
  struct Place {
    const Variant::SharedTable *table;
    std::size_t next; // the next of its keys and values, two to a pair
  };
  Rice::Array tokens;
  std::vector<Place> places;
  const auto open = [&tokens, &places](const Variant::SharedTable *opened) {
    tokens.push(table_token(), false);
    tokens.push(opened->pairs.size(), false);
    places.push_back({.table = opened, .next = 0});
  };
  open(table);
  while (!places.empty()) {
    Place &place = places.back();
    if (place.next == place.table->pairs.size() * 2) {
      places.pop_back();
      continue;
    }
    const auto &pair = place.table->pairs.at(place.next / 2);
    const Variant &value = place.next % 2 == 0 ? pair.first : pair.second;
    place.next++;
    if (const Variant::SharedTable *inner = push_value(tokens, value)) {
      open(inner);
    }
  }
  result.push(tokens, false);
}

// Appends one argument of a message to +result+, as Ruby sees it: a table
// as the Array of its tokens (push_table), and anything else as itself
// (push_value). Nothing else in a message becomes an Array.
void push_argument(Rice::Array &result, const Variant &variant) {
  if (const Variant::SharedTable *table = push_value(result, variant)) {
    push_table(result, table);
  }
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

// w_wait (wrap_Event.cpp:74-88), after the deprecation notice that
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

// The Variant for the one token that is a value in itself: nil, a
// boolean, a Float, a String, or :unknown, which Lota::Variant writes for
// a Proc or a Method, or a table with one in it.
Variant token_variant(const Rice::Object &token) {
  if (ruby::is_nil(token)) {
    return {};
  }
  if (ruby::is_boolean(token)) {
    return {ruby::is_true(token)};
  }
  if (ruby::is_string(token)) {
    return {Rice::detail::From_Ruby<std::string>().convert(token.value())};
  }
  if (ruby::is_symbol(token) && ruby::symbol_name(token) == "unknown") {
    return Variant::unknown();
  }
  return {Rice::detail::From_Ruby<double>().convert(token.value())};
}

// A table being read from tokens: its pairs so far, how many are to come,
// and the key of the pair it is in the middle of.
struct OpenTable {
  love::StrongRef<Variant::SharedTable> table;
  std::size_t remaining;
  std::optional<Variant> key;
};

// Gives +value+ to the table it is in, as the key or the value of its next
// pair, and each table that completes so to the one it is in. Returns the
// value no table is open to take, which is the whole value read.
std::optional<Variant> place(std::vector<OpenTable> &tables, Variant value) {
  while (!tables.empty()) {
    OpenTable &open = tables.back();
    if (!open.key.has_value()) {
      open.key = std::move(value);
      return std::nullopt;
    }
    open.table->pairs.emplace_back(std::move(open.key.value()), std::move(value));
    open.key.reset();
    if (--open.remaining > 0) {
      return std::nullopt;
    }
    // The Variant releases the table it is given, so it takes a reference
    // of its own.
    open.table->retain();
    value = Variant(open.table.get());
    tables.pop_back();
  }
  return value;
}

// The Variant luax_checkvariant (runtime.cpp:722-812) makes, from the
// tokens Lota::Variant.tokens has read a Ruby value into: a table is the
// Symbol :table, the number of its pairs, and each key and value in turn,
// read into a SharedTable (runtime.cpp:758-808). Lota::Variant has already
// raised LÖVE's errors and made a table of unknown type one token. Raises
// ArgumentError for tokens it did not write.
Variant tokens_variant(const Rice::Array &tokens) {
  std::vector<OpenTable> tables;
  long index = 0;
  while (index < ruby::length(tokens)) {
    const Rice::Object token = ruby::entry(tokens, index++);
    std::optional<Variant> whole;
    if (ruby::is_symbol(token) && ruby::symbol_name(token) == "table") {
      if (index == ruby::length(tokens)) {
        break;
      }
      const auto count =
          Rice::detail::From_Ruby<std::size_t>().convert(ruby::entry(tokens, index++).value());
      love::StrongRef<Variant::SharedTable> table(new Variant::SharedTable(),
                                                  love::Acquire::NORETAIN);
      if (count > 0) {
        tables.push_back({.table = std::move(table), .remaining = count, .key = std::nullopt});
        continue;
      }
      table->retain();
      whole = place(tables, Variant(table.get()));
    } else {
      whole = place(tables, token_variant(token));
    }
    if (whole.has_value()) {
      if (index != ruby::length(tokens)) {
        break;
      }
      return std::move(whole.value());
    }
  }
  ruby::raise_argument_error("not the tokens of one value");
}

// Each of +list+, an Array of Lota::Variant's tokens for each value, as
// its Variant.
std::vector<Variant> variants(const Rice::Array &list) {
  std::vector<Variant> values;
  values.reserve(static_cast<std::size_t>(ruby::length(list)));
  for (long index = 0; index < ruby::length(list); index++) {
    values.push_back(tokens_variant(Rice::Array(ruby::entry(list, index))));
  }
  return values;
}

// w_push (wrap_Event.cpp:90-115): queues a message named +name+ with
// +arguments+, which Lota::Event.push has read as w_push reads them, up to
// the first nil and raising its error for a value of unknown type.
bool push(const std::string &name, Rice::Array list) {
  const Rice::Array arguments = std::move(list);
  const love::StrongRef<Message> message(new Message(name, variants(arguments)),
                                         love::Acquire::NORETAIN);
  event().push(message.get());
  return true;
}

// w_restart (wrap_Event.cpp:138-153): queues a quit message whose first
// argument is "restart", followed by every one of +arguments+, nil
// included, which Lota::Event.restart has read as luax_checkvariant reads
// them.
bool restart(Rice::Array list) {
  const Rice::Array arguments = std::move(list);
  std::vector<Variant> args = variants(arguments);
  args.emplace(args.begin(), std::string("restart"));
  const love::StrongRef<Message> message(new Message("quit", args), love::Acquire::NORETAIN);
  event().push(message.get());
  return true;
}

// drawCallback and cleanupCallback (wrap_Event.cpp:176-199), for a Ruby
// callable that LÖVE keeps in a Reference to a Lua function. The callable
// is a root of Ruby's garbage collector from when the event module takes
// it until the module lets go of it.
using Callable = ruby::Root;

// drawCallbackInner and drawCallback (wrap_Event.cpp:161-193): calls the
// callable, which Lota::Event.modal_draw_callback= has given the game's
// callable to, and which returns the tokens of its two results, each read
// as luax_checkvariant reads it, for LÖVE's quit message. An error it
// raises, the game's or one for a result Lota cannot read, reaches the
// pump as an exception with the callback's name in front, as lua_cpcall
// catches every error in LÖVE's. So does a throw or another non-local
// exit, which Rice reports as a JumpException: a Lua function has no way
// out but an error, and Event::modalDraw would pass the exit on without
// the name.
void draw_callback(void *context, Variant *first, Variant *second) {
  Rice::Object callable = static_cast<Callable *>(context)->value();
  try {
    const Rice::Array results(callable.vcall("call", Rice::Array()));
    *first = tokens_variant(Rice::Array(ruby::entry(results, 0)));
    *second = tokens_variant(Rice::Array(ruby::entry(results, 1)));
  } catch (const Rice::Exception &error) {
    throw love::Exception("Error in modal draw callback: %s", error.what());
  } catch (const Rice::JumpException &jump) {
    throw love::Exception("Error in modal draw callback: %s", jump.what());
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
