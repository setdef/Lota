// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/joystick.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "filesystem/FileData.h"
#include "filesystem/Filesystem.h"
#include "joystick/Joystick.h"
#include "joystick/JoystickModule.h"
#include "joystick/sdl/JoystickModule.h"
#include "sensor/Sensor.h"

#include <cstddef>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace lota::native {

using love::joystick::Joystick;
using love::joystick::JoystickModule;
using love::sensor::Sensor;

namespace {

// luaopen_love_joystick (vendor/love/src/modules/joystick/
// wrap_JoystickModule.cpp:207-226) creates SDL's joystick module once; it
// then lives as long as the process, as LÖVE's lives until the game
// quits. The event module adds and removes its joysticks as SDL reports
// them (event/sdl/Event.cpp:714-731), and passes no joystick events while
// it is not open (lines 618-627).
void open() {
  open_module<JoystickModule, love::joystick::sdl::JoystickModule>(love::Module::M_JOYSTICK);
}

// Whether the module is open, as a game asks with "if love.joystick then".
bool is_open() {
  return love::Module::getInstance<JoystickModule>(love::Module::M_JOYSTICK) != nullptr;
}

JoystickModule &module() {
  auto *instance = love::Module::getInstance<JoystickModule>(love::Module::M_JOYSTICK);
  if (instance == nullptr) {
    throw love::Exception("Lota::Joystick is not open.");
  }
  return *instance;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State and to return Ruby values
// instead of pushing Lua ones.

// w_getJoysticks (wrap_JoystickModule.cpp:35-49): the joysticks now
// connected, in the order SDL connected them.
Rice::Array joysticks() {
  JoystickModule &instance = module();
  Rice::Array sticks;
  const int count = instance.getJoystickCount();
  for (int i = 0; i < count; i++) {
    sticks.push(instance.getJoystick(i), false);
  }
  return sticks;
}

// The gamepad axis or button +gpbindstr+ names, as w_setGamepadMapping
// and w_Joystick_getGamepadMapping read it (wrap_JoystickModule.cpp:88-97,
// wrap_Joystick.cpp:281-289): an axis first, then a button.
Joystick::GamepadInput gamepad_input(const std::string &gpbindstr) {
  Joystick::GamepadInput gpinput{};
  Joystick::GamepadAxis axis{};
  Joystick::GamepadButton button{};
  // GamepadInput keeps the axis or the button in a union, tagged by its
  // type, as LÖVE's own code fills it.
  // NOLINTBEGIN(cppcoreguidelines-pro-type-union-access)
  if (Joystick::getConstant(gpbindstr.c_str(), axis)) {
    gpinput.type = Joystick::INPUT_TYPE_AXIS;
    gpinput.axis = axis;
  } else if (Joystick::getConstant(gpbindstr.c_str(), button)) {
    gpinput.type = Joystick::INPUT_TYPE_BUTTON;
    gpinput.button = button;
  } else {
    raise_enum_error("gamepad axis/button", gpbindstr);
  }
  // NOLINTEND(cppcoreguidelines-pro-type-union-access)
  return gpinput;
}

// The joystick's own input w_setGamepadMapping binds to
// (wrap_JoystickModule.cpp:99-123): its type, its index, counting from 1,
// and a hat's direction, which only a hat reads.
Joystick::JoystickInput joystick_input(const std::string &jinputtypestr, int inputindex,
                                       const std::optional<std::string> &hatstr) {
  Joystick::JoystickInput jinput{};
  if (!Joystick::getConstant(jinputtypestr.c_str(), jinput.type)) {
    raise_enum_error("joystick input type", jinputtypestr);
  }

  // JoystickInput keeps the axis, the button, or the hat in a union,
  // tagged by its type, as LÖVE's own code fills it.
  // NOLINTBEGIN(cppcoreguidelines-pro-type-union-access)
  switch (jinput.type) {
  case Joystick::INPUT_TYPE_AXIS:
    jinput.axis = inputindex - 1;
    break;
  case Joystick::INPUT_TYPE_BUTTON:
    jinput.button = inputindex - 1;
    break;
  case Joystick::INPUT_TYPE_HAT: {
    // Hats need both a hat index and a hat value.
    jinput.hat.index = inputindex - 1;
    const std::string hat = required(hatstr, "hatdir");
    if (!Joystick::getConstant(hat.c_str(), jinput.hat.value)) {
      raise_enum_error("joystick hat", hat);
    }
    break;
  }
  default:
    raise_enum_error("joystick input type", jinputtypestr);
  }
  // NOLINTEND(cppcoreguidelines-pro-type-union-access)
  return jinput;
}

// w_setGamepadMapping (wrap_JoystickModule.cpp:80-129): whether SDL took
// the mapping. A braced list is evaluated in its order, so the gamepad's
// axis or button is checked before the joystick's input, as LÖVE checks
// them.
bool set_gamepad_mapping(const std::string &guid, const std::string &gpbindstr,
                         const std::string &jinputtypestr, int inputindex,
                         const std::optional<std::string> &hatstr) {
  const std::tuple<std::string, Joystick::GamepadInput, Joystick::JoystickInput> mapping{
      guid, gamepad_input(gpbindstr), joystick_input(jinputtypestr, inputindex, hatstr)};
  return module().setGamepadMapping(std::get<0>(mapping), std::get<1>(mapping),
                                    std::get<2>(mapping));
}

// w_loadGamepadMappings (wrap_JoystickModule.cpp:131-154): the mappings
// in the file +mappings+ names, when LÖVE's filesystem finds a file of
// that name, read as luax_getfiledata reads it, or else +mappings+
// itself.
void load_gamepad_mappings(const std::string &mappings) {
  std::string text = mappings;
  const auto *fs =
      love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
  bool isfile = false;
  if (fs != nullptr) {
    love::filesystem::Filesystem::Info info = {};
    const bool exists = fs->getInfo(mappings.c_str(), info);
    isfile = exists && info.type == love::filesystem::Filesystem::FILETYPE_FILE;
  }

  if (isfile) {
    const love::StrongRef<love::filesystem::FileData> data(fs->read(mappings.c_str()),
                                                           love::Acquire::NORETAIN);
    text = std::string(static_cast<const char *>(data->getData()), data->getSize());
  }

  module().loadGamepadMappings(text);
}

// w_saveGamepadMappings (wrap_JoystickModule.cpp:156-173), up to the
// string it returns; Lota::Joystick.save_gamepad_mappings writes it to a
// file, as LÖVE's calls love.filesystem.write.
std::string save_gamepad_mappings() { return module().saveGamepadMappings(); }

// w_Joystick_getAxes (wrap_Joystick.cpp:127-136): every axis's value.
Rice::Array axes(const Joystick &j) {
  Rice::Array values;
  for (const float value : j.getAxes()) {
    values.push(static_cast<double>(value), false);
  }
  return values;
}

// w_Joystick_isDown (wrap_Joystick.cpp:152-182), with its buttons,
// counting from 1, as one Array: whether any is down. Like LÖVE, it raises
// when given none.
bool is_down(const Joystick &j, Rice::Array buttonlist) {
  const Rice::Array list = std::move(buttonlist);
  if (list.size() == 0) {
    throw std::invalid_argument("Missing argument. Name: buttonindex.");
  }
  std::vector<int> buttons;
  buttons.reserve(static_cast<std::size_t>(list.size()));
  // Rice converts an Integer, or a Float, as Lua's luaL_checkinteger
  // takes any number.
  for (const auto item : list) {
    buttons.push_back(Rice::detail::From_Ruby<int>().convert(item.value()) - 1);
  }
  return j.isDown(buttons);
}

// w_Joystick_isGamepadDown (wrap_Joystick.cpp:230-275), with its buttons'
// names as one Array: whether any is down. Each name is checked before the
// joystick is asked, and like LÖVE it raises when given none.
bool is_gamepad_down(const Joystick &j, Rice::Array buttonlist) {
  const Rice::Array list = std::move(buttonlist);
  if (list.size() == 0) {
    throw std::invalid_argument("Missing argument. Name: button.");
  }
  std::vector<Joystick::GamepadButton> buttons;
  buttons.reserve(static_cast<std::size_t>(list.size()));
  for (const auto item : list) {
    const std::string name = Rice::detail::From_Ruby<std::string>().convert(item.value());
    Joystick::GamepadButton button{};
    if (!Joystick::getConstant(name.c_str(), button)) {
      raise_enum_error("gamepad button", name);
    }
    buttons.push_back(button);
  }
  return j.isGamepadDown(buttons);
}

// w_Joystick_getPlayerIndex (wrap_Joystick.cpp:192-198): the player's
// number, counting from 1, or -1 for none, which LÖVE leaves as it is.
int player_index(const Joystick &j) {
  const int index = j.getPlayerIndex();
  return index >= 0 ? index + 1 : index;
}

// w_Joystick_getGamepadMapping (wrap_Joystick.cpp:277-328): the input of
// the joystick that the gamepad axis or button +gpbindstr+ is bound to, as
// the input's type, its index, counting from 1, and for a hat its
// direction, or none when it is bound to nothing.
Rice::Array gamepad_mapping(const Joystick &j, const std::string &gpbindstr) {
  const Joystick::GamepadInput gpinput = gamepad_input(gpbindstr);
  const Joystick::JoystickInput jinput = j.getGamepadMapping(gpinput);

  Rice::Array results;
  if (jinput.type == Joystick::INPUT_TYPE_MAX_ENUM) {
    return results;
  }

  const char *inputtypestr = nullptr;
  if (!Joystick::getConstant(jinput.type, inputtypestr)) {
    throw love::Exception("Unknown joystick input type.");
  }
  results.push(std::string(inputtypestr), false);

  const char *hatstr = nullptr;
  // NOLINTBEGIN(cppcoreguidelines-pro-type-union-access)
  switch (jinput.type) {
  case Joystick::INPUT_TYPE_AXIS:
    results.push(jinput.axis + 1, false);
    return results;
  case Joystick::INPUT_TYPE_BUTTON:
    results.push(jinput.button + 1, false);
    return results;
  case Joystick::INPUT_TYPE_HAT:
    results.push(jinput.hat.index + 1, false);
    if (!Joystick::getConstant(jinput.hat.value, hatstr)) {
      throw love::Exception("Unknown joystick hat.");
    }
    results.push(std::string(hatstr), false);
    return results;
  default:
    throw love::Exception("Unknown joystick input type.");
  }
  // NOLINTEND(cppcoreguidelines-pro-type-union-access)
}

// w_Joystick_setVibration (wrap_Joystick.cpp:348-368): stops the motors
// when given no left one, and otherwise rumbles them, the right as hard as
// the left unless it is given, for +duration+ seconds, -1 for as long as
// the device keeps on. Whether the device took it.
bool set_vibration(Joystick &j, std::optional<double> left, std::optional<double> right,
                   double duration) {
  if (!left.has_value()) {
    // Disable joystick vibration if no argument is given.
    return j.setVibration();
  }
  return j.setVibration(static_cast<float>(*left), static_cast<float>(right.value_or(*left)),
                        static_cast<float>(duration));
}

// w_Joystick_getSensorData (wrap_Joystick.cpp:429-448): the values the
// sensor +sensor_type+ of the gamepad reads.
Rice::Array sensor_data(const Joystick &j, const std::string &sensor_type) {
  Sensor::SensorType type = Sensor::SENSOR_MAX_ENUM;
  if (!Sensor::getConstant(sensor_type.c_str(), type)) {
    raise_enum_error("sensor type", Sensor::getConstants(type), sensor_type);
  }
  Rice::Array values;
  for (const float value : j.getSensorData(type)) {
    values.push(static_cast<double>(value), false);
  }
  return values;
}

// SPDX-SnippetEnd

} // namespace

void define_joystick(const Rice::Module &native) {
  const Rice::Module joystick =
      Rice::define_module_under(native, "Joystick")
          .define_singleton_function("open", &open)
          .define_singleton_function("open?", &is_open)
          .define_singleton_function("joysticks", &joysticks)
          .define_singleton_function("set_gamepad_mapping", &set_gamepad_mapping, Rice::Arg("guid"),
                                     Rice::Arg("button"), Rice::Arg("inputtype"),
                                     Rice::Arg("inputindex"),
                                     Rice::Arg("hatdir") = std::optional<std::string>())
          .define_singleton_function("load_gamepad_mappings", &load_gamepad_mappings,
                                     Rice::Arg("mappings"))
          .define_singleton_function("save_gamepad_mappings", &save_gamepad_mappings);
  define_engine_class<Joystick>(joystick, "Joystick")
      .define_method("axes", &axes)
      .define_method("down?", &is_down, Rice::Arg("buttons"))
      .define_method("gamepad_down?", &is_gamepad_down, Rice::Arg("buttons"))
      .define_method("player_index", &player_index)
      .define_method("gamepad_mapping", &gamepad_mapping, Rice::Arg("button"))
      .define_method("set_vibration", &set_vibration, Rice::Arg("left") = std::optional<double>(),
                     Rice::Arg("right") = std::optional<double>(), Rice::Arg("duration") = -1.0)
      .define_method("sensor_data", &sensor_data, Rice::Arg("sensor_type"));
}

} // namespace lota::native
