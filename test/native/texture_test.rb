# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# Lota::Graphics::Texture.new, beyond what Lövetest's test for it checks
# (test/lovetest/tests/graphics.rb): w_newTexture's image from a FileData
# or an ImageData, its DPI scale from the FileData's name
# (wrap_Graphics.cpp:692-712), and the errors LÖVE raises.
class TextureTest < Minitest::Test
  # love.png (vendor/love/testing/resources) is 64 by 64, white at its
  # center, and pink 22 pixels left of it.
  WHITE = [1.0, 1.0, 1.0, 1.0].freeze
  BLACK = [0.0, 0.0, 0.0, 1.0].freeze

  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def drawn(size = 64)
    canvas = Lota::Graphics::Canvas.new(size, size)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    yield
    Lota::Graphics.canvas = nil
    Lota::Graphics.readback_texture(canvas)
  end

  def logo
    Lota::Image::ImageData.new(Lovetest.resource("love.png"))
  end

  def test_a_texture_is_not_a_canvas
    refute_predicate Lota::Graphics::Texture.new(logo), :canvas?
  end

  def test_a_texture_from_file_data_or_image_data_draws_their_pixels
    from_data = drawn { Lota::Graphics.draw(Lota::Graphics::Texture.new(Lovetest.resource("love.png"))) }
    from_image = drawn { Lota::Graphics.draw(Lota::Graphics::Texture.new(logo)) }

    assert_equal logo.pixel(10, 32), from_data.pixel(10, 32)
    assert_equal logo.pixel(10, 32), from_image.pixel(10, 32)
  end

  # A file named like "love@2x.png" holds pixels at twice the density, so
  # the texture draws at half its pixel size.
  def test_a_file_named_at_2x_draws_at_half_size
    data = Lota::Filesystem::FileData.new(File.binread(File.join(Lovetest::RESOURCES, "love.png")), "love@2x.png")
    image = drawn { Lota::Graphics.draw(Lota::Graphics::Texture.new(data)) }

    assert_equal WHITE, image.pixel(16, 16)
    assert_equal BLACK, image.pixel(40, 40)
  end

  def test_a_texture_needs_an_image
    error = assert_raises(TypeError) { Lota::Graphics::Texture.new(64) }

    assert_equal "wrong argument type Integer (expected Lota::Filesystem::FileData or Lota::Image::ImageData)",
      error.message
  end
end
