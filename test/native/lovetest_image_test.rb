# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../../tasks/lovetest_image"

# LovetestImage reads a PNG in plain Ruby, for a check that runs where
# Lota is not loaded (.github/fuse_check.rb), and compares two images by
# Lövetest's rule. Its reading is checked against the engine's own
# decoder, Lota::Image::ImageData, on every image Lövetest expects, which
# between them hold indexed images of each bit depth, grey, RGB, and RGBA.
class LovetestImageTest < Minitest::Test
  EXPECTED = File.join(NativeHelper::ROOT, "vendor/love/testing/output/expected")

  # The engine's decoder needs Lota::Image open, which booting opens.
  def setup
    EngineHelper.open_window
  end

  def test_it_reads_every_image_lovetest_expects_as_the_engine_decodes_it
    paths = Dir[File.join(EXPECTED, "*.png")]

    assert_operator paths.size, :>=, 60
    paths.each do |path|
      image = LovetestImage.read(path)
      file_data, = Lota::Filesystem.new_file_data(File.binread(path), File.basename(path))
      engine = Lota::Image::ImageData.new(file_data)

      assert_equal [engine.width, engine.height], [image.width, image.height], path
      assert_equal engine_pixels(engine), image.pixels, path
    end
  end

  def test_an_image_has_no_differences_from_itself
    image = LovetestImage.read(File.join(EXPECTED, LovetestImage::SCREENSHOT))

    assert_empty LovetestImage.differences(image, image)
  end

  def test_a_pixel_one_step_off_in_one_component_differs
    expected = LovetestImage::Image.new(width: 2, height: 2, pixels: [[0, 0, 0, 255]] * 4)
    pixels = expected.pixels.dup
    pixels[3] = [0, 0, 1, 255]
    actual = LovetestImage::Image.new(width: 2, height: 2, pixels:)

    assert_equal [[1, 1, [0, 0, 1, 255], [0, 0, 0, 255]]], LovetestImage.differences(actual, expected)
  end

  def test_images_of_different_sizes_cannot_be_compared
    small = LovetestImage::Image.new(width: 1, height: 1, pixels: [[0, 0, 0, 255]])
    wide = LovetestImage::Image.new(width: 2, height: 1, pixels: [[0, 0, 0, 255]] * 2)

    error = assert_raises(LovetestImage::Error) { LovetestImage.differences(wide, small) }
    assert_equal "the image is 2x1, and the expected image 1x1", error.message
  end

  # The engine's pixels, row by row, as 8-bit RGBA.
  def engine_pixels(image_data)
    (0...(image_data.height)).flat_map do |y|
      (0...(image_data.width)).map { |x| image_data.pixel(x, y).map { |value| (value * 255).round } }
    end
  end
end
