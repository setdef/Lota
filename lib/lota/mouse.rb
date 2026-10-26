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
  end
end
