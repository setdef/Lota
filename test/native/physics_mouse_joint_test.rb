# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Physics::MouseJoint's methods (wrap_MouseJoint.cpp), which
# Lövetest does not test: a MouseJoint drags its Body toward a target the
# game moves, with the force, stiffness, and damping the game sets.
class PhysicsMouseJointTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @body = Physics::Body.new(@world, 0, 0, :dynamic)
    Physics::CircleShape.new(@body, 5)
    @joint = Physics::MouseJoint.new(@body, 0, 0)
  end

  # setTarget moves where the joint pulls, and the World's steps then
  # carry the Body there (MouseJoint.cpp, b2MouseJoint::SetTarget).
  def test_the_body_follows_a_target_the_game_moves
    @joint.target = 300, 150
    120.times { @world.update(1 / 60.0) }

    x, y = @body.position

    assert_in_delta 300, x, 1
    assert_in_delta 150, y, 1
  end

  def test_target_reads_back_the_target_set_in_pixels
    assert_equal [0.0, 0.0], @joint.target

    @joint.target = 12.5, -40

    assert_equal [12.5, -40.0], @joint.target
  end

  # MouseJoint's constructor sets the maximum force to 1000 times the
  # Body's mass in Box2D's units, which getMaxForce scales up by the
  # meter (MouseJoint.cpp:39-54, 72-80).
  def test_max_force_defaults_by_the_mass_and_reads_back_what_is_set
    assert_in_delta 1000 * @body.mass * 30, @joint.max_force, 0.01

    @joint.max_force = 250

    assert_in_delta 250, @joint.max_force, 0.0001
  end

  # With no force to pull with, the joint cannot move the Body.
  def test_a_max_force_of_zero_leaves_the_body_where_it_is
    @joint.max_force = 0
    @joint.target = 300, 150
    60.times { @world.update(1 / 60.0) }

    assert_equal [0.0, 0.0], @body.position
  end

  def test_stiffness_and_damping_read_back_what_is_set
    @joint.stiffness = 12.5
    @joint.damping = 0.25

    assert_in_delta 12.5, @joint.stiffness, 0.0001
    assert_in_delta 0.25, @joint.damping, 0.0001
  end

  # LÖVE refuses a stiffness that is not positive (MouseJoint.cpp:82-91).
  def test_a_stiffness_that_is_not_positive_raises_lovees_error
    error = assert_raises(RuntimeError) { @joint.stiffness = 0 }

    assert_equal "MouseJoint Stiffness must be a positive number.", error.message
  end

  def test_a_destroyed_mouse_joint_raises_lovees_error
    @joint.destroy

    %i[target max_force stiffness damping].each do |getter|
      error = assert_raises(RuntimeError) { @joint.public_send(getter) }

      assert_equal "Attempt to use destroyed joint.", error.message
    end
    assert_raises(RuntimeError) { @joint.target = 1, 2 }
    assert_raises(RuntimeError) { @joint.max_force = 1 }
    assert_raises(RuntimeError) { @joint.stiffness = 1 }
    assert_raises(RuntimeError) { @joint.damping = 1 }
  end

  def test_a_setter_takes_only_numbers
    assert_raises(TypeError) { @joint.target = "1", 2 }
    assert_raises(TypeError) { @joint.max_force = nil }
  end
end
