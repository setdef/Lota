# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "mouse/cursor"

module Lota
  # The mouse, translated from love.mouse.
  #
  # A game that drags, aims, or points needs to know where the pointer is
  # right now, not only where it was when a button went down, and may want
  # to change the pointer's shape while it does.
  #
  # Lota::Mouse answers from the same state LÖVE reads, which Lota's loop
  # brings up to date each frame when it handles events, and changes the
  # pointer through LÖVE's own mouse module. Positions are in the window's
  # coordinates, scaled as Lota::Graphics draws.
  #
  # Use it in your update callback to follow the pointer, and the
  # +mousepressed+ and +mousereleased+ callbacks for clicks.
  #
  # === Example
  #
  #   def Lota.mousepressed(x, y, button)
  #     @drag_from = x
  #     Lota::Mouse.cursor = Lota::Mouse.system_cursor(:sizewe)
  #   end
  #
  #   def Lota.update(dt)
  #     @offset = Lota::Mouse.x - @drag_from if @drag_from
  #   end
  module Mouse
    # One of the operating system's own pointer shapes, matching
    # love.mouse.getSystemCursor (src/modules/mouse/wrap_Mouse.cpp,
    # w_getSystemCursor).
    #
    # [ctype] Symbol naming the shape by LÖVE's names: +:arrow+, +:ibeam+,
    #   +:wait+, +:crosshair+, +:waitarrow+, +:sizenwse+, +:sizenesw+,
    #   +:sizewe+, +:sizens+, +:sizeall+, +:no+, or +:hand+; Strings work
    #   too.
    #
    # LÖVE makes each shape once and hands out the same cursor afterward.
    # Raises ArgumentError ("Invalid system cursor type: ...") for a name
    # LÖVE does not know, and RuntimeError when the mouse module is not
    # open, as when <tt>t.modules.mouse = false</tt>.
    #
    # === Example
    #
    #   hand = Lota::Mouse.system_cursor(:hand)
    def self.system_cursor(ctype)
      Cursor.from_native(Native::Mouse.system_cursor(ctype.to_s))
    end

    # Shows +cursor+ as the mouse pointer, or the system's default pointer
    # when +cursor+ is +nil+, matching love.mouse.setCursor
    # (src/modules/mouse/wrap_Mouse.cpp, w_setCursor).
    #
    # [cursor] Lota::Mouse::Cursor, or +nil+.
    #
    # <tt>cursor = nil</tt> is LÖVE's setCursor() with no arguments.
    # Raises TypeError for anything but a Cursor or +nil+, and
    # RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.cursor = Lota::Mouse.system_cursor(:hand)
    #   Lota::Mouse.cursor = nil # back to the arrow
    def self.cursor=(cursor)
      if cursor.nil?
        Native::Mouse.set_cursor
      else
        raise TypeError, "wrong argument type #{cursor.class} (expected Lota::Mouse::Cursor)" unless cursor.is_a?(Cursor)

        Native::Mouse.set_cursor(cursor.native)
      end
    end

    # The pointer's horizontal position in the window, as a Float,
    # matching love.mouse.getX (src/modules/mouse/wrap_Mouse.cpp, w_getX).
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.x # => 412.0
    def self.x
      Native::Mouse.x
    end

    # The pointer's vertical position in the window, as a Float,
    # matching love.mouse.getY (src/modules/mouse/wrap_Mouse.cpp, w_getY).
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.y # => 230.0
    def self.y
      Native::Mouse.y
    end

    # The pointer's position in the window, as an Array of two Floats,
    # matching love.mouse.getPosition (src/modules/mouse/wrap_Mouse.cpp,
    # w_getPosition), whose two values rule 4 of ADR 001 makes one Array.
    #
    # A position outside the window, as while the player drags out of it,
    # is moved to its nearest edge, as LÖVE moves it. Raises RuntimeError
    # when the mouse module is not open.
    #
    # === Example
    #
    #   x, y = Lota::Mouse.position # => [412.0, 230.0]
    def self.position
      Native::Mouse.position
    end

    # Moves the pointer across the window, keeping its height, matching
    # love.mouse.setX (src/modules/mouse/wrap_Mouse.cpp, w_setX).
    #
    # [x] Float or Integer position in the window.
    #
    # LÖVE moves the system's pointer itself, so the player sees it jump.
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.x = 10
    def self.x=(x)
      Native::Mouse.set_x(x)
    end

    # Moves the pointer up or down the window, keeping its place across,
    # matching love.mouse.setY (src/modules/mouse/wrap_Mouse.cpp, w_setY).
    #
    # [y] Float or Integer position in the window.
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.y = 10
    def self.y=(y)
      Native::Mouse.set_y(y)
    end

    # Moves the pointer to a place in the window, matching
    # love.mouse.setPosition (src/modules/mouse/wrap_Mouse.cpp,
    # w_setPosition), whose two values rule 6 of ADR 001 makes one Array.
    #
    # [position] An Array of the Float or Integer position across and
    #   down the window.
    #
    # LÖVE moves the system's pointer itself, which also reports the move
    # to the game, as a mousemoved event. Raises RuntimeError when the
    # mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.position = 320, 240
    def self.position=(position)
      x, y = position
      Native::Mouse.set_position(x, y)
    end

    # Whether any of +buttons+ is held down, matching love.mouse.isDown
    # (src/modules/mouse/wrap_Mouse.cpp, w_isDown).
    #
    # [buttons] Integer buttons, as LÖVE numbers them: 1 the left, 2 the
    #   right, and 3 the middle; LÖVE passes none of a number less than 1.
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.down?(1, 2) # => false
    def self.down?(*buttons)
      Native::Mouse.down?(buttons)
    end

    # Shows the pointer when +visible+ is truthy and hides it otherwise,
    # matching love.mouse.setVisible (src/modules/mouse/wrap_Mouse.cpp,
    # w_setVisible).
    #
    # Raises TypeError unless +visible+ is +true+ or +false+, and
    # RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.visible = false
    def self.visible=(visible)
      Native::Mouse.set_visible(visible)
    end

    # Whether the pointer is shown, matching love.mouse.isVisible
    # (src/modules/mouse/wrap_Mouse.cpp, w_isVisible).
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.visible? # => true
    def self.visible?
      Native::Mouse.visible?
    end

    # Keeps the pointer inside the window when +grabbed+ is +true+, and
    # lets it leave when +false+, matching love.mouse.setGrabbed
    # (src/modules/mouse/wrap_Mouse.cpp, w_setGrabbed).
    #
    # Raises TypeError unless +grabbed+ is +true+ or +false+, and
    # RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.grabbed = true
    def self.grabbed=(grabbed)
      Native::Mouse.set_grabbed(grabbed)
    end

    # Whether the pointer is kept inside the window, matching
    # love.mouse.isGrabbed (src/modules/mouse/wrap_Mouse.cpp, w_isGrabbed).
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.grabbed? # => false
    def self.grabbed?
      Native::Mouse.grabbed?
    end

    # Turns relative mode on when +relative+ is +true+, and off when
    # +false+, matching love.mouse.setRelativeMode
    # (src/modules/mouse/wrap_Mouse.cpp, w_setRelativeMode).
    #
    # In relative mode the pointer is hidden and stays where it is, and the
    # +mousemoved+ callback reports how far the mouse moved, as a game that
    # turns a camera with the mouse needs. Returns +false+ when the system
    # cannot turn it on, so it stays a method rather than a writer (ADR
    # 001, rule 7). Raises TypeError unless +relative+ is +true+ or
    # +false+, and RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.set_relative_mode(true) # => true
    def self.set_relative_mode(relative)
      Native::Mouse.set_relative_mode(relative)
    end

    # Whether relative mode is on, matching love.mouse.getRelativeMode
    # (src/modules/mouse/wrap_Mouse.cpp, w_getRelativeMode).
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.relative_mode # => false
    def self.relative_mode
      Native::Mouse.relative_mode
    end

    # Whether the system lets a game change the pointer's shape, matching
    # love.mouse.isCursorSupported (src/modules/mouse/wrap_Mouse.cpp,
    # w_isCursorSupported).
    #
    # Raises RuntimeError when the mouse module is not open.
    #
    # === Example
    #
    #   Lota::Mouse.cursor = Lota::Mouse.system_cursor(:hand) if Lota::Mouse.cursor_supported?
    def self.cursor_supported?
      Native::Mouse.cursor_supported?
    end
  end
end
