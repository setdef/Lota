// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/window.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "window/Window.h"
#include "window/sdl/Window.h"

#include <string>

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

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w_setMode (wrap_Window.cpp:130-151): opens or changes the window, and
// returns false when the system refuses the mode. nil settings are
// LÖVE's setMode(width, height) with no table.
bool set_mode(int width, int height, WindowSettings *settings) {
  return window().setWindow(width, height, settings);
}

// readWindowSettings' fullscreentype (wrap_Window.cpp:60-66): false for a
// name Window does not know, which Lota::Window.set_mode raises
// ArgumentError for, with luax_enumerror's message and the names
// fullscreen_types gives.
bool set_fullscreen_type(WindowSettings &settings, const std::string &name) {
  return Window::getConstant(name.c_str(), settings.fstype);
}

Rice::Array fullscreen_types() {
  Rice::Array names;
  for (const std::string &name : Window::getConstants(Window::FULLSCREEN_MAX_ENUM)) {
    names.push(name, false);
  }
  return names;
}

// w_setTitle and w_getTitle (wrap_Window.cpp:463-474). The title waits in
// the module until the window opens.
void set_title(const std::string &title) { window().setWindowTitle(title); }

std::string title() { return window().getWindowTitle(); }

// w__setHighDPIAllowed (vendor/love/src/modules/love/love.cpp:439-445),
// which boot.lua calls before the window opens.
void set_high_dpi_allowed(bool enable) {
  require_main_thread(MODULE);
  love::window::setHighDPIAllowed(enable);
}

// SPDX-SnippetEnd

} // namespace

void define_window(const Rice::Module &native) {
  // The settings w_setMode reads from its table (readWindowSettings,
  // wrap_Window.cpp:56-128) start from WindowSettings' own defaults
  // (window/Window.h:284-303). displayindex counts from 0 here, as in
  // C++; Lota::Window counts from 1, as LÖVE's Lua API does.
  Rice::define_class_under<WindowSettings>(native, "WindowSettings")
      .define_constructor(Rice::Constructor<WindowSettings>())
      .define_attr("fullscreen", &WindowSettings::fullscreen)
      .define_method("set_fullscreentype", &set_fullscreen_type, Rice::Arg("name"))
      .define_attr("vsync", &WindowSettings::vsync)
      .define_attr("msaa", &WindowSettings::msaa)
      .define_attr("stencil", &WindowSettings::stencil)
      .define_attr("depth", &WindowSettings::depth)
      .define_attr("resizable", &WindowSettings::resizable)
      .define_attr("minwidth", &WindowSettings::minwidth)
      .define_attr("minheight", &WindowSettings::minheight)
      .define_attr("borderless", &WindowSettings::borderless)
      .define_attr("centered", &WindowSettings::centered)
      .define_attr("displayindex", &WindowSettings::displayindex)
      .define_attr("usedpiscale", &WindowSettings::usedpiscale)
      .define_attr("useposition", &WindowSettings::useposition)
      .define_attr("x", &WindowSettings::x)
      .define_attr("y", &WindowSettings::y);

  Rice::define_module_under(native, "Window")
      .define_singleton_function("open", &open)
      .define_singleton_function("set_mode", &set_mode, Rice::Arg("width"), Rice::Arg("height"),
                                 Rice::Arg("settings"))
      .define_singleton_function("fullscreen_types", &fullscreen_types)
      .define_singleton_function("set_title", &set_title, Rice::Arg("title"))
      .define_singleton_function("title", &title)
      .define_singleton_function("set_high_dpi_allowed", &set_high_dpi_allowed,
                                 Rice::Arg("enable"));
}

} // namespace lota::native
