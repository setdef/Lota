# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "lovetest_helper"

# Lovetest::TestMethod#compare_img fails a test whose image differs from
# LÖVE's, so a translated test that passes has matched LÖVE's image. Each
# test clears a canvas as love.test.graphics.clear does, but to another
# color, and compares it with that test's expected image.
class CompareImgTest < Lovetest::TestMethod
  def lovetest_method
    "clear"
  end

  def cleared(red, green, blue, alpha)
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(red, green, blue, alpha)
    Lota::Graphics.canvas = nil
    Lota::Graphics.readback_texture(canvas)
  end

  def test_the_expected_color_matches
    compare_img(cleared(1, 1, 0, 1))
  end

  def test_a_wrong_color_fails
    failure = assert_raises(Minitest::Assertion) { compare_img(cleared(1, 0, 1, 1)) }

    assert_includes failure.message, "at 0,0, matching = ra, not matching = gb (clear-1)"
  end

  # Lövetest's default tolerance is zero: one 8-bit step in one component
  # is a different image.
  def test_one_step_off_in_one_component_fails
    failure = assert_raises(Minitest::Assertion) { compare_img(cleared(1, 1, 1.0 / 255, 1)) }

    assert_includes failure.message, "not matching = b (clear-1)"
  end

  def test_a_missing_expected_image_fails
    @imgs = 2

    failure = assert_raises(Minitest::Assertion) { compare_img(cleared(1, 1, 0, 1)) }
    assert_includes failure.message, "love.test.graphics.clear-2.png"
  end
end
