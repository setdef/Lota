// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/window.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "window/Window.h"
#include "window/sdl/Window.h"

#include <optional>
#include <string>
#include <utility>

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

// Whether the module is open, as boot.lua asks with "if love.window then".
// Asking reads no window state, so any thread may ask.
bool is_open() { return love::Module::getInstance<Window>(love::Module::M_WINDOW) != nullptr; }

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

// w__setHighDPIAllowed (vendor/love/src/modules/love/love.cpp:439-445),
// which boot.lua calls before the window opens.
void set_high_dpi_allowed(bool enable) {
  require_main_thread(MODULE);
  love::window::setHighDPIAllowed(enable);
}

// w_showMessageBox's simple form (wrap_Window.cpp:590-596 and 639-653), when its
// third argument is not a table: shows +message+ in a box titled +title+,
// of the kind +type+ names ("info" when nil), and returns whether it could.
bool show_message_box(const std::string &title, const std::string &message,
                      const std::optional<std::string> &type, bool attachtowindow) {
  Window::MessageBoxType box_type = Window::MESSAGEBOX_INFO;
  if (type.has_value() && !Window::getConstant(type->c_str(), box_type)) {
    raise_enum_error("messagebox type", Window::getConstants(box_type), type.value());
  }
  return window().showMessageBox(title, message, box_type, attachtowindow);
}

// w_showMessageBox's form with buttons (wrap_Window.cpp:590-638), when its
// third argument is a table: shows the buttons +buttons+ names and returns
// which the player pressed, counting from 1. +enterbutton+ and
// +escapebutton+ count from 1, as the table's fields do; the first button
// answers Return and the last Escape unless they say otherwise.
int show_message_box_with_buttons(const std::string &title, const std::string &message,
                                  Rice::Array button_list, std::optional<int> enterbutton,
                                  std::optional<int> escapebutton,
                                  const std::optional<std::string> &type, bool attachtowindow) {
  // A Rice::Array rather than a std::vector, whose Ruby class Rice would
  // define in each bundle that converts one, as LotaNativeTest does.
  const Rice::Array buttons = std::move(button_list);
  Window::MessageBoxData data = {};
  data.type = Window::MESSAGEBOX_INFO;
  data.title = title;
  data.message = message;
  for (const auto item : buttons) {
    data.buttons.push_back(Rice::detail::From_Ruby<std::string>().convert(item.value()));
  }
  if (data.buttons.empty()) {
    raise_argument_error("Must have at least one messagebox button.");
  }
  data.enterButtonIndex = enterbutton.has_value() ? enterbutton.value() - 1 : 0;
  data.escapeButtonIndex = escapebutton.has_value() ? escapebutton.value() - 1
                                                    : static_cast<int>(data.buttons.size()) - 1;
  if (type.has_value() && !Window::getConstant(type->c_str(), data.type)) {
    raise_enum_error("messagebox type", Window::getConstants(data.type), type.value());
  }
  data.attachToWindow = attachtowindow;
  return window().showMessageBox(data) + 1;
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
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("set_mode", &set_mode, Rice::Arg("width"), Rice::Arg("height"),
                                 Rice::Arg("settings"))
      .define_singleton_function("fullscreen_types", &fullscreen_types)
      .define_singleton_function("set_high_dpi_allowed", &set_high_dpi_allowed, Rice::Arg("enable"))
      .define_singleton_function(
          "show_message_box", &show_message_box, Rice::Arg("title"), Rice::Arg("message"),
          Rice::Arg("type") = std::optional<std::string>(), Rice::Arg("attachtowindow") = true)
      .define_singleton_function("show_message_box_with_buttons", &show_message_box_with_buttons,
                                 Rice::Arg("title"), Rice::Arg("message"), Rice::Arg("buttons"),
                                 Rice::Arg("enterbutton") = std::optional<int>(),
                                 Rice::Arg("escapebutton") = std::optional<int>(),
                                 Rice::Arg("type") = std::optional<std::string>(),
                                 Rice::Arg("attachtowindow") = true);
}

} // namespace lota::native
