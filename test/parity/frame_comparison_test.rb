# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"
require_relative "../lovetest/lovetest_helper"
require_relative "frame_comparison"

# Parity::FrameComparison agrees with Lövetest's compareImg, as
# Lovetest::TestMethod#compare_img translates it: on the expected image of
# love.test.graphics.clear, a canvas cleared as that test clears it
# matches, and one with pixels changed fails on the pixel compareImg fails
# on first, with compareImg's message.
class FrameComparisonTest < Lovetest::TestMethod
  def lovetest_method
    "clear"
  end

  def expected
    path = File.join(Lovetest::EXPECTED, "love.test.graphics.clear-1.png")
    Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(File.binread(path), File.basename(path)))
  end

  # A 16 by 16 canvas cleared to yellow, with a 1 by 1 rectangle of
  # +color+ at each of +points+.
  def cleared(points = [], color = [1, 0, 1, 1])
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(1, 1, 0, 1)
    Lota::Graphics.color = color
    points.each { |x, y| Lota::Graphics.rectangle(:fill, x, y, 1, 1) }
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.canvas = nil
    Lota::Graphics.readback_texture(canvas)
  end

  def test_the_same_pixels_match
    comparison = Parity::FrameComparison.new(expected, cleared, "clear-1")

    assert_predicate comparison, :match?
    assert_nil comparison.message
  end

  # compareImg goes column by column, so (2, 9) fails before (3, 5),
  # though it comes later row by row.
  def test_a_difference_fails_on_compare_imgs_first_pixel_with_its_message
    actual = cleared([[3, 5], [2, 9], [12, 0]])
    comparison = Parity::FrameComparison.new(expected, actual, "clear-1")
    failure = assert_raises(Minitest::Assertion) { compare_img(actual) }

    refute_predicate comparison, :match?
    assert_equal failure.message.lines.first.chomp.delete_suffix("."), comparison.message
    assert_includes comparison.message, "at 2,9, matching = ra, not matching = gb (clear-1)"
  end

  def test_one_step_in_one_component_fails
    actual = cleared([[0, 0]], [1, 1, 1.0 / 255, 1])
    comparison = Parity::FrameComparison.new(expected, actual, "clear-1")

    assert_includes comparison.message, "at 0,0, matching = rga, not matching = b (clear-1)"
  end

  def test_a_frame_of_another_size_fails_with_its_size
    canvas = Lota::Graphics::Canvas.new(8, 16)
    comparison = Parity::FrameComparison.new(expected, Lota::Graphics.readback_texture(canvas), "clear-1")

    assert_equal "frame is 8x16, expected 16x16 (clear-1)", comparison.message
  end
end
