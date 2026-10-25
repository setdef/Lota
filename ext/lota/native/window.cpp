// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/window.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "window/Window.h"
#include "window/sdl/Window.h"

namespace lota::native {

using love::window::Window;
using love::window::WindowSettings;

namespace {

constexpr const char *MODULE = "Lota::Window";

Window &window() {
  require_main_thread(MODULE);
  auto *instance = love::Module::getInstance<Window>(love::Module::M_WINDOW);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", MODULE);
  }
  return *instance;
}

// luaopen_love_window (vendor/love/src/modules/window/wrap_Window.cpp:
// 829-845) creates SDL's window module once. Its constructor registers it
// as the module instance (love::Module's constructor), where the other
// modules find it; it then lives as long as the process, as LÖVE's lives
// until the game quits.
void open() {
  require_main_thread(MODULE);
  open_module<Window, love::window::sdl::Window>(love::Module::M_WINDOW);
}

// w_setMode (wrap_Window.cpp:130-151): opens or changes the window, and
// returns false when the system refuses the mode.
bool set_mode(int width, int height, WindowSettings *settings) {
  return window().setWindow(width, height, settings);
}

} // namespace

void define_window(const Rice::Module &native) {
  // The settings w_setMode reads from its table (readWindowSettings,
  // wrap_Window.cpp:56-128) start from WindowSettings' own defaults
  // (window/Window.h:284-303). Only the fields Lota sets so far are bound.
  Rice::define_class_under<WindowSettings>(native, "WindowSettings")
      .define_constructor(Rice::Constructor<WindowSettings>())
      .define_attr("stencil", &WindowSettings::stencil)
      .define_attr("depth", &WindowSettings::depth)
      .define_attr("resizable", &WindowSettings::resizable)
      .define_attr("usedpiscale", &WindowSettings::usedpiscale);

  Rice::define_module_under(native, "Window")
      .define_singleton_function("open", &open)
      .define_singleton_function("set_mode", &set_mode, Rice::Arg("width"), Rice::Arg("height"),
                                 Rice::Arg("settings"));
}

} // namespace lota::native
