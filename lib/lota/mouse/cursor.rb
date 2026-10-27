# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Mouse
    # A picture for the mouse pointer, matching LÖVE's Cursor class
    # (src/modules/mouse/Cursor.h).
    #
    # The pointer's shape tells the player what a click will do: an arrow
    # selects, a hand follows a link, a pair of arrows drags an edge.
    # Operating systems draw a set of such shapes themselves.
    #
    # Lota::Mouse.system_cursor returns one of the system's shapes as a
    # Cursor, and Lota::Mouse.cursor= shows it. Lota makes the system's
    # cursors only; LÖVE also makes one from an image, which Lota binds
    # later.
    #
    # === Example
    #
    #   drag = Lota::Mouse.system_cursor(:sizewe)
    #   Lota::Mouse.cursor = drag
    class Cursor
      include Object

      # The engine's Cursor, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Cursor the engine made. :nodoc:
      def self.from_native(native)
        cursor = allocate
        cursor.instance_variable_set(:@native, native)
        cursor
      end

      # LÖVE makes cursors with love.mouse.getSystemCursor, so Lota does
      # too (Lota::Mouse.system_cursor).
      private_class_method :new
    end
  end
end
