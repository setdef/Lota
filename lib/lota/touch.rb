# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # Fingers on a touchscreen, translated from love.touch.
  #
  # A game on a phone or a tablet has no pointer: the player puts one or
  # more fingers on the glass, drags them, and lifts them. The game has to
  # follow each finger on its own, from the frame it lands to the frame
  # it lifts, or a pinch reads as two taps.
  #
  # Lota::Touch answers from the list of touches LÖVE's event module keeps
  # while Lota's loop handles events, and the +touchpressed+,
  # +touchmoved+, and +touchreleased+ callbacks tell you when a finger
  # lands, moves, or lifts. Each touch has an id, an Integer that stays
  # the same while the finger stays down and that the callbacks receive
  # first.
  #
  # A touchscreen's positions are in the window's coordinates, scaled as
  # Lota::Graphics draws, the units of Lota::Mouse.position and of
  # Lota::Graphics.width. A touchpad's are its own, from 0 to 1 across
  # it.
  #
  # Use it to follow fingers in your update callback; use the callbacks
  # to react to a tap the moment it happens.
  #
  # === Examples
  #
  #   def Lota.touchpressed(id, x, y)
  #     @popped << id if @bubble.contains?(x, y)
  #   end
  #
  #   def Lota.draw
  #     Lota::Touch.touches.each do |id|
  #       x, y = Lota::Touch.position(id)
  #       Lota::Graphics.circle(:fill, x, y, 20)
  #     end
  #   end
  #
  # SDL also tells the game about a touch as a mouse: the first finger
  # down presses the left button, and +mousepressed+, +mousemoved+, and
  # +mousereleased+ receive +true+ for their +istouch+ argument. A game
  # that handles both skips the mouse callbacks when +istouch+ is true.
  # On iOS and Android SDL turns a mouse into touches too, which the
  # touch callbacks receive with +true+ for their last argument, +mouse+.
  #
  # On a Mac, a trackpad reports no touches unless <tt>t.trackpadtouch =
  # true</tt>; then it reports them as a +:touchpad+ whose positions run
  # from 0 to 1.
  module Touch
    # The ids of the touches now pressed, as an Array of Integers, matching
    # love.touch.getTouches (src/modules/touch/wrap_Touch.cpp, w_getTouches).
    #
    # [filter] Symbol naming the kind of device to list touches of:
    #   +:touchscreen+, +:touchpad+, or +:touchpadrelative+; Strings work
    #   too. Lists every touch when +nil+.
    #
    # The ids come in the order their fingers landed. An id is unique only
    # while its finger stays down: one that lifts may give its id to the
    # next. The list is the one Lota's loop brought up to date when it last
    # handled events. Raises ArgumentError ("Invalid touch device type
    # ...") for a name LÖVE does not know, and RuntimeError when the touch
    # module is not open, as when <tt>t.modules.touch = false</tt>.
    #
    # === Example
    #
    #   Lota::Touch.touches # => [105553116266496, 105553116266752]
    #   Lota::Touch.touches(:touchscreen).size # => 2
    def self.touches(filter = nil)
      Native::Touch.touches(filter&.to_s)
    end

    # Where the touch +id+ is, as an Array of x and y, matching
    # love.touch.getPosition (src/modules/touch/wrap_Touch.cpp,
    # w_getPosition).
    #
    # [id] Integer id of a touch now pressed, from #touches or a touch
    #   callback.
    #
    # A touchscreen's position is in the window's coordinates, scaled as
    # Lota::Graphics draws; a touchpad's runs from 0 to 1 across it. Raises
    # RuntimeError ("Invalid active touch ID: ...") once the finger has
    # lifted, TypeError for an id that is not an Integer, as LÖVE raises
    # for anything but a touch id, and RuntimeError when the touch module
    # is not open.
    #
    # === Example
    #
    #   x, y = Lota::Touch.position(id) # => [200.5, 120.0]
    def self.position(id)
      Native::Touch.position(touch_id(id))
    end

    # How hard the touch +id+ presses, as a Float, matching
    # love.touch.getPressure (src/modules/touch/wrap_Touch.cpp,
    # w_getPressure).
    #
    # [id] Integer id of a touch now pressed.
    #
    # SDL gives the force iOS measures, and 1 for a Mac's trackpad. Raises
    # as #position does.
    #
    # === Example
    #
    #   Lota::Touch.pressure(id) # => 1.0
    def self.pressure(id)
      Native::Touch.pressure(touch_id(id))
    end

    # The kind of device the touch +id+ is on, as a Symbol, matching
    # love.touch.getDeviceType (src/modules/touch/wrap_Touch.cpp,
    # w_getDeviceType): +:touchscreen+, +:touchpad+, or
    # +:touchpadrelative+.
    #
    # [id] Integer id of a touch now pressed.
    #
    # Raises as #position does.
    #
    # === Example
    #
    #   Lota::Touch.device_type(id) # => :touchscreen
    def self.device_type(id)
      Native::Touch.device_type(touch_id(id)).to_sym
    end

    # Whether SDL made the touch +id+ from a mouse, matching
    # love.touch.isMouse (src/modules/touch/wrap_Touch.cpp, w_isMouse).
    #
    # [id] Integer id of a touch now pressed.
    #
    # SDL makes touches from a mouse on iOS and Android, so that a game
    # written for fingers works with a mouse there too. Raises as #position
    # does.
    #
    # === Example
    #
    #   Lota::Touch.mouse?(id) # => false
    def self.mouse?(id)
      Native::Touch.mouse?(touch_id(id))
    end

    # +id+, or TypeError unless it is an Integer, as LÖVE's
    # luax_checktouchid raises for anything but the light userdata it
    # pushes (wrap_Touch.cpp:36-42), which Lota gives Ruby as an Integer.
    # :nodoc:
    private_class_method def self.touch_id(id)
      case id
      when Integer then id
      else raise TypeError, "wrong argument type #{id.class} (expected Integer)"
      end
    end
  end
end
