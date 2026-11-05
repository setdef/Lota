// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/sensor.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "sensor/Sensor.h"
#include "sensor/sdl/Sensor.h"

#include <string>

namespace lota::native {

using love::sensor::Sensor;

namespace {

// luaopen_love_sensor (vendor/love/src/modules/sensor/wrap_Sensor.cpp:
// 108-124) creates SDL's sensor module once; it then lives as long as the
// process, as LÖVE's lives until the game quits. The event module passes
// a sensor's readings only while it is open and the sensor enabled
// (event/sdl/Event.cpp:579-610).
void open() { open_module<Sensor, love::sensor::sdl::Sensor>(love::Module::M_SENSOR); }

// Whether the module is open, as a game asks with "if love.sensor then".
bool is_open() { return love::Module::getInstance<Sensor>(love::Module::M_SENSOR) != nullptr; }

Sensor &module() {
  auto *instance = love::Module::getInstance<Sensor>(love::Module::M_SENSOR);
  if (instance == nullptr) {
    throw love::Exception("Lota::Sensor is not open.");
  }
  return *instance;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from vendor/love/src/modules/sensor/wrap_Sensor.cpp, as cited
// below, and changed to take its arguments from Rice instead of a
// lua_State and to return Ruby values instead of pushing Lua ones.

// luax_checksensortype (lines 31-40): the sensor type +name+ names, or
// ArgumentError, which LÖVE raises naming a "sensor mode".
Sensor::SensorType sensor_type(const std::string &name) {
  Sensor::SensorType type = Sensor::SENSOR_MAX_ENUM;
  if (!Sensor::getConstant(name.c_str(), type)) {
    raise_enum_error("sensor mode", Sensor::getConstants(type), name);
  }
  return type;
}

// w_hasSensor (lines 42-48): whether the device has a sensor of the type.
bool has_sensor(const std::string &name) {
  const Sensor::SensorType type = sensor_type(name);
  return module().hasSensor(type);
}

// w_isEnabled (lines 50-56): whether the sensor of the type is on.
bool is_enabled(const std::string &name) {
  const Sensor::SensorType type = sensor_type(name);
  return module().isEnabled(type);
}

// w_setEnabled (lines 58-65): turns the sensor of the type on or off.
void set_enabled(const std::string &name, bool enabled) {
  const Sensor::SensorType type = sensor_type(name);
  module().setEnabled(type, enabled);
}

// w_getData (lines 67-79): what the sensor of the type reads.
Rice::Array data(const std::string &name) {
  const Sensor::SensorType type = sensor_type(name);
  Rice::Array values;
  for (const float value : module().getData(type)) {
    values.push(static_cast<double>(value), false);
  }
  return values;
}

// w_getName (lines 81-89): the name SDL gives the sensor of the type.
std::string sensor_name(const std::string &name) {
  const Sensor::SensorType type = sensor_type(name);
  return module().getSensorName(type);
}

// SPDX-SnippetEnd

} // namespace

void define_sensor(const Rice::Module &native) {
  Rice::define_module_under(native, "Sensor")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("sensor?", &has_sensor, Rice::Arg("sensor_type"))
      .define_singleton_function("enabled?", &is_enabled, Rice::Arg("sensor_type"))
      .define_singleton_function("set_enabled", &set_enabled, Rice::Arg("sensor_type"),
                                 Rice::Arg("enabled"))
      .define_singleton_function("data", &data, Rice::Arg("sensor_type"))
      .define_singleton_function("sensor_name", &sensor_name, Rice::Arg("sensor_type"));
}

} // namespace lota::native
