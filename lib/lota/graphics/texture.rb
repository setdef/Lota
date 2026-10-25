# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # An image on the graphics card, matching LÖVE's Texture class
    # (src/modules/graphics/Texture.h).
    #
    # Whatever a game draws, it draws from a texture or into one. Pixels
    # in memory are slow to draw; a texture keeps them where the graphics
    # card can reach them at once.
    #
    # LÖVE 12 has one class for every texture, where LÖVE 11 had separate
    # Image and Canvas classes. Lota::Graphics::Canvas.new makes a texture
    # you can draw into, and canvas? says whether a texture is one.
    #
    # Use it to read rendered pixels back with
    # Lota::Graphics.readback_texture, and as the target of
    # Lota::Graphics.canvas=.
    #
    # === Examples
    #
    #   texture = Lota::Graphics::Canvas.new(16, 16)
    #   texture.class   # => Lota::Graphics::Texture
    #   texture.canvas? # => true
    class Texture
      # The engine's Texture, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Texture the engine made. Every Texture the engine hands
      # to Ruby passes through here. :nodoc:
      def self.from_native(native)
        texture = allocate
        texture.instance_variable_set(:@native, native)
        texture
      end

      # LÖVE makes textures with factories such as love.graphics.newCanvas,
      # so Lota does too (Lota::Graphics::Canvas.new).
      private_class_method :new

      # Whether you can draw into this texture, matching Texture:isCanvas
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_isCanvas).
      #
      # A texture made by Lota::Graphics::Canvas.new always is. So
      # <tt>Lota::Graphics::Canvas === texture</tt> asks this, and a
      # +case+ can tell canvases from other textures.
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16).canvas? # => true
      def canvas?
        @native.canvas?
      end
    end
  end
end
