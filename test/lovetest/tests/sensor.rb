# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.sensor tests (vendor/love/testing/tests/sensor.lua),
# translated to Ruby by the rules of doc/contributors/design/translation.md, all
# four. Three of them skip where the machine has neither an accelerometer nor a
# gyroscope, as Lövetest skips them, which on a desktop computer is usual. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/sensor_test.rb) and under lota run (test/lovetest/game).
class SensorTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from the helpers of Lövetest's sensor tests
  # (vendor/love/testing/tests/sensor.lua:11-47): setEnabled becomes the
  # writer enabled= of the type and the setting (rule 6), isEnabled
  # enabled? (rule 8), getData data (rule 3), whose three values are an
  # Array (rule 4), and getName name (rule 3). Lua's pcall, which
  # returns false when the call raised, becomes a rescue.
  def check_is_enabled(sensor_type)
    Lota::Sensor.enabled = sensor_type, true
    assert_equal(true, Lota::Sensor.enabled?(sensor_type), "check #{sensor_type} enabled")
    Lota::Sensor.enabled = sensor_type, false
    assert_equal(false, Lota::Sensor.enabled?(sensor_type), "check #{sensor_type} disabled")
  end

  def check_get_name(sensor_type)
    Lota::Sensor.enabled = sensor_type, true
    ok, name = attempt { Lota::Sensor.name(sensor_type) }
    assert_equal(true, ok, "check sensor.getName(\"#{sensor_type}\") success")
    assert_equal(String, name.class, "check sensor.getName(\"#{sensor_type}\") return value type")

    Lota::Sensor.enabled = sensor_type, false
    ok, = attempt { Lota::Sensor.name(sensor_type) }
    assert_equal(false, ok, "check sensor.getName(\"#{sensor_type}\") errors when disabled")
  end

  def check_get_data(sensor_type)
    Lota::Sensor.enabled = sensor_type, true
    ok, data = attempt { Lota::Sensor.data(sensor_type) }
    assert_equal(true, ok, "check sensor.getData(\"#{sensor_type}\") success")
    if ok
      x, y, z = data
      assert_not_nil(x)
      assert_not_nil(y)
      assert_not_nil(z)
    end

    Lota::Sensor.enabled = sensor_type, false
    ok, = attempt { Lota::Sensor.data(sensor_type) }
    assert_equal(false, ok, "check sensor.getData(\"#{sensor_type}\") errors when disabled")
  end

  # Translated to Ruby from love.test.sensor.hasSensor, isEnabled,
  # getName, and getData (sensor.lua:57-110): hasSensor becomes sensor?
  # (rule 8), and the sensor types symbols (rule 9).
  def test_has_sensor
    # but we can make sure that the SensorTypes can be passed
    accelerometer = Lota::Sensor.sensor?(:accelerometer)
    gyroscope = Lota::Sensor.sensor?(:gyroscope)
    assert_not_nil(accelerometer)
    assert_not_nil(gyroscope)
  end

  def test_is_enabled
    each_sensor { |sensor_type| check_is_enabled(sensor_type) }
  end

  def test_get_name
    each_sensor { |sensor_type| check_get_name(sensor_type) }
  end

  def test_get_data
    each_sensor { |sensor_type| check_get_data(sensor_type) }
  end

  # Lövetest's check, in each test, for the sensors this system has: each
  # one it has, or the skip when it has neither.
  def each_sensor
    accelerometer = Lota::Sensor.sensor?(:accelerometer)
    gyroscope = Lota::Sensor.sensor?(:gyroscope)

    return skip("neither accelerometer nor gyroscope are supported in this system") unless accelerometer || gyroscope

    yield :accelerometer if accelerometer
    yield :gyroscope if gyroscope
  end
  # SPDX-SnippetEnd

  # Lua's pcall: +true+ and the block's value, or +false+ when the block
  # raised RuntimeError, as the engine raises for a sensor that is off.
  def attempt
    [true, yield]
  rescue RuntimeError
    [false, nil]
  end
end
