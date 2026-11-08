# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # The name LÖVE 11 gave TextBatch, which LÖVE 12 still accepts as
    # love.graphics.newText but has deprecated, named by ADR 001, rule 2.
    #
    # LÖVE has no Text class: <tt>Text.new</tt> makes a
    # Lota::Graphics::TextBatch, and prints LÖVE's notice of the
    # deprecation the first time it is called. Because the engine cannot
    # tell the two apart, <tt>Text === batch</tt> is true of every
    # TextBatch.
    #
    # Use TextBatch.new in new code; this is for code ported from LÖVE 11.
    #
    # === Example
    #
    #   Lota::Graphics::Text.new(font, "Score") # => a TextBatch
    module Text
      # Makes a TextBatch as TextBatch.new does, matching
      # love.graphics.newText (src/modules/graphics/wrap_Graphics.cpp,
      # w_newText), which marks itself deprecated, renamed to newTextBatch,
      # and calls w_newTextBatch.
      #
      # [font] Lota::Graphics::Font the text is drawn in.
      # [text] As for TextBatch.new.
      #
      # === Example
      #
      #   Lota::Graphics::Text.new(font, [[1, 0, 0], "Game Over"])
      def self.new(font, text = nil)
        location = caller_locations(1, 1)&.first
        where = location ? "#{location.path}:#{location.lineno}: " : ""
        Deprecation.mark("Lota::Graphics::Text.new", :function, :renamed, "Lota::Graphics::TextBatch.new", where:)
        TextBatch.new(font, text)
      end

      # Whether +object+ is a Lota::Graphics::TextBatch, which every
      # object Text.new makes is.
      #
      # === Example
      #
      #   Lota::Graphics::Text === batch # => true
      def self.===(object)
        object.is_a?(TextBatch)
      end
    end
  end
end
