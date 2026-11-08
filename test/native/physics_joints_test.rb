# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The methods of Lota::Physics's Joint classes but MouseJoint
# (test/native/physics_mouse_joint_test.rb), which Lövetest does not test
# (wrap_DistanceJoint.cpp and the other joints' wrap files): each setter
# read back, and each checked by what the World then does with the joined
# Bodies.
class PhysicsJointsTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @ground = Physics::Body.new(@world, 0, 0, :static)
    @body = Physics::Body.new(@world, 60, 0, :dynamic)
    Physics::CircleShape.new(@body, 5)
  end

  def step(seconds = 1, rate = 60)
    (seconds * rate).round.times { @world.update(1.0 / rate) }
  end

  # setLength sets the joint's rest length, which getLength reads back, but
  # Box2D 2.4 holds a joint whose least and greatest lengths are equal at
  # its least, which LÖVE makes the length the joint was made with and
  # never changes, so the Body stays where it was, as in LÖVE
  # (doc/contributors/upstream/007.md).
  def test_a_distance_joint_keeps_its_first_length_as_in_love
    joint = Physics::DistanceJoint.new(@ground, @body, 0, 0, 60, 0)

    assert_in_delta 60, joint.length, 0.001
    joint.length = 30
    step

    assert_in_delta 30, joint.length, 0.001
    assert_in_delta 60, @body.x, 0.5
  end

  def test_a_distance_joint_reads_back_its_spring
    joint = Physics::DistanceJoint.new(@ground, @body, 0, 0, 60, 0)
    joint.stiffness = 12
    joint.damping = 0.5

    assert_in_delta 12, joint.stiffness, 0.0001
    assert_in_delta 0.5, joint.damping, 0.0001
  end

  # A friction joint with no force to spend leaves the Body sliding; with
  # enough, it stops it.
  def test_a_friction_joint_slows_its_body_by_its_max_force
    joint = Physics::FrictionJoint.new(@ground, @body, 60, 0, true)
    joint.max_force = 0
    joint.max_torque = 3

    assert_equal 0.0, joint.max_force
    assert_in_delta 3, joint.max_torque, 0.0001
    @body.linear_velocity = 30, 0
    step(0.5)

    assert_in_delta 30, @body.linear_velocity.first, 0.01
    joint.max_force = 10_000
    step(0.5)

    assert_in_delta 0, @body.linear_velocity.first, 0.01
  end

  def test_a_gear_joint_gives_its_joints_and_its_ratio
    other = Physics::Body.new(@world, 120, 0, :dynamic)
    Physics::CircleShape.new(other, 5)
    first = Physics::RevoluteJoint.new(@ground, @body, 60, 0)
    second = Physics::RevoluteJoint.new(@ground, other, 120, 0)
    gear = Physics::GearJoint.new(first, second, 2)

    assert_equal [first, second], gear.joints
    assert_in_delta 2, gear.ratio, 0.0001
    gear.ratio = 3

    assert_in_delta 3, gear.ratio, 0.0001
  end

  # A motor joint drives the second Body to its linear offset from the
  # first.
  def test_a_motor_joint_drives_its_body_to_the_offset
    joint = Physics::MotorJoint.new(@ground, @body)
    joint.max_force = 10_000
    joint.linear_offset = 90, 30

    assert_equal [90.0, 30.0], joint.linear_offset.map { |value| value.round(3) }
    step(2)

    assert_in_delta 90, @body.x, 1
    assert_in_delta 30, @body.y, 1
  end

  def test_a_motor_joint_reads_back_its_settings
    joint = Physics::MotorJoint.new(@ground, @body)
    joint.angular_offset = 0.5
    joint.max_force = 20
    joint.max_torque = 30
    joint.correction_factor = 0.75

    assert_in_delta 0.5, joint.angular_offset, 0.0001
    assert_in_delta 20, joint.max_force, 0.001
    assert_in_delta 30, joint.max_torque, 0.001
    assert_in_delta 0.75, joint.correction_factor, 0.0001
  end

  # A prismatic joint's motor slides the Body along the axis, and its
  # limits stop it.
  def test_a_prismatic_joint_slides_by_its_motor_within_its_limits
    joint = Physics::PrismaticJoint.new(@ground, @body, 60, 0, 1, 0)

    assert_equal [1.0, 0.0], joint.axis.map { |value| value.round(4) }
    joint.motor_enabled = true
    joint.max_motor_force = 10_000
    joint.motor_speed = 30
    joint.limits_enabled = true
    joint.limits = -15, 15

    assert_predicate joint, :motor_enabled?
    assert_predicate joint, :limits_enabled?
    assert_equal [-15.0, 15.0], joint.limits.map { |value| value.round(3) }
    step(2)

    assert_in_delta 15, joint.joint_translation, 0.5
    assert_in_delta 75, @body.x, 0.5
    assert_operator joint.motor_force(60), :>, 0
  end

  def test_a_prismatic_joint_reads_back_each_setting
    joint = Physics::PrismaticJoint.new(@ground, @body, 60, 0, 0, 1)
    joint.lower_limit = -3
    joint.upper_limit = 6
    joint.motor_speed = 2
    joint.max_motor_force = 5

    assert_in_delta(-3, joint.lower_limit, 0.001)
    assert_in_delta 6, joint.upper_limit, 0.001
    assert_in_delta 2, joint.motor_speed, 0.0001
    assert_in_delta 5, joint.max_motor_force, 0.001
    assert_in_delta 0, joint.joint_speed, 0.0001
    assert_in_delta 0, joint.reference_angle, 0.0001
    refute_predicate joint, :motor_enabled?
  end

  def test_a_pulley_joint_gives_its_anchors_lengths_and_ratio
    other = Physics::Body.new(@world, 120, 60, :dynamic)
    Physics::CircleShape.new(other, 5)
    joint = Physics::PulleyJoint.new(@body, other, 60, -60, 120, -60, 60, 0, 120, 60, 2)

    assert_equal [60.0, -60.0, 120.0, -60.0], joint.ground_anchors.map { |value| value.round(3) }
    assert_in_delta 60, joint.length_a, 0.001
    assert_in_delta 120, joint.length_b, 0.001
    assert_in_delta 2, joint.ratio, 0.0001
  end

  # A revolute joint's motor turns the Body about the anchor, and its
  # limits stop it.
  def test_a_revolute_joint_turns_by_its_motor_within_its_limits
    joint = Physics::RevoluteJoint.new(@ground, @body, 60, 0)
    joint.motor_enabled = true
    joint.max_motor_torque = 10_000
    joint.motor_speed = 1
    joint.limits_enabled = true
    joint.limits = -0.5, 0.5

    assert_predicate joint, :motor_enabled?
    assert_equal [-0.5, 0.5], joint.limits
    step(2)

    assert_in_delta 0.5, joint.joint_angle, 0.02
    assert_in_delta 0.5, @body.angle, 0.02
    assert_operator joint.motor_torque(60), :>, 0
  end

  # Box2D asserts that the lower limit is not above the upper, which LÖVE
  # raises as its error (b2_settings.cpp, loveAssert).
  def test_a_revolute_joint_refuses_limits_out_of_order
    joint = Physics::RevoluteJoint.new(@ground, @body, 60, 0)
    error = assert_raises(RuntimeError) { joint.limits = 1, -1 }

    assert_equal "Box2D assertion failed: lower <= upper", error.message
  end

  def test_a_revolute_joint_reads_back_each_setting
    joint = Physics::RevoluteJoint.new(@ground, @body, 60, 0, 60, 0, false, 0.25)
    joint.lower_limit = -1
    joint.upper_limit = 2
    joint.motor_speed = 3
    joint.max_motor_torque = 4

    assert_in_delta(-1, joint.lower_limit, 0.0001)
    assert_in_delta 2, joint.upper_limit, 0.0001
    assert_in_delta 3, joint.motor_speed, 0.0001
    assert_in_delta 4, joint.max_motor_torque, 0.001
    assert_in_delta 0.25, joint.reference_angle, 0.0001
    assert_in_delta 0, joint.joint_speed, 0.0001
    refute_predicate joint, :limits_enabled?
  end

  # A rope joint lets its Body no farther than its maximum length.
  def test_a_rope_joint_keeps_its_body_within_its_max_length
    joint = Physics::RopeJoint.new(@ground, @body, 0, 0, 60, 0, 90)

    assert_in_delta 90, joint.max_length, 0.001
    joint.max_length = 75
    @body.linear_velocity = 300, 0
    step

    assert_in_delta 75, joint.max_length, 0.001
    assert_operator @body.x, :<=, 75.5
  end

  def test_a_weld_joint_reads_back_its_spring_and_angle
    joint = Physics::WeldJoint.new(@ground, @body, 60, 0, 60, 0, false, 0.5)
    joint.stiffness = 7
    joint.damping = 0.25

    assert_in_delta 7, joint.stiffness, 0.0001
    assert_in_delta 0.25, joint.damping, 0.0001
    assert_in_delta 0.5, joint.reference_angle, 0.0001
  end

  # A wheel joint's motor spins the wheel; its suspension's spring is
  # read and set under both of LÖVE's names, which are one setting.
  def test_a_wheel_joint_spins_by_its_motor
    joint = Physics::WheelJoint.new(@ground, @body, 60, 0, 0, 1)

    assert_equal [0.0, 1.0], joint.axis.map { |value| value.round(4) }
    joint.motor_enabled = true
    joint.max_motor_torque = 10_000
    joint.motor_speed = 2
    step

    assert_predicate joint, :motor_enabled?
    assert_in_delta 2, @body.angular_velocity, 0.01
    assert_in_delta 2, joint.motor_speed, 0.0001
    assert_in_delta 10_000, joint.max_motor_torque, 0.1
    assert_operator joint.motor_torque(60).abs, :>=, 0
    assert_in_delta 0, joint.joint_translation, 0.01
    assert_in_delta 0, joint.joint_speed, 0.01
  end

  def test_a_wheel_joint_spring_has_two_names_for_one_setting
    joint = Physics::WheelJoint.new(@ground, @body, 60, 0, 0, 1)
    joint.spring_stiffness = 9
    joint.spring_damping = 0.75

    assert_in_delta 9, joint.stiffness, 0.0001
    assert_in_delta 0.75, joint.damping, 0.0001
    joint.stiffness = 4
    joint.damping = 0.5

    assert_in_delta 4, joint.spring_stiffness, 0.0001
    assert_in_delta 0.5, joint.spring_damping, 0.0001
  end

  def test_a_destroyed_joint_raises_lovees_error
    joints = [
      [Physics::DistanceJoint.new(@ground, @body, 0, 0, 60, 0), :length],
      [Physics::FrictionJoint.new(@ground, @body, 60, 0), :max_force],
      [Physics::MotorJoint.new(@ground, @body), :linear_offset],
      [Physics::PrismaticJoint.new(@ground, @body, 60, 0, 1, 0), :limits],
      [Physics::RevoluteJoint.new(@ground, @body, 60, 0), :limits],
      [Physics::RopeJoint.new(@ground, @body, 0, 0, 60, 0, 90), :max_length],
      [Physics::WeldJoint.new(@ground, @body, 60, 0), :reference_angle],
      [Physics::WheelJoint.new(@ground, @body, 60, 0, 0, 1), :axis],
    ]
    joints.each do |joint, getter|
      joint.destroy
      error = assert_raises(RuntimeError) { joint.public_send(getter) }

      assert_equal "Attempt to use destroyed joint.", error.message
    end
  end
end
