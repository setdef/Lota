// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/window.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "window/Window.h"
#include "window/sdl/Window.h"

#include <array>
#include <bit>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

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

// w_getMode's fullscreentype (wrap_Window.cpp:189-193): the name of the
// settings' fullscreen type, "desktop" for one Window has no name for.
std::string fullscreen_type(const WindowSettings &settings) {
  const char *fstypestr = "desktop";
  Window::getConstant(settings.fstype, fstypestr);
  return fstypestr;
}

// What w_getMode and w_updateMode read first (wrap_Window.cpp:153-157
// and 180-184): the window's size, as an Array, with +settings+ filled
// in with its current settings, which Lota::Window.mode and update_mode
// read from it.
Rice::Array get_window(WindowSettings &settings) {
  int width = 0;
  int height = 0;
  window().getWindow(width, height, settings);
  Rice::Array size;
  size.push(width, false);
  size.push(height, false);
  return size;
}

Rice::Array fullscreen_types() {
  Rice::Array names;
  for (const std::string &name : Window::getConstants(Window::FULLSCREEN_MAX_ENUM)) {
    names.push(name, false);
  }
  return names;
}

// w_getFullscreen (wrap_Window.cpp:332-345): whether the window is
// fullscreen and the name of its fullscreen type, as an Array (rule 4 of
// doc/contributors/design/translation.md). Unlike w_getMode, it raises for a
// type Window has no name for.
Rice::Array get_fullscreen() {
  int width = 0;
  int height = 0;
  WindowSettings settings;
  window().getWindow(width, height, settings);

  const char *typestr = nullptr;
  if (!Window::getConstant(settings.fstype, typestr)) {
    throw love::Exception("Unknown fullscreen type.");
  }

  Rice::Array results;
  results.push(settings.fullscreen, false);
  results.push(std::string(typestr), false);
  return results;
}

// w_getFullscreenModes (wrap_Window.cpp:272-309): the modes of a display,
// each as an Array of its width, height, and refresh rate, which
// Lota::Window.fullscreen_modes makes frozen FullscreenModes (rule 28). The
// display counts from 1, as the table's does, and is the window's own
// when nil.
Rice::Array get_fullscreen_modes(std::optional<int> display) {
  int displayindex = 0;
  if (display.has_value()) {
    displayindex = display.value() - 1;
  } else {
    int x = 0;
    int y = 0;
    window().getPosition(x, y, displayindex);
  }

  Rice::Array list;
  for (const Window::DisplayMode &mode : window().getFullscreenModes(displayindex)) {
    Rice::Array entry;
    entry.push(mode.width, false);
    entry.push(mode.height, false);
    entry.push(mode.refreshRate, false);
    list.push(entry, false);
  }
  return list;
}

// w_setVSync (wrap_Window.cpp:434-443): the Ruby side has turned a
// boolean into the 1 or 0 LÖVE makes of it.
void set_vsync(int vsync) { window().setVSync(vsync); }

// w_close (wrap_Window.cpp:353-358), which LÖVE has deprecated without a
// replacement; Lota::Window.close marks it so.
void close_window() { window().close(); }

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

// The names of the file dialog's types, for Lota::Window.show_file_dialog's
// error (luax_enumerror, wrap_Window.cpp:692-694).
Rice::Array file_dialog_types() {
  Rice::Array names;
  for (const std::string &name : Window::getConstants(Window::FILEDIALOG_MAX_ENUM)) {
    names.push(name, false);
  }
  return names;
}

// Sets +data+'s type to the one +name+ names, and returns whether one
// does (wrap_Window.cpp:692-694).
bool set_file_dialog_type(Window::FileDialogData &data, const std::string &name) {
  return Window::getConstant(name.c_str(), data.type);
}

// Adds a filter to +data+, as w_showFileDialog does for each entry of its
// filters table (wrap_Window.cpp:722-739).
void add_file_dialog_filter(Window::FileDialogData &data, const std::string &name,
                            const std::string &pattern) {
  data.filters.push_back(Window::FileDialogFilter{.name = name, .pattern = pattern});
}

// The function a game gives w_showFileDialog, which LÖVE keeps in a
// Reference until it calls it: a Ruby callable, a root of Ruby's garbage
// collector until then.
using FileDialogCallable = ruby::Root;

// fileDialogCallback (wrap_Window.cpp:655-686): calls the callable,
// which Lota::Window.show_file_dialog has given the game's callable to,
// with the chosen files as an Array, the chosen filter's name or nil, and
// the error or nil, and lets go of it. Window::handleSDLEvent calls this
// from the event pump, on the main thread
// (src/modules/window/sdl/Window.cpp:1545-1558). An error the callable
// raises reaches the pump as an exception with the callback's name in
// front, as LÖVE's does after lua_pcall; so does a throw or another
// non-local exit, which Rice reports as a JumpException, as in Lota's
// modal draw callback (native/event.cpp).
//
// An empty name is left out. No path is empty, and SDL reports a
// cancelled zenity, which prints nothing, as one empty name where its
// documentation promises an empty list (SDL 3.4.10,
// src/dialog/unix/SDL_zenitydialog.c, run_zenity), which LÖVE passes on
// (upstream/027.md).
void file_dialog_callback(void *context, const std::vector<std::string> &files,
                          const char *filtername, const char *errstr) {
  const std::unique_ptr<FileDialogCallable> callable(static_cast<FileDialogCallable *>(context));
  Rice::Array list;
  for (const std::string &file : files) {
    if (!file.empty()) {
      list.push(Rice::String(file), false);
    }
  }
  Rice::Array arguments;
  arguments.push(list, false);
  // The filter's name and the error, each nil where LÖVE pushes nil.
  for (const char *text : std::array<const char *, 2>{filtername, errstr}) {
    arguments.push(text != nullptr ? Rice::Object(Rice::String(text)) : ruby::nil(), false);
  }
  try {
    callable->value().vcall("call", arguments);
  } catch (const Rice::Exception &error) {
    throw love::Exception("Error in file dialog callback: %s", error.what());
  } catch (const Rice::JumpException &jump) {
    throw love::Exception("Error in file dialog callback: %s", jump.what());
  }
}

// w_showFileDialog (wrap_Window.cpp:688-757): shows the dialog +data+
// describes, which Lota::Window.show_file_dialog has filled in from its
// arguments as LÖVE reads its table, and returns at once; the callable
// gets the answer later (file_dialog_callback).
void show_file_dialog(const Window::FileDialogData &data, Rice::Object given) {
  const Rice::Object callable = std::move(given);
  Window &instance = window();
  instance.showFileDialog(data, &file_dialog_callback,
                          std::make_unique<FileDialogCallable>(callable).release());
}

// w_getPointer (wrap_Window.cpp:766-770): the address of SDL's window,
// which LÖVE pushes as a lightuserdata, as an Integer, 0 while no window
// is open, which Lota::Window.pointer makes a Fiddle::Pointer.
std::uintptr_t pointer() { return std::bit_cast<std::uintptr_t>(window().getHandle()); }

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
      .define_method("fullscreentype", &fullscreen_type)
      .define_attr("refreshrate", &WindowSettings::refreshrate, Rice::AttrAccess::Read)
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

  // The settings w_showFileDialog reads from its table
  // (wrap_Window.cpp:688-750), which start zeroed, as LÖVE's
  // FileDialogData data = {} does: the first type, openfile, no strings,
  // no filters, and neither multiselect nor attachtowindow.
  Rice::define_class_under<Window::FileDialogData>(native, "FileDialogData")
      .define_constructor(Rice::Constructor<Window::FileDialogData>())
      .define_method("set_type", &set_file_dialog_type, Rice::Arg("name"))
      .define_attr("title", &Window::FileDialogData::title)
      .define_attr("acceptlabel", &Window::FileDialogData::acceptLabel)
      .define_attr("cancellabel", &Window::FileDialogData::cancelLabel)
      .define_attr("defaultname", &Window::FileDialogData::defaultName)
      .define_method("add_filter", &add_file_dialog_filter, Rice::Arg("name"), Rice::Arg("pattern"))
      .define_attr("multiselect", &Window::FileDialogData::multiSelect)
      .define_attr("attachtowindow", &Window::FileDialogData::attachToWindow);

  Rice::define_module_under(native, "Window")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("set_mode", &set_mode, Rice::Arg("width"), Rice::Arg("height"),
                                 Rice::Arg("settings"))
      .define_singleton_function("get_window", &get_window, Rice::Arg("settings"))
      .define_singleton_function("fullscreen_types", &fullscreen_types)
      .define_singleton_function("fullscreen", &get_fullscreen)
      .define_singleton_function("fullscreen_modes", &get_fullscreen_modes,
                                 Rice::Arg("display") = std::optional<int>())
      .define_singleton_function("set_vsync", &set_vsync, Rice::Arg("vsync"))
      .define_singleton_function("close", &close_window)
      .define_singleton_function("set_high_dpi_allowed", &set_high_dpi_allowed, Rice::Arg("enable"))
      .define_singleton_function("pointer", &pointer)
      .define_singleton_function(
          "show_message_box", &show_message_box, Rice::Arg("title"), Rice::Arg("message"),
          Rice::Arg("type") = std::optional<std::string>(), Rice::Arg("attachtowindow") = true)
      .define_singleton_function("show_message_box_with_buttons", &show_message_box_with_buttons,
                                 Rice::Arg("title"), Rice::Arg("message"), Rice::Arg("buttons"),
                                 Rice::Arg("enterbutton") = std::optional<int>(),
                                 Rice::Arg("escapebutton") = std::optional<int>(),
                                 Rice::Arg("type") = std::optional<std::string>(),
                                 Rice::Arg("attachtowindow") = true)
      .define_singleton_function("file_dialog_types", &file_dialog_types)
      .define_singleton_function("show_file_dialog", &show_file_dialog, Rice::Arg("data"),
                                 Rice::Arg("callable"));
}

} // namespace lota::native
