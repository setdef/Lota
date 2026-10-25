// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/event.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "event/Event.h"
#include "event/sdl/Event.h"

namespace lota::native {

using love::event::Event;

namespace {

// luaopen_love_event (vendor/love/src/modules/event/wrap_Event.cpp:
// 263-287) creates SDL's event module once; it then lives as long as the
// process, as LÖVE's lives until the game quits.
void open() { open_module<Event, love::event::sdl::Event>(love::Module::M_EVENT); }

// w_pump with no timeout (wrap_Event.cpp:67-72): gathers what SDL has
// queued without waiting.
void pump() {
  auto *instance = love::Module::getInstance<Event>(love::Module::M_EVENT);
  if (instance == nullptr) {
    throw love::Exception("Lota::Event is not open.");
  }
  instance->pump(0.0F);
}

} // namespace

void define_event(const Rice::Module &native) {
  Rice::define_module_under(native, "Event")
      .define_singleton_function("open", &open)
      .define_singleton_function("pump", &pump);
}

} // namespace lota::native
