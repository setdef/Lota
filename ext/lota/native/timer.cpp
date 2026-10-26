// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/timer.hpp"

#include "native/binding.hpp"

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

} // namespace

void define_timer(const Rice::Module &native) {
  Rice::define_module_under(native, "Timer")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open);
}

} // namespace lota::native
