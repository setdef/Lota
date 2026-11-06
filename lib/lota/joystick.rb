# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "joystick/joystick"

module Lota
  # Game controllers, translated from love.joystick.
  #
  # Players plug controllers in and pull them out while a game runs, and
  # each brand puts its buttons somewhere else. A game needs the list of
  # controllers connected now, word when one comes or goes, and a way to
  # read any of them by the same button names.
  #
  # Lota::Joystick lists the connected controllers as
  # Lota::Joystick::Joystick objects, and keeps SDL's database of gamepad
  # mappings, which turns a controller's own buttons into an Xbox
  # controller's names (+:a+, +:leftshoulder+). The callbacks
  # +joystickadded+, +joystickremoved+, +joystickpressed+,
  # +joystickreleased+, +joystickaxis+, +joystickhat+, +gamepadpressed+,
  # +gamepadreleased+, and +gamepadaxis+ receive the Joystick first.
  #
  # Use it to find controllers when the game starts, and to teach SDL a
  # controller it does not know.
  #
  # === Examples
  #
  #   def Lota.load
  #     @pad = Lota::Joystick.joysticks.find(&:gamepad?)
  #   end
  #
  #   def Lota.gamepadpressed(joystick, button)
  #     jump if button == :a
  #   end
  #
  #   Lota::Joystick.load_gamepad_mappings("gamecontrollerdb.txt")
  module Joystick
    # The controllers connected now, as an Array of
    # Lota::Joystick::Joystick in the order they connected, matching
    # love.joystick.getJoysticks (src/modules/joystick/
    # wrap_JoystickModule.cpp, w_getJoysticks).
    #
    # The module lists the controllers already connected when it opens,
    # and Lota's loop adds and removes the others as it handles events.
    # Raises RuntimeError when the joystick module is not open, as when
    # <tt>t.modules.joystick = false</tt>.
    #
    # === Example
    #
    #   Lota::Joystick.joysticks # => [#<Lota::Joystick::Joystick ...>]
    def self.joysticks
      Native::Joystick.joysticks.map { |native| self::Joystick.from_native(native) }
    end

    # How many controllers are connected, matching
    # love.joystick.getJoystickCount.
    #
    # === Example
    #
    #   Lota::Joystick.joystick_count # => 0
    def self.joystick_count
      Native::Joystick.joystick_count
    end

    # Whether controllers send events while the window does not have
    # focus, matching love.joystick.setBackgroundEvents; +false+ by
    # default.
    #
    # === Example
    #
    #   Lota::Joystick.background_events = true
    def self.background_events=(enable)
      Native::Joystick.set_background_events(enable)
    end

    # Whether controllers send events while the window does not have
    # focus, matching love.joystick.hasBackgroundEvents.
    #
    # === Example
    #
    #   Lota::Joystick.background_events? # => false
    def self.background_events?
      Native::Joystick.background_events?
    end

    # Binds one gamepad axis or button of every controller with the GUID
    # +guid+ to one of its inputs, matching love.joystick.setGamepadMapping
    # (src/modules/joystick/wrap_JoystickModule.cpp, w_setGamepadMapping).
    # Returns whether SDL took the mapping.
    #
    # [guid] String GUID of 32 hexadecimal digits, as
    #   Lota::Joystick::Joystick#guid gives it. A mapping applies to every
    #   controller of that model, not to one Joystick.
    # [button] The gamepad axis or button to bind, such as +:a+ or
    #   +:leftx+.
    # [inputtype] +:axis+, +:button+, or +:hat+: the kind of the
    #   controller's own input.
    # [inputindex] Integer index of that input, counting from 1.
    # [hatdir] For a hat, its direction: +:c+, +:u+, +:r+, +:d+, +:l+,
    #   +:ru+, +:rd+, +:lu+, or +:ld+. Other kinds ignore it.
    #
    # Raises ArgumentError for a name LÖVE does not know, and when a hat
    # has no direction, and RuntimeError ("Invalid joystick GUID: ...")
    # for a GUID that is not 32 characters. A mapping SDL refuses returns
    # +false+, as LÖVE returns it (ADR 001, rule 7).
    #
    # === Example
    #
    #   Lota::Joystick.set_gamepad_mapping("030000005e040000130b000011050000", :a, :button, 1)
    #   Lota::Joystick.set_gamepad_mapping(guid, :dpup, :hat, 1, :u)
    def self.set_gamepad_mapping(guid, button, inputtype, inputindex, hatdir = nil)
      Native::Joystick.set_gamepad_mapping(guid, EnumName.of(button), EnumName.of(inputtype), inputindex,
        hatdir && EnumName.of(hatdir))
    end

    # Adds gamepad mappings to SDL's database, from a file or a String in
    # SDL's format, one mapping a line, matching
    # love.joystick.loadGamepadMappings.
    #
    # [mappings] The name of a file Lota::Filesystem finds, such as a
    #   community gamecontrollerdb.txt in the game's folder, or the
    #   mappings themselves.
    #
    # A name Lota::Filesystem finds no file for is read as mappings, so a
    # misspelled file name raises RuntimeError for its text, as in LÖVE.
    #
    # === Example
    #
    #   Lota::Joystick.load_gamepad_mappings("gamecontrollerdb.txt")
    def self.load_gamepad_mappings(mappings)
      Native::Joystick.load_gamepad_mappings(mappings)
    end

    # Every gamepad mapping this program has used or set, in SDL's format,
    # one a line, matching love.joystick.saveGamepadMappings. With a file
    # name it also writes them to that file in the save directory, as
    # Lota::Filesystem.write does, and returns them all the same.
    #
    # === Example
    #
    #   Lota::Joystick.save_gamepad_mappings("mappings.txt")
    def self.save_gamepad_mappings(filename = nil)
      mappings = Native::Joystick.save_gamepad_mappings
      Filesystem.write(filename, mappings) if filename
      mappings
    end

    # The gamepad mapping SDL has for controllers with the GUID +guid+, in
    # SDL's format, or +nil+ when it has none, matching
    # love.joystick.getGamepadMappingString.
    #
    # === Example
    #
    #   Lota::Joystick.gamepad_mapping_string("faker") # => nil
    def self.gamepad_mapping_string(guid)
      Native::Joystick.gamepad_mapping_string(guid)
    end
  end
end
