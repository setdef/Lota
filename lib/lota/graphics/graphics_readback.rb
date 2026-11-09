# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A copy of a texture's pixels from the graphics card that finishes on
    # its own while the game goes on, matching LÖVE's GraphicsReadback
    # class (src/modules/graphics/GraphicsReadback.h), which
    # Lota::Graphics.readback_texture_async makes.
    #
    # Lota::Graphics.readback_texture waits for the graphics card to finish
    # drawing before it returns, which can stall a frame. A readback asks
    # for the pixels and returns at once; LÖVE checks it each frame, as it
    # presents, and the pixels are there once complete? says so. To have
    # them sooner, wait.
    #
    # === Example
    #
    #   @readback = Lota::Graphics.readback_texture_async(canvas)
    #
    #   def Lota.update(dt)
    #     return unless @readback&.complete?
    #
    #     @readback.image_data.encode(:png, "frame.png")
    #     @readback = nil
    #   end
    class GraphicsReadback < Object
      # Wraps a GraphicsReadback the engine made. :nodoc:
      private_class_method def self.from_native(native)
        readback = allocate
        readback.instance_variable_set(:@native, native)
        readback
      end

      # Whether the copy has finished, with or without an error, matching
      # GraphicsReadback:isComplete
      # (src/modules/graphics/wrap_GraphicsReadback.cpp,
      # w_GraphicsReadback_isComplete).
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   readback.complete? # => false
      def complete?
        @native.complete?
      end

      # Whether the copy failed, matching GraphicsReadback:hasError
      # (src/modules/graphics/wrap_GraphicsReadback.cpp,
      # w_GraphicsReadback_hasError).
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   readback.error? # => false
      def error?
        @native.error?
      end

      # Waits until the copy has finished, matching GraphicsReadback:wait
      # (src/modules/graphics/wrap_GraphicsReadback.cpp,
      # w_GraphicsReadback_wait), and returns +nil+.
      #
      # It stalls as Lota::Graphics.readback_texture does. Raises
      # ThreadError off the main thread.
      #
      # === Example
      #
      #   readback.wait
      #   readback.complete? # => true
      def wait
        @native.wait
      end

      # Checks whether the copy has finished, and when it has, puts the
      # pixels where image_data finds them, matching
      # GraphicsReadback:update
      # (src/modules/graphics/wrap_GraphicsReadback.cpp,
      # w_GraphicsReadback_update), and returns +nil+.
      #
      # LÖVE does this for every readback as it presents a frame, so a game
      # needs it only to know sooner. Raises RuntimeError with LÖVE's
      # message when the copy cannot be made, and ThreadError off the main
      # thread.
      #
      # === Example
      #
      #   readback.update
      def update
        @native.update
      end

      # The bytes a buffer's readback read, as a Lota::Data::ByteData, or
      # +nil+ until the copy has finished, matching
      # GraphicsReadback:getBufferData
      # (src/modules/graphics/wrap_GraphicsReadback.cpp,
      # w_GraphicsReadback_getBufferData). A texture's readback reads no
      # bytes, so it is always +nil+ for one.
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   readback.buffer_data # => nil
      def buffer_data
        native = @native.buffer_data
        native && Lota::Data::ByteData.__send__(:from_native, native)
      end

      # The pixels a texture's readback read, as a Lota::Image::ImageData,
      # the one given to Lota::Graphics.readback_texture_async if it was
      # given one, or +nil+ until the copy has finished, matching
      # GraphicsReadback:getImageData
      # (src/modules/graphics/wrap_GraphicsReadback.cpp,
      # w_GraphicsReadback_getImageData).
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   readback.wait
      #   readback.image_data.pixel(0, 0) # => [1.0, 0.0, 0.0, 1.0]
      def image_data
        native = @native.image_data
        native && Lota::Image::ImageData.__send__(:from_native, native)
      end
    end
  end
end
