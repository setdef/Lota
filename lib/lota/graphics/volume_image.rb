# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # LÖVE 11's name for Lota::Graphics::VolumeTexture, which LÖVE 12 keeps
    # as love.graphics.newVolumeImage, a function that calls
    # w_newVolumeTexture (src/modules/graphics/wrap_Graphics.cpp,
    # w_newVolumeImage). LÖVE marks it renamed only in a comment, so it
    # prints no notice.
    #
    # LÖVE has no VolumeImage class. So VolumeImage is a module, as Canvas is
    # (ADR 001, rules 25 and 26), whose +new+ returns a Texture and whose
    # <tt>VolumeImage === texture</tt> asks, as VolumeTexture's does,
    # whether the texture's type is +:volume+.
    #
    # === Example
    #
    #   Lota::Graphics::VolumeImage.new(%w[a.png b.png]).texture_type # => :volume
    module VolumeImage
      # Creates a volume texture as Lota::Graphics::VolumeTexture.new does,
      # matching love.graphics.newVolumeImage.
      #
      # === Example
      #
      #   Lota::Graphics::VolumeImage.new(%w[a.png b.png])
      def self.new(*, **settings)
        VolumeTexture.new(*, **settings)
      end

      # Whether +object+ is a Lota::Graphics::Texture whose type is
      # +:volume+, as Lota::Graphics::VolumeTexture === asks.
      #
      # === Example
      #
      #   Lota::Graphics::VolumeImage === Lota::Graphics::Canvas.new(8, 8) # => false
      def self.===(object)
        VolumeTexture === object
      end
    end
  end
end
