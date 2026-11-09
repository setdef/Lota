# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # LÖVE 11's name for Lota::Graphics::ArrayTexture, which LÖVE 12 keeps
    # as love.graphics.newArrayImage, a function that calls
    # w_newArrayTexture (src/modules/graphics/wrap_Graphics.cpp,
    # w_newArrayImage). LÖVE marks it renamed only in a comment, so it
    # prints no notice.
    #
    # LÖVE has no ArrayImage class. So ArrayImage is a module, as Canvas is
    # (rules 25 and 26 of doc/contributors/design/translation.md), whose +new+
    # returns a Texture and whose <tt>ArrayImage === texture</tt> asks, as
    # ArrayTexture's does, whether the texture's type is +:array+.
    #
    # === Example
    #
    #   Lota::Graphics::ArrayImage.new(%w[a.png b.png]).texture_type # => :array
    module ArrayImage
      # Creates a array texture as Lota::Graphics::ArrayTexture.new does,
      # matching love.graphics.newArrayImage.
      #
      # === Example
      #
      #   Lota::Graphics::ArrayImage.new(%w[a.png b.png])
      def self.new(*, **settings)
        ArrayTexture.new(*, **settings)
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:array+, as Lota::Graphics::ArrayTexture === asks.
      #
      # === Example
      #
      #   Lota::Graphics::ArrayImage === Lota::Graphics::Canvas.new(8, 8) # => false
      def self.===(object)
        ArrayTexture === object
      end
    end
  end
end
