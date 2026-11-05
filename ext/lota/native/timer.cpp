// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/timer.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "timer/Timer.h"

namespace lota::native {

using love::timer::Timer;

namespace {

// luaopen_love_timer (vendor/love/src/modules/timer/wrap_Timer.cpp:
// 82-101) creates the module once; it then lives as long as the process,
// as LÖVE's lives until the game quits.
void open() { open_module<Timer, Timer>(love::Module::M_TIMER); }

// Whether the module is open, as boot.lua and callbacks.lua ask with
// "if love.timer".
bool is_open() { return love::Module::getInstance<Timer>(love::Module::M_TIMER) != nullptr; }

void *sleep_without_gvl(void *data) {
  const auto *timer = love::Module::getInstance<Timer>(love::Module::M_TIMER);
  timer->sleep(*static_cast<double *>(data));
  return nullptr;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from w_sleep (vendor/love/src/modules/timer/wrap_Timer.cpp:
// 57-61), and changed to sleep with Ruby's GVL released, as Ruby's own
// sleep does: the other threads of this Ractor run meanwhile, and so does
// Ruby's collector, which waits for every Ractor that holds its GVL, so a
// thread that sleeps (Lota::Thread) delays no other. SDL's delay cannot
// be cut short, so an interrupt waits for the sleep to end, and Ruby then
// raises it.
void w_sleep(double seconds) {
  if (love::Module::getInstance<Timer>(love::Module::M_TIMER) == nullptr) {
    throw love::Exception("Lota::Timer is not open.");
  }
  ruby::without_gvl(&sleep_without_gvl, static_cast<void *>(&seconds));
}

// SPDX-SnippetEnd

} // namespace

void define_timer(const Rice::Module &native) {
  Rice::define_module_under(native, "Timer")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("sleep", &w_sleep, Rice::Arg("seconds"));
}

} // namespace lota::native
