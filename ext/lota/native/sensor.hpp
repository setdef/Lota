// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_SENSOR_HPP
#define LOTA_NATIVE_SENSOR_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds the functions of love.sensor, and the one that opens it, as
// module functions of <native>::Sensor.
void define_sensor(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_SENSOR_HPP
