# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# Lota::Graphics::Texture.new, Lota::Graphics::Image,
# Lota::Image::ImageData.new, and Lota::Graphics::Font.new with a file
# name, beyond what Lövetest's tests for them check
# (test/lovetest/tests/graphics.rb): w_newTexture's image from a file, a
# FileData, or an ImageData, its canvas setting, its DPI scale from a
# file's name (wrap_Graphics.cpp:692-712), and the errors LÖVE raises.
# The test process boots test/lovetest, whose resources/ links to
# Lövetest's, so a file name there is a path in that folder, as LÖVE's
# filesystem reads it.
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

  def test_a_texture_from_a_file_draws_the_files_pixels
    texture = Lota::Graphics::Texture.new("resources/love.png")
    image = drawn { Lota::Graphics.draw(texture) }

    refute_predicate texture, :canvas?
    assert_equal logo.pixel(32, 32), image.pixel(32, 32)
    assert_equal logo.pixel(10, 32), image.pixel(10, 32)
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

    assert_equal "wrong argument type Integer (expected String, Lota::Filesystem::FileData, or " \
      "Lota::Image::ImageData)", error.message
  end

  def test_a_file_that_is_not_there_raises_loves_error
    texture = assert_raises(RuntimeError) { Lota::Graphics::Texture.new("resources/missing.png") }
    font = assert_raises(RuntimeError) { Lota::Graphics::Font.new("resources/missing.ttf", 8) }
    image = assert_raises(RuntimeError) { Lota::Image::ImageData.new("resources/missing.png") }

    assert_equal "Could not open file resources/missing.png. Does not exist.", texture.message
    assert_equal "Could not open file resources/missing.ttf. Does not exist.", font.message
    assert_equal "Could not open file resources/missing.png. Does not exist.", image.message
  end

  def test_an_image_data_from_a_file_decodes_it
    image = Lota::Image::ImageData.new("resources/love.png")

    assert_equal [64, 64], [image.width, image.height]
    assert_equal logo.pixel(10, 32), image.pixel(10, 32)
  end

  # A font file named alone reads at LÖVE's default size for its data,
  # through Font::newRasterizer, as the FileData form does.
  def test_a_font_from_a_file_draws_as_from_its_data
    by_name = drawn(16) do
      Lota::Graphics.font = Lota::Graphics::Font.new("resources/font.ttf", 8)
      Lota::Graphics.print("love", 0, 3)
    end
    by_data = drawn(16) do
      Lota::Graphics.font = Lota::Graphics::Font.new(Lovetest.resource("font.ttf"), 8)
      Lota::Graphics.print("love", 0, 3)
    end

    assert_equal (0...16).map { |x| by_data.pixel(x, 6) }, (0...16).map { |x| by_name.pixel(x, 6) }
    refute_equal [BLACK] * 16, (0...16).map { |x| by_name.pixel(x, 6) }
  ensure
    Lota::Graphics.font = Lovetest.font if Lovetest.font
  end

  # newTexture's canvas setting (wrap_Graphics.cpp:770-771) makes a texture
  # from an image that can also be drawn into.
  def test_the_canvas_setting_makes_a_texture_to_draw_into
    texture = Lota::Graphics::Texture.new(logo, canvas: true)
    Lota::Graphics.canvas = texture
    Lota::Graphics.clear(0, 0, 1, 1)
    Lota::Graphics.canvas = nil

    assert_predicate texture, :canvas?
    assert_equal [0.0, 0.0, 1.0, 1.0], Lota::Graphics.readback_texture(texture).pixel(32, 32)
    refute_predicate Lota::Graphics::Texture.new(logo, canvas: nil), :canvas?
    refute_predicate Lota::Graphics::Texture.new(logo, canvas: false), :canvas?
  end

  # LÖVE 12's newImage is newTexture (wrap_Graphics.cpp:1251-1255), so
  # Image.new makes the texture Texture.new makes from the same arguments.
  def test_an_image_is_a_texture_made_as_texture_new_makes_one
    image = Lota::Graphics::Image.new(Lovetest.resource("love.png"))
    drawn_image = drawn { Lota::Graphics.draw(image) }

    assert_instance_of Module, Lota::Graphics::Image
    assert_instance_of Lota::Graphics::Texture, image
    refute_predicate image, :canvas?
    assert_equal logo.pixel(10, 32), drawn_image.pixel(10, 32)
    assert_predicate Lota::Graphics::Image.new(logo, canvas: true), :canvas?
  end

  # A texture records nothing of the factory that made it, and newImage
  # can make a canvas, so every Texture is an image, and nothing else is.
  def test_every_texture_and_nothing_else_is_an_image
    texture = Lota::Graphics::Texture.new(logo)
    canvas = Lota::Graphics::Canvas.new(4, 4)
    kind = case canvas
    when Lota::Graphics::Image then :image
    end

    assert_operator Lota::Graphics::Image, :===, texture
    assert_operator Lota::Graphics::Image, :===, canvas
    assert_equal :image, kind
    refute_operator Lota::Graphics::Image, :===, :image
    refute_operator Lota::Graphics::Image, :===, logo
  end
end
