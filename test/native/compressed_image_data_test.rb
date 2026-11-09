# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Image::CompressedImageData, as love.image.newCompressedData makes
# it (src/modules/image/wrap_Image.cpp:106-119) and its methods read it
# (src/modules/image/wrap_CompressedImageData.cpp), and
# Lota::Image.compressed?, as love.image.isCompressed asks
# (wrap_Image.cpp:121-129). The file is Lövetest's own: a 64 by 64 DXT1
# image with seven mipmaps (vendor/love/testing/resources/love.dxt1).
class CompressedImageDataTest < Minitest::Test
  Image = Lota::Image
  RESOURCES = File.expand_path("../lovetest/resources", __dir__)

  def setup
    EngineHelper.open_window
  end

  def compressed
    Image::CompressedData.new("resources/love.dxt1")
  end

  def bytes(name)
    File.binread(File.join(RESOURCES, name))
  end

  # luax_getdata (src/modules/filesystem/wrap_Filesystem.cpp:381-411)
  # reads a file name, a File, or any Data, so the file reads the same from
  # each.
  def test_compressed_data_comes_from_a_file_name_a_file_or_any_data
    file = Lota::Filesystem.open_file("resources/love.dxt1", :r).first
    sources = [
      "resources/love.dxt1",
      file,
      Lota::Filesystem.new_file_data(bytes("love.dxt1"), "love.dxt1").first,
      Lota::Data::ByteData.new(bytes("love.dxt1")),
    ]

    sources.each do |source|
      data = Image::CompressedData.new(source)

      assert_instance_of Image::CompressedImageData, data
      assert_equal [64, 64, 7, 2744], [*data.dimensions, data.mipmap_count, data.size]
    end
  ensure
    file&.close
  end

  def test_compressed_data_refuses_what_luax_getdata_cannot_read
    error = assert_raises(TypeError) { Image::CompressedData.new(:dxt1) }

    assert_equal "wrong argument type Symbol (expected filename, File, or Data)", error.message
    assert_raises(TypeError) { Image.compressed?(64) }
  end

  # CompressedImageData's constructor (src/modules/image/
  # CompressedImageData.cpp:30-62) raises when no format handler parses
  # the data.
  def test_compressed_data_raises_loves_error_for_an_image_it_cannot_parse
    error = assert_raises(RuntimeError) { Image::CompressedData.new("resources/love.png") }

    assert_equal "Could not parse compressed data: Unknown format.", error.message
  end

  def test_compressed_asks_whether_a_format_handler_parses_the_data
    assert Image.compressed?("resources/love.dxt1")
    assert Image.compressed?(Lota::Data::ByteData.new(bytes("love.dxt1")))
    refute Image.compressed?("resources/love.png")
  end

  # Rule 2: LÖVE has no CompressedData class in love.image, so
  # CompressedData is a module, whose === is true of every
  # CompressedImageData, the only thing newCompressedData makes.
  def test_compressed_data_matches_every_compressed_image_data
    assert_operator Image::CompressedData, :===, compressed
    refute_operator Image::CompressedData, :===, Image::ImageData.new(1, 1)
    refute_operator Image::CompressedData, :===, Lota::Data::ByteData.new("x")
    assert_raises(NoMethodError) { Image::CompressedImageData.new }
  end

  # getWidth, getHeight, and getDimensions take a mipmap, counting from 1
  # (wrap_CompressedImageData.cpp:43-82), and checkSliceExists raises for
  # one the image lacks (CompressedImageData.cpp:157-164).
  def test_each_mipmap_has_its_own_size
    data = compressed

    assert_equal [64, 64], data.dimensions(1)
    assert_equal [32, 16, 1], [data.width(2), data.height(3), data.width(7)]
    assert_equal [8, 8], data.dimensions(4)
    error = assert_raises(RuntimeError) { data.width(8) }

    assert_equal "Mipmap level 8 does not exist", error.message
    assert_raises(RuntimeError) { data.height(0) }
  end

  def test_it_is_a_data_of_its_own_type
    data = compressed

    assert_equal "CompressedImageData", data.object_type
    assert data.type_of?("Data")
    assert_equal 2744, data.string.bytesize
  end

  # w_CompressedImageData_clone (wrap_CompressedImageData.cpp:34-41): a copy
  # with its own memory, so setting one linear leaves the other.
  def test_clone_makes_loves_copy
    data = compressed
    copy = data.clone
    copy.linear = true

    assert_instance_of Image::CompressedImageData, copy
    assert_equal [:DXT1, 7], [copy.format, copy.mipmap_count]
    assert_equal data.string, copy.string
    refute_predicate data, :linear?
    assert_predicate copy, :linear?
  end

  # luax_checkboolean (wrap_CompressedImageData.cpp:106-111) takes only a
  # boolean.
  def test_linear_takes_true_or_false
    assert_raises(TypeError) { compressed.linear = 1 }
  end

  # getImageData (src/modules/graphics/wrap_Graphics.cpp:714-745) takes a
  # CompressedImageData as it is, so a texture made from one is compressed.
  def test_a_texture_draws_a_compressed_image_data
    texture = Lota::Graphics::Image.new(compressed)

    assert_predicate texture, :compressed?
    assert_equal :DXT1, texture.format
  end
end
