# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "lovetest_helper"

# Lövetest runs each test in a frame of its own, and love.run resets the
# transformation before the next frame draws (callbacks.lua:196), so what
# one test translated or scaled reaches no test after it.
# Lovetest::TestMethod ends each test the same way, so it reaches no test
# of the suite after it either, Lövetest's or not.
class TestMethodTest < Minitest::Test
  # A test that scales and leaves the scale, as love.test.graphics.scale
  # does (vendor/love/testing/tests/graphics.lua).
  class Scaling < Lovetest::TestMethod
    def test_scale
      Lota::Graphics.scale(4, 4)
    end
  end
  # This suite runs it, when it chooses to.
  Minitest::Runnable.runnables.delete(Scaling)

  def test_a_test_leaves_the_origin_to_the_tests_after_it
    assert_predicate Scaling.new("test_scale").run, :passed?

    canvas = Lota::Graphics::Canvas.new(4, 4)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.canvas = nil
    image = Lota::Graphics.readback_texture(canvas)

    assert_equal [1.0, 1.0, 1.0, 1.0], image.pixel(0, 0)
    assert_equal [0.0, 0.0, 0.0, 1.0], image.pixel(2, 2)
  ensure
    Lota::Graphics.origin
  end
end
