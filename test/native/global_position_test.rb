# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# The arithmetic of Lota::Mouse.global_position (ext/lota/native/
# global_position.hpp), on displays laid out as no computer the tests run
# on has them. LÖVE's Mouse::getGlobalPosition subtracts the origin of
# every display before the pointer's (doc/contributors/upstream/022.md);
# Lota subtracts that display's origin alone, which is what LÖVE answers
# whenever the displays before it start at the desktop's origin.
class GlobalPositionTest < Minitest::Test
  # Three displays of 1920 by 1080, side by side from the desktop's origin.
  SIDE_BY_SIDE = [[0, 0, 1920, 1080], [1920, 0, 1920, 1080], [3840, 0, 1920, 1080]].freeze

  def place(x, y, displays)
    LotaNativeTest.place_on_displays(x, y, displays.flatten)
  end

  def test_a_point_on_the_first_display_keeps_its_desktop_position
    assert_equal [100.0, 200.0, 0], place(100.0, 200.0, SIDE_BY_SIDE)
  end

  # LÖVE answers the same here, as the first display starts at 0.
  def test_a_point_on_the_second_display_is_less_its_origin
    assert_equal [80.0, 200.0, 1], place(2000.0, 200.0, SIDE_BY_SIDE)
  end

  # LÖVE answers 4000 - 0 - 1920 - 3840 = -1760 here.
  def test_a_point_on_the_third_display_is_less_its_origin_alone
    assert_equal [160.0, 500.0, 2], place(4000.0, 500.0, SIDE_BY_SIDE)
  end

  # A display to the left of the primary one starts at a negative x, so
  # LÖVE would add its width to a point on the primary.
  def test_a_point_after_a_display_away_from_the_origin_is_less_its_own_origin
    displays = [[-1280, 0, 1280, 1024], [0, 0, 1920, 1080]]

    assert_equal [50.0, 60.0, 1], place(50.0, 60.0, displays)
    assert_equal [1270.0, 60.0, 0], place(-10.0, 60.0, displays)
  end

  # SDL_PointInRectFloat holds all four edges of a rectangle (SDL_rect.h),
  # so a point on the edge between two displays is on the earlier one.
  def test_a_point_on_the_edge_between_displays_is_on_the_earlier_one
    assert_equal [1920.0, 1080.0, 0], place(1920.0, 1080.0, SIDE_BY_SIDE)
    assert_equal [0.5, 0.0, 1], place(1920.5, 0.0, SIDE_BY_SIDE)
  end

  # LÖVE subtracts in single precision (Mouse.cpp:171-185).
  def test_the_place_is_a_floats_difference
    assert_equal [160.5, 0.25, 2], place(4000.5, 0.25, SIDE_BY_SIDE)
    assert_equal [Float, Float, Integer], place(4000.5, 0.25, SIDE_BY_SIDE).map(&:class)
  end

  # LÖVE reports the first display for a point on none (Mouse.cpp:192-193),
  # and Lota places the point against that display's origin.
  def test_a_point_on_no_display_is_placed_on_the_first
    displays = [[100, 100, 800, 600], [900, 100, 800, 600]]

    assert_equal [-50.0, -40.0, 0], place(50.0, 60.0, displays)
  end

  def test_with_no_displays_a_point_keeps_its_desktop_position
    assert_equal [50.0, 60.0, 0], place(50.0, 60.0, [])
  end
end
