# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Text laid out once and drawn many times, matching LÖVE's TextBatch
    # class (src/modules/graphics/TextBatch.h), which LÖVE 11 called Text.
    #
    # Lota::Graphics.print lays out its text, and sends its glyphs to the
    # graphics card, every time it is called. A TextBatch does that work
    # when you add the text, then draws all of it in one go, as a
    # SpriteBatch does for sprites. Many pieces of text, each placed
    # where you like and each in colors of its own, share one batch drawn
    # with Lota::Graphics.draw.
    #
    # Use it for text that changes rarely and is drawn every frame, such
    # as the text on a screen full of cards.
    #
    # === Examples
    #
    #   text = Lota::Graphics::TextBatch.new(font)
    #   title = text.add("Fireball", 8, 8)
    #   text.addf([[1, 0.5, 0], "Deal 6 damage."], 120, :center, 8, 40)
    #   Lota::Graphics.draw(text, 100, 100)
    class TextBatch < Object
      # Wraps a TextBatch the engine made. :nodoc:
      private_class_method def self.from_native(native)
        batch = allocate
        batch.instance_variable_set(:@native, native)
        batch
      end

      # Makes a batch drawn in +font+, matching love.graphics.newTextBatch
      # (src/modules/graphics/wrap_Graphics.cpp, w_newTextBatch), named by
      # rule 2 of doc/contributors/design/translation.md.
      #
      # [font] Lota::Graphics::Font the text is drawn in.
      # [text] String, or an Array of colored text as Lota::Graphics.print
      #   takes it, for the batch to start with; empty when left out or
      #   +nil+.
      #
      # Raises TypeError for a font that is not a Font or text of the
      # wrong type, RuntimeError with LÖVE's message when the window is
      # not open, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::TextBatch.new(font)
      #   Lota::Graphics::TextBatch.new(font, "Game Over")
      #   Lota::Graphics::TextBatch.new(font, [[1, 0, 0], "Game ", [1, 1, 1], "Over"])
      def self.new(font, text = nil)
        raise TypeError, "wrong argument type #{font.class} (expected Lota::Graphics::Font)" unless font.is_a?(Font)

        from_native(Native::Graphics.new_text_batch(font.__send__(:native), text.nil? ? nil : Graphics.__send__(:colored_text, text, "Lota::Graphics::TextBatch.new")))
      end

      # Replaces everything in the batch with +text+, placed at the
      # origin, matching TextBatch:set
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_set).
      #
      # [text] String, or an Array of colored text as
      #   Lota::Graphics.print takes it.
      #
      # === Example
      #
      #   batch.set("Round 2")
      def set(text)
        @native.set(Graphics.__send__(:colored_text, text, "Lota::Graphics::TextBatch#set"))
      end

      # Replaces everything in the batch with +text+ wrapped at +wraplimit+
      # and aligned within it, matching TextBatch:setf
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_setf).
      #
      # [text] As for set.
      # [wraplimit] Float or Integer width at which lines wrap.
      # [align] +:left+, +:center+, +:right+, or +:justify+.
      #
      # Raises ArgumentError for an unknown alignment.
      #
      # === Example
      #
      #   batch.setf("A long line of text", 100, :center)
      def setf(text, wraplimit, align)
        @native.setf(Graphics.__send__(:colored_text, text, "Lota::Graphics::TextBatch#setf"), wraplimit, EnumName.of(align))
      end

      # Adds +text+ and returns its Integer index, counting from 1, for
      # width, height, and dimensions, matching TextBatch:add
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_add).
      #
      # [text] As for set.
      # [placement] Where the text goes: up to nine numbers, as
      #   Lota::Graphics.draw takes them after a drawable, or a
      #   Lota::Math::Transform.
      #
      # === Examples
      #
      #   index = batch.add("Hello", 10, 20)
      #   batch.add("Hello", 10, 20, Math::PI / 4, 2)
      #   batch.add("Hello", transform)
      def add(text, *placement)
        colored = Graphics.__send__(:colored_text, text, "Lota::Graphics::TextBatch#add")
        transform = placement.first
        return @native.add_with_transform(colored, transform.native) if transform.is_a?(Math::Transform)

        @native.add(colored, Graphics.__send__(:standard_placement, *numbers(placement)))
      end

      # Adds +text+ wrapped at +wraplimit+ and aligned within it, and
      # returns its Integer index, counting from 1, matching TextBatch:addf
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_addf).
      #
      # [text] As for set.
      # [wraplimit] Float or Integer width at which lines wrap.
      # [align] +:left+, +:center+, +:right+, or +:justify+.
      # [placement] As for add.
      #
      # Raises ArgumentError for an unknown alignment.
      #
      # === Example
      #
      #   batch.addf("A long line of text", 100, :right, 10, 20)
      def addf(text, wraplimit, align, *placement)
        colored = Graphics.__send__(:colored_text, text, "Lota::Graphics::TextBatch#addf")
        align = EnumName.of(align)
        transform = placement.first
        return @native.addf_with_transform(colored, wraplimit, align, transform.native) if transform.is_a?(Math::Transform)

        @native.addf(colored, wraplimit, align, Graphics.__send__(:standard_placement, *numbers(placement)))
      end

      # The numbers in +placement+, which holds a Transform only in place
      # of all of them.
      private def numbers(placement)
        numbers = [] #: Array[Float | Integer | nil]
        placement.each do |number|
          case number
          when Float, Integer, nil then numbers << number
          end
        end
        numbers
      end

      # Removes all the text, matching TextBatch:clear
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_clear).
      #
      # === Example
      #
      #   batch.clear
      def clear
        @native.clear
      end

      # Sets the font the batch's text is drawn in, matching
      # TextBatch:setFont (src/modules/graphics/wrap_TextBatch.cpp,
      # w_TextBatch_setFont). The text is laid out again in it.
      #
      # Raises TypeError for anything but a Font.
      #
      # === Example
      #
      #   batch.font = Lota::Graphics::Font.new(24)
      def font=(font)
        raise TypeError, "wrong argument type #{font.class} (expected Lota::Graphics::Font)" unless font.is_a?(Font)

        @native.set_font(font.native)
      end

      # The font the batch's text is drawn in, matching TextBatch:getFont
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_getFont).
      #
      # === Example
      #
      #   batch.font.height
      def font
        Font.__send__(:from_native, @native.font)
      end

      # The Float width of all the text, or of the text at +index+, as
      # add returned it, matching TextBatch:getWidth
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_getWidth).
      #
      # === Example
      #
      #   batch.width
      def width(index = nil)
        @native.width(index || 0)
      end

      # The Float height of all the text, or of the text at +index+,
      # matching TextBatch:getHeight
      # (src/modules/graphics/wrap_TextBatch.cpp, w_TextBatch_getHeight).
      #
      # === Example
      #
      #   batch.height
      def height(index = nil)
        @native.height(index || 0)
      end

      # The width and height of all the text, or of the text at +index+,
      # as an Array of two Floats (rule 4 of
      # doc/contributors/design/translation.md), matching
      # TextBatch:getDimensions (src/modules/graphics/wrap_TextBatch.cpp,
      # w_TextBatch_getDimensions).
      #
      # === Example
      #
      #   width, height = batch.dimensions
      def dimensions(index = nil)
        @native.dimensions(index || 0)
      end
    end
  end
end
