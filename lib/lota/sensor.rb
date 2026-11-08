# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The device's motion sensors, translated from love.sensor.
  #
  # A game on a phone or a tablet can be steered by tilting it: a marble
  # rolls downhill, a ship banks. Reading the tilt means turning a sensor
  # on, reading it each frame, and turning it off again to save the
  # battery.
  #
  # Lota::Sensor reads the device's accelerometer and gyroscope through
  # SDL, as LÖVE does. A sensor is off until you turn it on; while it is
  # on, the +sensorupdated+ callback receives each new reading. A desktop
  # computer usually has neither sensor, which #sensor? says before you
  # ask more. A gamepad's own sensors are Lota::Joystick::Joystick's.
  #
  # Use it in your load callback to turn a sensor on, and in your update
  # callback to read it.
  #
  # === Examples
  #
  #   def Lota.load
  #     Lota::Sensor.enabled = :accelerometer, true if Lota::Sensor.sensor?(:accelerometer)
  #   end
  #
  #   def Lota.update(dt)
  #     return unless Lota::Sensor.enabled?(:accelerometer)
  #
  #     x, y, = Lota::Sensor.data(:accelerometer)
  #     @marble.roll(x, y, dt)
  #   end
  module Sensor
    # Whether the device has a sensor of +sensor_type+, matching
    # love.sensor.hasSensor (src/modules/sensor/wrap_Sensor.cpp,
    # w_hasSensor).
    #
    # [sensor_type] +:accelerometer+ or +:gyroscope+; Strings work too.
    #
    # Raises ArgumentError ("Invalid sensor mode ...") for a name LÖVE
    # does not know, and RuntimeError when the sensor module is not open,
    # as when <tt>t.modules.sensor = false</tt>.
    #
    # === Example
    #
    #   Lota::Sensor.sensor?(:gyroscope) # => false
    def self.sensor?(sensor_type)
      Native::Sensor.sensor?(EnumName.of(sensor_type))
    end

    # Whether the sensor of +sensor_type+ is on, matching
    # love.sensor.isEnabled. Every sensor starts off.
    #
    # === Example
    #
    #   Lota::Sensor.enabled?(:accelerometer) # => false
    def self.enabled?(sensor_type)
      Native::Sensor.enabled?(EnumName.of(sensor_type))
    end

    # Turns the sensor of a type on or off, matching
    # love.sensor.setEnabled.
    #
    # [setting] The sensor's type and whether it is on, as an Array (ADR
    #   001, rule 6).
    #
    # Turning on a sensor the device does not have does nothing. Raises
    # RuntimeError when SDL cannot open one it has.
    #
    # === Example
    #
    #   Lota::Sensor.enabled = :accelerometer, true
    def self.enabled=(setting)
      sensor_type, enabled = setting
      Native::Sensor.set_enabled(EnumName.of(sensor_type), enabled)
    end

    # What the sensor of +sensor_type+ reads, as an Array of Floats,
    # matching love.sensor.getData: an accelerometer's x, y, and z in
    # meters per second squared, or a gyroscope's in radians per second.
    #
    # Raises RuntimeError (<tt>"accelerometer" sensor is not enabled</tt>)
    # while the sensor is off.
    #
    # === Example
    #
    #   x, y, z = Lota::Sensor.data(:accelerometer)
    def self.data(sensor_type)
      Native::Sensor.data(EnumName.of(sensor_type))
    end

    # The name SDL gives the sensor of +sensor_type+, matching
    # love.sensor.getName (src/modules/sensor/wrap_Sensor.cpp:81-89), which
    # ADR 001's rule 3 names +name+; or, given no argument, Ruby's own
    # Module#name of this module, +"Lota::Sensor"+, since getName requires
    # its sensor type.
    #
    # Raises RuntimeError while the sensor is off.
    #
    # === Examples
    #
    #   Lota::Sensor.name(:accelerometer) # => "Accelerometer"
    #   Lota::Sensor.name                 # => "Lota::Sensor"
    def self.name(*arguments)
      return super() if arguments.empty?

      sensor_type, = arguments
      raise ArgumentError, "wrong number of arguments (given #{arguments.size}, expected 0..1)" if arguments.size > 1

      Native::Sensor.sensor_name(EnumName.of(sensor_type))
    end
  end
end
