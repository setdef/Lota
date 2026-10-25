// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/timer.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "timer/Timer.h"

namespace lota::native {

using love::timer::Timer;

namespace {

Timer &timer() {
  auto *instance = love::Module::getInstance<Timer>(love::Module::M_TIMER);
  if (instance == nullptr) {
    throw love::Exception("Lota::Timer is not open.");
  }
  return *instance;
}

// luaopen_love_timer (vendor/love/src/modules/timer/wrap_Timer.cpp:
// 82-101) creates the module once; it then lives as long as the process,
// as LÖVE's lives until the game quits.
void open() { open_module<Timer, Timer>(love::Module::M_TIMER); }

// Whether the module is open, as boot.lua and callbacks.lua ask with
// "if love.timer".
bool is_open() { return love::Module::getInstance<Timer>(love::Module::M_TIMER) != nullptr; }

// w_step (wrap_Timer.cpp:35-39): the seconds since the last step.
double step() { return timer().step(); }

// w_sleep (wrap_Timer.cpp:59-63).
void sleep(double seconds) { timer().sleep(seconds); }

} // namespace

void define_timer(const Rice::Module &native) {
  Rice::define_module_under(native, "Timer")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("step", &step)
      .define_singleton_function("sleep", &sleep, Rice::Arg("seconds"));
}

} // namespace lota::native
