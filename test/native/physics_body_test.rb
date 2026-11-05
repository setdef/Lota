# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Physics::Body's methods that Lövetest does not test
# (wrap_Body.cpp): waking and sleeping, activity, the transform and
# kinematic state, spin, inertia, and the vectors and velocities of a
# Body's points, each checked by what the World then does with the Body.
class PhysicsBodyTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, true)
    @body = Physics::Body.new(@world, 0, 0, :dynamic)
    Physics::CircleShape.new(@body, 5)
  end

  # A Body at rest sleeps after Box2D's half a second (b2_timeToSleep),
  # and setAwake wakes it, or puts it back to sleep.
  def test_awake_wakes_a_sleeping_body_and_puts_it_to_sleep
    60.times { @world.update(1 / 60.0) }

    refute_predicate @body, :awake?
    @body.awake = true

    assert_predicate @body, :awake?
    @body.awake = false

    refute_predicate @body, :awake?
  end

  # An inactive Body is out of the World's step: its velocity moves it
  # only once it is active again.
  def test_an_inactive_body_does_not_move
    @body.linear_velocity = 30, 0
    @body.active = false
    @world.update(1)

    refute_predicate @body, :active?
    assert_equal [0.0, 0.0], @body.position
    @body.active = true
    @world.update(1)

    assert_predicate @body, :active?
    assert_in_delta 30, @body.x, 0.01
  end

  def test_transform_moves_and_turns_the_body_at_once
    @body.transform = 15, -30, 0.5

    x, y, angle = @body.transform

    assert_in_delta 15, x, 0.0001
    assert_in_delta(-30, y, 0.0001)
    assert_in_delta 0.5, angle, 0.0001
    assert_in_delta 0.5, @body.angle, 0.0001
  end

  # setKinematicState sets the position, angle, and both velocities, and
  # a step then moves the Body by them.
  def test_kinematic_state_reads_back_and_drives_the_step
    @body.kinematic_state = 30, 60, 0.25, 30, 0, 1

    expected = [30, 60, 0.25, 30, 0, 1]
    @body.kinematic_state.zip(expected) { |got, want| assert_in_delta want, got, 0.0001 }
    @world.update(0.5)

    x, _, angle, = @body.kinematic_state

    assert_in_delta 45, x, 0.01
    assert_in_delta 0.75, angle, 0.01
  end

  def test_angular_velocity_damping_and_inertia_read_back_what_is_set
    @body.angular_velocity = 2
    @body.angular_damping = 0.5
    @body.inertia = 40

    assert_in_delta 2, @body.angular_velocity, 0.0001
    assert_in_delta 0.5, @body.angular_damping, 0.0001
    assert_in_delta 40, @body.inertia, 0.001
    assert_predicate @body, :custom_mass_data?
  end

  def test_angular_damping_slows_the_spin
    @body.angular_velocity = 2
    @body.angular_damping = 5
    @world.update(0.5)

    assert_operator @body.angular_velocity, :<, 1
  end

  # A Body turned a quarter turn sees the world's x axis as its own -y.
  def test_local_vector_turns_a_world_vector_into_the_body_frame
    @body.angle = Math::PI / 2
    x, y = @body.local_vector(1, 0)

    assert_in_delta 0, x, 0.0001
    assert_in_delta(-1, y, 0.0001)
  end

  # A Body spinning at a radian a second about its center moves its point
  # ten pixels to the right at ten pixels a second, down the screen.
  def test_the_velocity_of_a_point_of_a_spinning_body
    @body.angular_velocity = 1
    world_x, world_y = @body.linear_velocity_from_world_point(10, 0)
    @body.angle = Math::PI / 2
    local_x, local_y = @body.linear_velocity_from_local_point(10, 0)

    assert_in_delta 0, world_x, 0.0001
    assert_in_delta 10, world_y, 0.0001
    assert_in_delta(-10, local_x, 0.0001)
    assert_in_delta 0, local_y, 0.0001
  end

  # Body:getFixtures is Body:getShapes under LÖVE 11's name, and its
  # first use prints LÖVE's notice (wrap_Body.cpp:630-634).
  def test_fixtures_is_shapes_with_a_deprecation_notice
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    fixtures = nil
    out, = capture_io { fixtures = @body.fixtures }

    assert_equal @body.shapes, fixtures
    assert_match(/\ALota - Warning: .*physics_body_test\.rb:\d+: Using deprecated method Lota::Physics::Body#fixtures \(replaced by Lota::Physics::Body#shapes\)\n\z/, out)
  ensure
    capture_io { Lota::Deprecation.output = output }
  end

  def test_a_destroyed_body_raises_lovees_error
    @body.destroy

    [
      -> { @body.awake = true },
      -> { @body.active = true },
      -> { @body.transform },
      -> { @body.transform = 1, 2, 3 },
      -> { @body.kinematic_state },
      -> { @body.kinematic_state = 1, 2, 3, 4, 5, 6 },
      -> { @body.angular_velocity = 1 },
      -> { @body.angular_damping = 1 },
      -> { @body.inertia = 1 },
      -> { @body.local_vector(1, 0) },
      -> { @body.linear_velocity_from_world_point(1, 0) },
      -> { @body.linear_velocity_from_local_point(1, 0) },
    ].each do |call|
      error = assert_raises(RuntimeError, &call)

      assert_equal "Attempt to use destroyed body.", error.message
    end
  end
end
