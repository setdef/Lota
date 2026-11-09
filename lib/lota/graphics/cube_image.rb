# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # LÖVE 11's name for Lota::Graphics::CubeTexture, which LÖVE 12 keeps
    # as love.graphics.newCubeImage, a function that calls
    # w_newCubeTexture (src/modules/graphics/wrap_Graphics.cpp,
    # w_newCubeImage). LÖVE marks it renamed only in a comment, so it
    # prints no notice.
    #
    # LÖVE has no CubeImage class. So CubeImage is a module, as Canvas is (rules
    # 25 and 26 of doc/contributors/design/translation.md), whose +new+ returns
    # a Texture and whose <tt>CubeImage === texture</tt> asks, as CubeTexture's
    # does, whether the texture's type is +:cube+.
    #
    # === Example
    #
    #   Lota::Graphics::CubeImage.new(%w[a.png b.png]).texture_type # => :cube
    module CubeImage
      # Creates a cube texture as Lota::Graphics::CubeTexture.new does,
      # matching love.graphics.newCubeImage.
      #
      # === Example
      #
      #   Lota::Graphics::CubeImage.new(%w[a.png b.png])
      def self.new(*, **settings)
        CubeTexture.new(*, **settings)
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:cube+, as Lota::Graphics::CubeTexture === asks.
      #
      # === Example
      #
      #   Lota::Graphics::CubeImage === Lota::Graphics::Canvas.new(8, 8) # => false
      def self.===(object)
        CubeTexture === object
      end
    end
  end
end
