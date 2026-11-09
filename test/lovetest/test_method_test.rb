# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "lovetest_helper"
require_relative "tests/graphics"

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
      assert_coords([4, 4], Lota::Graphics.transform_point(1, 1))
    end
  end

  # A test that runs to its end without asserting anything, and one that
  # skips before it asserts.
  class Unasserted < Lovetest::TestMethod
    def test_nothing
      Lota::Graphics.origin
    end

    def test_skip
      skip("not here")
    end
  end
  # This suite runs them, when it chooses to.
  Minitest::Runnable.runnables.delete(Scaling)
  Minitest::Runnable.runnables.delete(Unasserted)

  # Lövetest fails a test that defines no asserts (vendor/love/testing/
  # classes/TestMethod.lua:486-487), so a translated test that silently
  # stops checking anything fails rather than passing.
  def test_a_test_that_asserts_nothing_fails_as_in_lovetest
    result = Unasserted.new("test_nothing").run

    refute_predicate result, :passed?
    assert_equal ["no asserts defined"], result.failures.map(&:message)
  end

  def test_a_test_that_skips_before_asserting_still_skips
    result = Unasserted.new("test_skip").run

    assert_predicate result, :skipped?
    assert_equal ["not here"], result.failures.map(&:message)
  end

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

  # love.test.graphics.getMeshCullMode ends by setting the mesh cull mode
  # to back (vendor/love/testing/tests/graphics.lua:2005-2012), which
  # every Mesh drawn after it is culled by (Mesh.cpp:812), and which hides
  # this square. GraphicsTest ends each test with the default, none, so
  # a suite that runs after it draws its meshes.
  def test_a_graphics_test_leaves_meshes_drawn_for_the_tests_after_it
    assert_predicate GraphicsTest.new("test_get_mesh_cull_mode").run, :passed?

    mesh = Lota::Graphics::Mesh.new([[0, 0], [4, 0], [4, 4], [0, 4]], :fan)
    canvas = Lota::Graphics::Canvas.new(4, 4)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(mesh)
    Lota::Graphics.pop

    assert_equal [1.0, 1.0, 1.0, 1.0], Lota::Graphics.readback_texture(canvas).pixel(1, 1)
  ensure
    Lota::Graphics.mesh_cull_mode = :none
  end
end
