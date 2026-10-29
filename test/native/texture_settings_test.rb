# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# The settings textures are made with, read as luax_checktexturesettings
# reads its table (src/modules/graphics/wrap_Graphics.cpp:759-871), and
# the forms of newTexture, newCanvas, newArrayImage, newCubeImage, and
# newVolumeImage, beyond what Lövetest's tests for them check
# (test/lovetest/tests/graphics.rb): sizes with no pixels, the errors LÖVE
# raises, and mipmaps, which a texture drawn smaller samples.
class TextureSettingsTest < Minitest::Test
  Graphics = Lota::Graphics

  def setup
    EngineHelper.open_window
    Graphics.color = 1, 1, 1, 1
  end

  def test_a_size_makes_a_texture_with_no_pixels_of_its_type
    flat = Graphics::Texture.new(8, 4)
    layered = Graphics::Texture.new(8, 4, 3)

    assert_equal [:"2d", [8, 4], 1], [flat.texture_type, flat.dimensions, flat.layer_count]
    assert_equal [:array, 3], [layered.texture_type, layered.layer_count]
    assert_equal :volume, Graphics::Texture.new(8, 8, type: :volume, layers: 2).texture_type
  end

  def test_an_image_ignores_the_type_setting_as_loves_image_form_does
    assert_equal :"2d", Graphics::Texture.new("resources/love.png", type: :volume).texture_type
  end

  def test_settings_reach_the_texture
    canvas = Graphics::Canvas.new(16, 16, format: :rgba16f, debugname: "glow", dpiscale: 2, mipmaps: :manual)

    assert_equal [:rgba16f, "glow", 2.0, :manual], [canvas.format, canvas.debug_name, canvas.dpi_scale, canvas.mipmap_mode]
    assert_equal [32, 32], canvas.pixel_dimensions
    assert_equal [16, 16], canvas.pixel_dimensions(2)
  end

  def test_mipmaps_true_and_false_name_manual_and_none
    assert_equal :manual, Graphics::Image.new("resources/love.png", mipmaps: true).mipmap_mode
    assert_equal :none, Graphics::Image.new("resources/love.png", mipmaps: false).mipmap_mode
    assert_equal 1, Graphics::Image.new("resources/love.png").mipmap_count
  end

  def test_a_dpi_scale_setting_wins_over_a_files_name
    data = Lota::Filesystem::FileData.new(File.binread(File.join(Lovetest::RESOURCES, "love.png")), "love@2x.png")

    assert_equal 2.0, Graphics::Texture.new(data).dpi_scale
    assert_equal 1.0, Graphics::Texture.new(data, dpiscale: 1).dpi_scale
  end

  def test_a_canvas_from_settings_alone_needs_its_size
    canvas = Graphics::Canvas.new(width: 4, height: 2)
    error = assert_raises(ArgumentError) { Graphics::Canvas.new(format: :rgba8) }

    assert_equal [4, 2], canvas.dimensions
    assert_equal "expected integer field 'width' in table", error.message
  end

  def test_a_canvas_is_always_a_canvas
    assert_predicate Graphics::Canvas.new(4, 4, canvas: false), :canvas?
    refute_predicate Graphics::Texture.new(4, 4), :canvas?
    assert_predicate Graphics::Texture.new(4, 4, canvas: true), :canvas?
  end

  def test_unknown_settings_and_values_raise_loves_errors
    name = assert_raises(ArgumentError) { Graphics::Canvas.new(4, 4, size: 3) }
    format = assert_raises(ArgumentError) { Graphics::Canvas.new(4, 4, format: :rgba9) }
    mipmaps = assert_raises(ArgumentError) { Graphics::Canvas.new(4, 4, mipmaps: :sometimes) }
    type = assert_raises(ArgumentError) { Graphics::Canvas.new(4, 4, type: :flat) }

    assert_equal "Invalid texture setting name: size", name.message
    assert_equal "Invalid pixel format: rgba9", format.message
    assert_equal "Invalid Texture mipmap mode 'sometimes', expected one of: 'none', 'manual', 'auto'", mipmaps.message
    assert_match(/\AInvalid texture type 'flat', expected one of: /, type.message)
    assert_raises(TypeError) { Graphics::Canvas.new(4, 4, readable: 1) }
    assert_raises(ArgumentError) { Graphics::Canvas.new(4, 4, viewformats: :rgba8) }
  end

  def test_a_size_that_is_not_a_number_raises
    assert_raises(TypeError) { Graphics::Canvas.new("4", 4) }
    assert_raises(ArgumentError) { Graphics::Texture.new(4) }
    assert_raises(TypeError) { Graphics::ArrayImage.new(4, 4, :three) }
  end

  def test_array_cube_and_volume_images_are_their_types
    array = Graphics::ArrayImage.new(%w[resources/love.png resources/love2.png])
    cube = Graphics::CubeImage.new("resources/cubemap.png")
    volume = Graphics::VolumeImage.new(%w[resources/love.png resources/love2.png resources/love3.png])

    assert_equal [:array, 2], [array.texture_type, array.layer_count]
    assert_equal :cube, cube.texture_type
    assert_equal [:volume, 3], [volume.texture_type, volume.depth]
    assert_operator Graphics::ArrayImage, :===, array
    refute_operator Graphics::ArrayImage, :===, cube
    assert_operator Graphics::CubeImage, :===, cube
    assert_operator Graphics::VolumeImage, :===, volume
    refute_operator Graphics::VolumeImage, :===, :volume
  end

  def test_sized_array_cube_and_volume_images
    assert_equal [:array, 3], Graphics::ArrayImage.new(4, 4, 3).then { [it.texture_type, it.layer_count] }
    assert_equal [:cube, [4, 4]], Graphics::CubeImage.new(4).then { [it.texture_type, it.dimensions] }
    assert_equal [:volume, 2], Graphics::VolumeImage.new(4, 4, 2).then { [it.texture_type, it.depth] }
  end

  def test_an_array_of_arrays_gives_each_layer_its_mipmaps
    logo = Lota::Image::ImageData.new("resources/love.png")
    half = Lota::Image::ImageData.new(32, 32)
    array = Graphics::ArrayImage.new([[logo, half], [logo, half]], mipmaps: true)

    assert_equal [2, 2], [array.layer_count, array.mipmap_count]
  end

  def test_a_cube_of_mipmaps_needs_six_faces
    logo = Lota::Image::ImageData.new("resources/love.png")
    error = assert_raises(RuntimeError) { Graphics::CubeImage.new([[logo]]) }

    assert_equal "Cubemap images must have 6 faces.", error.message
  end

  def test_a_compressed_image_stays_compressed
    assert_predicate Graphics::Image.new("resources/love.dxt1"), :compressed?
    refute_predicate Graphics::Image.new("resources/love.png"), :compressed?
  end

  # A canvas with mipmaps :auto makes them as it is drawn into, so its
  # second mipmap holds the first at half the size.
  def test_auto_mipmaps_follow_what_is_drawn
    canvas = Graphics::Canvas.new(4, 4, mipmaps: :auto)
    canvas.render_to { Graphics.clear(1, 0, 0, 1) }

    assert_equal [1.0, 0.0, 0.0, 1.0], Graphics.readback_texture(canvas, nil, 2).pixel(0, 0)
  end

  def test_manual_mipmaps_wait_for_generate_mipmaps
    canvas = Graphics::Canvas.new(4, 4, mipmaps: :manual)
    canvas.render_to { Graphics.clear(0, 0, 0, 1) }
    canvas.generate_mipmaps
    canvas.render_to { Graphics.clear(0, 1, 0, 1) }

    assert_equal [0.0, 0.0, 0.0, 1.0], Graphics.readback_texture(canvas, nil, 2).pixel(0, 0)
    canvas.generate_mipmaps
    assert_equal [0.0, 1.0, 0.0, 1.0], Graphics.readback_texture(canvas, nil, 2).pixel(0, 0)
  end

  def test_a_mipmap_the_texture_lacks_raises_loves_error
    error = assert_raises(RuntimeError) { Graphics::Canvas.new(4, 4).width(2) }

    assert_equal "Invalid mipmap index: 2", error.message
  end
end
