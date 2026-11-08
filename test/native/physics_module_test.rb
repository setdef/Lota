# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Physics's module functions that Lövetest does not test
# (wrap_Physics.cpp): the springs' stiffness and frequency, each
# computed from the Bodies' masses, as Box2D's b2LinearStiffness and
# b2AngularStiffness compute them.
class PhysicsModuleTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @body = Physics::Body.new(@world, 0, 0, :dynamic)
    Physics::CircleShape.new(@body, 10)
  end

  # A MouseJoint's spring is LÖVE's 5 hertz at a damping ratio of 0.7,
  # computed against the World's ground (MouseJoint.cpp:39-54), which is
  # what compute_linear_stiffness gives with no second Body.
  def test_linear_stiffness_is_what_a_mouse_joint_starts_with
    stiffness, damping = Physics.compute_linear_stiffness(5, 0.7, @body)
    joint = Physics::MouseJoint.new(@body, 0, 0)

    assert_in_delta joint.stiffness, stiffness, joint.stiffness * 0.0001
    assert_in_delta joint.damping, damping, joint.damping * 0.0001
    assert_operator stiffness, :>, 0
  end

  def test_linear_frequency_undoes_linear_stiffness
    other = Physics::Body.new(@world, 50, 0, :dynamic)
    Physics::CircleShape.new(other, 20)
    stiffness, damping = Physics.compute_linear_stiffness(4, 0.5, @body, other)
    frequency, ratio = Physics.compute_linear_frequency(stiffness, damping, @body, other)

    assert_in_delta 4, frequency, 0.001
    assert_in_delta 0.5, ratio, 0.001
  end

  def test_angular_frequency_undoes_angular_stiffness
    stiffness, damping = Physics.compute_angular_stiffness(3, 0.25, @body)
    frequency, ratio = Physics.compute_angular_frequency(stiffness, damping, @body)

    assert_operator stiffness, :>, 0
    assert_in_delta 3, frequency, 0.001
    assert_in_delta 0.25, ratio, 0.001
  end

  # The ground LÖVE takes for a missing second Body is static, so it adds
  # no mass, as a static Body of the game's own does not; a dynamic second
  # Body's mass makes the spring softer.
  def test_the_second_body_defaults_to_the_ground
    static = Physics::Body.new(@world, 50, 0, :static)
    other = Physics::Body.new(@world, 50, 0, :dynamic)
    Physics::CircleShape.new(other, 10)

    assert_equal Physics.compute_linear_stiffness(5, 0.7, @body), Physics.compute_linear_stiffness(5, 0.7, @body, static)
    assert_operator Physics.compute_linear_stiffness(5, 0.7, @body, other).first, :<,
      Physics.compute_linear_stiffness(5, 0.7, @body).first
  end

  def test_a_destroyed_body_raises_lovees_error
    other = Physics::Body.new(@world, 50, 0, :dynamic)
    other.destroy

    error = assert_raises(RuntimeError) { Physics.compute_angular_stiffness(5, 0.7, @body, other) }

    assert_equal "Attempt to use destroyed body.", error.message
    @body.destroy
    assert_raises(RuntimeError) { Physics.compute_linear_frequency(1, 1, @body) }
  end
end
