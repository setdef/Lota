# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Joystick
    # One game controller, matching LÖVE's Joystick
    # (src/modules/joystick/wrap_Joystick.cpp).
    #
    # A game played with a controller asks two kinds of question: what the
    # device is (its name, how many buttons and sticks it has, whether it
    # rumbles) and what the player is doing with it right now. Controllers
    # differ in where their buttons are, so a game that reads button 3
    # finds a different button on every brand.
    #
    # A Joystick answers both, and for a controller SDL knows as a
    # gamepad, it also answers by the names of an Xbox controller's
    # buttons and sticks (+:a+, +:leftx+), wherever the device puts them.
    # The joystick callbacks receive the same Joystick each time, so it
    # serves as a Hash key for the player who holds it.
    #
    # Use Lota::Joystick.joysticks or the +joystickadded+ callback to get
    # one, and read it in your update callback.
    #
    # === Examples
    #
    #   def Lota.joystickadded(joystick)
    #     @players[joystick] = Player.new
    #   end
    #
    #   def Lota.update(dt)
    #     @players.each do |joystick, player|
    #       player.move(joystick.gamepad_axis(:leftx), joystick.gamepad_axis(:lefty))
    #       player.jump if joystick.gamepad_down?(:a)
    #     end
    #   end
    #
    #   def Lota.gamepadpressed(joystick, button)
    #     joystick.set_vibration(0.5, 0.5, 0.2) if button == :x
    #   end
    class Joystick < Object
      # The Joystick that wraps +native+, the same one each time while it
      # lives, as LÖVE gives Lua the same userdata for the same joystick.
      # :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        joystick = allocate
        joystick.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, joystick)
        joystick
      end

      # Whether the device is still connected, matching
      # Joystick:isConnected. A Joystick outlives its device: when a device
      # with the same GUID connects again, LÖVE gives it the same Joystick.
      #
      # === Example
      #
      #   joystick.connected? # => true
      def connected?
        @native.connected?
      end

      # The device's name, as SDL reports it, matching Joystick:getName.
      #
      # === Example
      #
      #   joystick.name # => "Xbox Wireless Controller"
      def name
        @native.name
      end

      # The joystick's id, counting from 1, and SDL's instance id of its
      # device, counting from 1, or +nil+ once it is disconnected, as an
      # Array, matching Joystick:getID. The first stays the same for the
      # life of the program, even across reconnection.
      #
      # === Example
      #
      #   id, instance_id = joystick.id # => [1, 1]
      def id
        @native.id
      end

      # The device's GUID, a String of 32 hexadecimal digits that is the
      # same for every device of its model, matching Joystick:getGUID. The
      # gamepad mapping functions of Lota::Joystick take it.
      #
      # === Example
      #
      #   joystick.guid # => "030000005e040000130b000011050000"
      def guid
        @native.guid
      end

      # The device's USB vendor id, product id, and product version, as an
      # Array of Integers, matching Joystick:getDeviceInfo; zeros where SDL
      # knows none.
      #
      # === Example
      #
      #   vendor, product, version = joystick.device_info
      def device_info
        @native.device_info
      end

      # The device's power, as an Array of its state and its battery's
      # percent, matching Joystick:getDevicePowerInfo: +:unknown+,
      # +:onbattery+, +:nobattery+, +:charging+, or +:charged+, and an
      # Integer, or +nil+ when SDL cannot tell.
      #
      # === Example
      #
      #   state, percent = joystick.device_power_info # => [:onbattery, 80]
      def device_power_info
        state, percent = @native.device_power_info
        [state.to_s.to_sym, percent.is_a?(Integer) ? percent : nil]
      end

      # How the device is connected, matching
      # Joystick:getDeviceConnectionState: +:unknown+, +:wired+, or
      # +:wireless+.
      #
      # === Example
      #
      #   joystick.device_connection_state # => :wireless
      def device_connection_state
        @native.device_connection_state.to_sym
      end

      # The kind of device, matching Joystick:getJoystickType: +:unknown+,
      # +:gamepad+, +:wheel+, +:arcadestick+, +:flightstick+, +:dancepad+,
      # +:guitar+, +:drumkit+, +:arcadepad+, or +:throttle+.
      #
      # === Example
      #
      #   joystick.joystick_type # => :gamepad
      def joystick_type
        @native.joystick_type.to_sym
      end

      # How many axes the device has, matching Joystick:getAxisCount.
      #
      # === Example
      #
      #   joystick.axis_count # => 6
      def axis_count
        @native.axis_count
      end

      # How many buttons the device has, matching Joystick:getButtonCount.
      #
      # === Example
      #
      #   joystick.button_count # => 15
      def button_count
        @native.button_count
      end

      # How many hats (directional pads) the device has, matching
      # Joystick:getHatCount.
      #
      # === Example
      #
      #   joystick.hat_count # => 1
      def hat_count
        @native.hat_count
      end

      # The value of axis +axis+, counting from 1, from -1 to 1, matching
      # Joystick:getAxis; 0 for an axis the device does not have.
      #
      # === Example
      #
      #   joystick.axis(1) # => -0.25
      def axis(axis)
        @native.axis(axis)
      end

      # The value of every axis, in order, as an Array of Floats, matching
      # Joystick:getAxes.
      #
      # === Example
      #
      #   x, y = joystick.axes
      def axes
        @native.axes
      end

      # The direction hat +hat+, counting from 1, points in, matching
      # Joystick:getHat: +:c+ (centered), +:u+, +:r+, +:d+, +:l+, +:ru+,
      # +:rd+, +:lu+, or +:ld+.
      #
      # === Example
      #
      #   joystick.hat(1) # => :c
      def hat(hat)
        @native.hat(hat).to_sym
      end

      # Whether any of +buttons+, counting from 1, is down, matching
      # Joystick:isDown.
      #
      # [buttons] Integers, or one Array of them, as LÖVE takes a table.
      #
      # Raises ArgumentError when given no button, as LÖVE does.
      #
      # === Example
      #
      #   joystick.down?(1, 2)
      def down?(*buttons)
        @native.down?(list(buttons))
      end

      # Sets the player number the device shows, counting from 1, as on an
      # Xbox controller's ring of lights, matching Joystick:setPlayerIndex.
      #
      # === Example
      #
      #   joystick.player_index = 2
      def player_index=(index)
        @native.set_player_index(index)
      end

      # The player number the device shows, counting from 1, or -1 for
      # none, matching Joystick:getPlayerIndex.
      #
      # === Example
      #
      #   joystick.player_index # => 2
      def player_index
        @native.player_index
      end

      # Whether SDL knows the device as a gamepad, with buttons and sticks
      # where an Xbox controller has them, matching Joystick:isGamepad.
      #
      # === Example
      #
      #   joystick.gamepad? # => true
      def gamepad?
        @native.gamepad?
      end

      # The gamepad's model, matching Joystick:getGamepadType, such as
      # +:xbox360+, +:ps5+, or +:unknown+.
      #
      # === Example
      #
      #   joystick.gamepad_type # => :xboxone
      def gamepad_type
        @native.gamepad_type.to_sym
      end

      # The value of the gamepad axis +axis+, matching
      # Joystick:getGamepadAxis: from -1 to 1 for a stick, and from 0 to 1
      # for a trigger.
      #
      # [axis] +:leftx+, +:lefty+, +:rightx+, +:righty+, +:triggerleft+, or
      #   +:triggerright+; Strings work too.
      #
      # Raises ArgumentError ("Invalid gamepad axis: ...") for a name LÖVE
      # does not know.
      #
      # === Example
      #
      #   joystick.gamepad_axis(:leftx) # => 0.5
      def gamepad_axis(axis)
        @native.gamepad_axis(EnumName.of(axis))
      end

      # Whether any of the gamepad's +buttons+ is down, matching
      # Joystick:isGamepadDown.
      #
      # [buttons] Symbols such as +:a+, +:b+, +:x+, +:y+, +:back+,
      #   +:guide+, +:start+, +:leftstick+, +:rightstick+,
      #   +:leftshoulder+, +:rightshoulder+, +:dpup+, +:dpdown+,
      #   +:dpleft+, or +:dpright+, or one Array of them; Strings work too.
      #
      # Raises ArgumentError for a name LÖVE does not know, and when given
      # none.
      #
      # === Example
      #
      #   joystick.gamepad_down?(:a, :b)
      def gamepad_down?(*buttons)
        @native.gamepad_down?(list(buttons).map { |button| EnumName.of(button) })
      end

      # The input of the device that the gamepad axis or button +button+
      # is bound to, matching Joystick:getGamepadMapping: an Array of the
      # input's type (+:axis+, +:button+, or +:hat+), its index, counting
      # from 1, and for a hat its direction, or an empty Array when nothing
      # is bound to it.
      #
      # [button] A gamepad axis or button, as #gamepad_axis and
      #   #gamepad_down? name them.
      #
      # === Example
      #
      #   type, index = joystick.gamepad_mapping(:a) # => [:button, 1]
      def gamepad_mapping(button)
        type, index, hat = @native.gamepad_mapping(EnumName.of(button))
        return [] unless type.is_a?(String) && index.is_a?(Integer)

        hat.is_a?(String) ? [type.to_sym, index, hat.to_sym] : [type.to_sym, index]
      end

      # The device's gamepad mapping in SDL's format, or +nil+ when it has
      # none, matching Joystick:getGamepadMappingString.
      #
      # === Example
      #
      #   joystick.gamepad_mapping_string # => "030000005e04...,Xbox Controller,a:b0,..."
      def gamepad_mapping_string
        @native.gamepad_mapping_string
      end

      # Whether the device can rumble, matching
      # Joystick:isVibrationSupported.
      #
      # === Example
      #
      #   joystick.vibration_supported? # => true
      def vibration_supported?
        @native.vibration_supported?
      end

      # Rumbles the device's left and right motors, from 0 to 1, for
      # +duration+ seconds, or stops them when +left+ is +nil+, matching
      # Joystick:setVibration. Returns whether the device took it.
      #
      # [left] Float strength of the left motor, or +nil+ to stop.
      # [right] Float strength of the right motor; +left+'s when +nil+.
      # [duration] Float seconds, or -1, the default, to rumble until told
      #   otherwise.
      #
      # A device that cannot rumble returns +false+ rather than raising,
      # so a game falls back on its own (ADR 001, rule 7).
      #
      # === Example
      #
      #   joystick.set_vibration(1, 1, 0.25)
      #   joystick.set_vibration # stops it
      def set_vibration(left = nil, right = nil, duration = nil)
        return @native.set_vibration if left.nil?

        @native.set_vibration(left, right, duration || -1.0)
      end

      # The strengths of the left and right motors, matching
      # Joystick:getVibration, which LÖVE 12 deprecated: it always returns
      # zeros.
      #
      # === Example
      #
      #   joystick.vibration # => [0.0, 0.0]
      def vibration
        @native.vibration
      end

      # Whether the gamepad has the sensor +sensor_type+, matching
      # Joystick:hasSensor.
      #
      # [sensor_type] +:accelerometer+ or +:gyroscope+; Strings work too.
      #
      # Raises ArgumentError for a name LÖVE does not know.
      #
      # === Example
      #
      #   joystick.sensor?(:gyroscope) # => true
      def sensor?(sensor_type)
        @native.sensor?(EnumName.of(sensor_type))
      end

      # Whether the gamepad's sensor +sensor_type+ is on, matching
      # Joystick:isSensorEnabled.
      #
      # === Example
      #
      #   joystick.sensor_enabled?(:accelerometer) # => false
      def sensor_enabled?(sensor_type)
        @native.sensor_enabled?(EnumName.of(sensor_type))
      end

      # Turns the gamepad's sensor on or off, matching
      # Joystick:setSensorEnabled. A sensor sends the
      # +joysticksensorupdated+ callback only while it is on.
      #
      # [setting] The sensor's type and whether it is on, as an Array
      #   (ADR 001, rule 6).
      #
      # Raises RuntimeError when the gamepad has no such sensor.
      #
      # === Example
      #
      #   joystick.sensor_enabled = :accelerometer, true
      def sensor_enabled=(setting)
        sensor_type, enabled = setting
        @native.set_sensor_enabled(EnumName.of(sensor_type), enabled)
      end

      # What the gamepad's sensor +sensor_type+ reads, as an Array of
      # Floats, matching Joystick:getSensorData: an accelerometer's x, y,
      # and z in meters per second squared, or a gyroscope's in radians
      # per second.
      #
      # Raises RuntimeError when the sensor is off.
      #
      # === Example
      #
      #   x, y, z = joystick.sensor_data(:accelerometer)
      def sensor_data(sensor_type)
        @native.sensor_data(EnumName.of(sensor_type))
      end

      # The joystick's place in Lota::Joystick.joysticks, counting from 1,
      # or +nil+ once it is disconnected, matching
      # Joystick:getConnectedIndex.
      #
      # === Example
      #
      #   joystick.connected_index # => 1
      def connected_index
        @native.connected_index
      end

      # +buttons+, or the one Array among them, as LÖVE reads its buttons
      # from its arguments or from one table. :nodoc:
      private def list(buttons)
        first = buttons.first
        first.is_a?(Array) ? first : buttons
      end
    end
  end
end
