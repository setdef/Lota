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
    # Cursor, Cursor.new makes one of a picture of the game's own, and
    # Lota::Mouse.cursor= shows it.
    #
    # === Examples
    #
    #   drag = Lota::Mouse.system_cursor(:sizewe)
    #   Lota::Mouse.cursor = drag
    #
    #   Lota::Mouse.cursor = Lota::Mouse::Cursor.new("pointer.png", 4, 2)
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

      # A Cursor of a picture, matching love.mouse.newCursor
      # (src/modules/mouse/wrap_Mouse.cpp, w_newCursor), which rule 2
      # makes Cursor.new.
      #
      # [image] A Lota::Image::ImageData, or anything
      #   Lota::Image::ImageData.new decodes, such as an image file's name
      #   or a Lota::Filesystem::FileData; or an Array of them, the same
      #   picture at each of the screen's scales.
      # [hotx] Integer pixel of the picture, from its left, that points;
      #   0 when left out.
      # [hoty] Integer pixel, from its top; 0 when left out.
      #
      # Raises RuntimeError with LÖVE's message where the system cannot
      # make cursors (Lota::Mouse.cursor_supported?), or for a picture it
      # cannot use.
      #
      # === Example
      #
      #   Lota::Mouse::Cursor.new("pointer.png", 4, 2).get_type # => :image
      def self.new(image, hotx = 0, hoty = 0)
        images = (image.is_a?(Array) ? image : [image]).map do |each|
          (each.is_a?(Image::ImageData) ? each : Image::ImageData.new(each)).native
        end
        from_native(Native::Mouse.new_cursor(images, hotx, hoty))
      end

      # What kind of Cursor this is, as a Symbol, matching Cursor:getType
      # (src/modules/mouse/wrap_Cursor.cpp, w_Cursor_getType):
      # <tt>:image</tt> for one made from an image, and a system cursor's
      # shape, such as <tt>:hand</tt>, for one of the system's (ADR 001,
      # rules 9 and 16).
      #
      # === Example
      #
      #   Lota::Mouse.system_cursor(:hand).get_type # => :hand
      def get_type
        @native.get_type.to_sym
      end
    end
  end
end
