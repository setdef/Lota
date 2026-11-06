# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Sensor answers from LÖVE's own sensor module
# (vendor/love/src/modules/sensor/sdl/Sensor.cpp), beyond what Lövetest's
# tests check (test/lovetest/tests/sensor.rb): every sensor starts off, a
# sensor that is off raises when read, and the names are checked as
# luax_checksensortype checks them (wrap_Sensor.cpp:31-40). A desktop
# computer has no sensor, so turning one on there does nothing.
class SensorModuleTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def teardown
    %i[accelerometer gyroscope].each { |sensor_type| Lota::Sensor.enabled = sensor_type, false }
  end

  def test_a_sensor_that_is_off_raises_when_read
    %i[accelerometer gyroscope].each do |sensor_type|
      refute Lota::Sensor.enabled?(sensor_type)
      error = assert_raises(RuntimeError) { Lota::Sensor.data(sensor_type) }
      assert_equal %("#{sensor_type}" sensor is not enabled), error.message
      error = assert_raises(RuntimeError) { Lota::Sensor.get_name(sensor_type) }
      assert_equal %("#{sensor_type}" sensor is not enabled), error.message
    end
  end

  # Sensor::setEnabled opens a sensor of the type only where SDL lists one
  # (sdl/Sensor.cpp:66-95), so on a machine without it the sensor stays off.
  def test_turning_on_a_sensor_turns_it_on_where_the_device_has_one
    %i[accelerometer gyroscope].each do |sensor_type|
      Lota::Sensor.enabled = sensor_type, true

      assert_equal Lota::Sensor.sensor?(sensor_type), Lota::Sensor.enabled?(sensor_type)
      assert_equal 3, Lota::Sensor.data(sensor_type).size if Lota::Sensor.enabled?(sensor_type)
    end
  end

  def test_a_sensor_type_lota_does_not_know_raises
    error = assert_raises(ArgumentError) { Lota::Sensor.sensor?(:compass) }
    assert_equal "Invalid sensor mode 'compass', expected one of: 'accelerometer', 'gyroscope'", error.message
    assert_raises(ArgumentError) { Lota::Sensor.enabled = :compass, true }
  end

  def test_lota_sensor_is_the_module
    assert_same Lota::Sensor, lota.sensor
  end
end
