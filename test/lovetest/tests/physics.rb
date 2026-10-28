# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.physics tests (vendor/love/testing/tests/physics.lua),
# translated to Ruby by ADR 001's rules. They run in the test suite's own
# process (test/lovetest/physics_test.rb) and under lota run
# (test/lovetest/game).
#
# Two kinds of check wait for the maintainer, and are left out where they
# come: those of Body:getType, Shape:getType, and Joint:getType, whose
# Ruby name rule 3 makes type, the name rule 16 gives every LÖVE object
# for Object:type (rake bindings:report); and those that need
# World:setCallbacks, getCallbacks, setContactFilter, or
# getContactFilter, whose Ruby shape is one of Plan 001's design
# questions. So love.test.physics.Contact, which runs inside a contact
# callback, is left out whole, as are love.test.physics.Shape's collision
# checks after its callbacks are set; love.test.physics.World keeps its
# other checks, and the steps between them.
class PhysicsTest < Lovetest::TestMethod
  TYPES = %w[Body Joint Shape World].freeze

  # Lövetest runs a module's tests sorted by name (classes/TestModule.lua:
  # 68-71), so love.test.physics.setMeter, which leaves the meter at 10,
  # runs after every other; Minitest runs them in any order, so each
  # starts at LÖVE's default meter of 30, as it does in Lövetest
  # (src/modules/physics/box2d/Physics.h, DEFAULT_METER).
  def setup
    super
    Lota::Physics.meter = 30
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.physics.Body
  # (vendor/love/testing/tests/physics.lua:12-212): newWorld, newBody, and
  # newRectangleShape become World.new, Body.new, and RectangleShape.new
  # (rule 2), getters drop get (rule 3), setters become writers, of an
  # Array when they take several values (rules 5 and 6), is and has
  # become predicates (rule 8), 'static' and its kind become symbols (rule
  # 9), and the rest is snake_case (rule 13). A function's several results
  # are an Array (rule 4), whose size Lua's # counts. Lua's table of user
  # data becomes a Hash. Lövetest's assertRange becomes Minitest's
  # assert_includes of the Range, and assertNotEquals refute_equal. Its
  # checks of getType are left out.
  def test_body
    # create body
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 0, 0, :static)
    body2 = Lota::Physics::Body.new(world, 30, 30, :dynamic)
    Lota::Physics::RectangleShape.new(body1, 5, 5, 10, 10)
    Lota::Physics::RectangleShape.new(body2, 5, 5, 10, 10)
    assert_object(body1)

    # check shapes
    assert_equal(1, body1.shapes.size, "check shapes total 1")
    assert_equal(1, body2.shapes.size, "check shapes total 2")
    refute_equal(nil, body1.shape, "check shape 1")
    refute_equal(nil, body2.shape, "check shape 2")

    # check body active
    assert_true(body1.active?, "check active by def")

    # check body bullet
    assert_false(body1.bullet?, "check not bullet by def")
    body1.bullet = true
    assert_true(body1.bullet?, "check set bullet")

    # check fixed rotation
    assert_false(body1.fixed_rotation?, "check fix rot def")
    body1.fixed_rotation = true
    assert_true(body1.fixed_rotation?, "check set fix rot")

    # check sleeping/waking
    assert_true(body1.sleeping_allowed?, "check sleep def")
    body1.sleeping_allowed = false
    assert_false(body1.sleeping_allowed?, "check set sleep")
    body1.sleeping_allowed = true
    world.update(1)
    assert_false(body1.awake?, "check fell asleep")
    body1.sleeping_allowed = false
    body1.type = :dynamic
    assert_true(body1.awake?, "check waking up")

    # check touching
    assert_false(body1.touching?(body2))
    body2.position = 5, 5
    world.update(1)
    assert_true(body1.touching?(body2))

    # check children lists
    assert_equal(1, body1.contacts.size, "check contact list")
    assert_equal(0, body1.joints.size, "check joints list")
    Lota::Physics::DistanceJoint.new(body1, body2, 5, 5, 10, 10, true)
    assert_equal(1, body1.joints.size, "check joints list")

    # check local points
    x, y = body1.local_center
    assert_includes(5..6, x, "check local center x")
    assert_includes(5..6, y, "check local center y")
    lx, ly = body1.local_point(10, 10)
    assert_includes(10..11, lx, "check local point x")
    assert_includes(9..10, ly, "check local point y")
    lx1, ly1, lx2, ly2 = body1.local_points(0, 5, 5, 10)
    assert_includes(0..1, lx1, "check local points x 1")
    assert_includes(3..4, ly1, "check local points y 1")
    assert_includes(5..6, lx2, "check local points x 2")
    assert_includes(9..10, ly2, "check local points y 2")

    # check world points
    wx, wy = body1.world_point(10.4, 9)
    assert_includes(10..11, wx, "check world point x")
    assert_includes(10..11, wy, "check world point y")
    wx1, wy1, wx2, wy2 = body1.world_points(0.4, 4, 5.4, 9)
    assert_includes(0..1, wx1, "check world points x 1")
    assert_includes(5..6, wy1, "check world points y 1")
    assert_includes(5..6, wx2, "check world points x 2")
    assert_includes(10..11, wy2, "check world points y 2")

    # check angular damping + velocity
    assert_equal(0, body1.angular_damping, "check angular damping")
    assert_equal(0, body1.angular_velocity, "check angular velocity")

    # check world props
    assert_object(body1.world)
    assert_equal(2, body1.world.body_count, "check world count")
    cx, cy = body1.world_center
    assert_includes(4..5, cx, "check world center x")
    assert_includes(6..7, cy, "check world center y")
    vx, vy = body1.world_vector(5, 10)
    assert_equal(5, vx, "check vector x")
    assert_equal(10, vy, "check vector y")

    # check inertia
    assert_includes(5..6, body1.inertia, "check inertia")

    # check angle
    assert_equal(0, body1.angle, "check def angle")
    body1.angle = 90 * (Math::PI / 180)
    assert_equal((Math::PI / 2 * 100).floor, (body1.angle * 100).floor, "check set angle")

    # check gravity scale
    assert_equal(1, body1.gravity_scale, "check def grav")
    body1.gravity_scale = 2
    assert_equal(2, body1.gravity_scale, "check change grav")

    # check damping
    assert_equal(0, body1.linear_damping, "check def lin damping")
    body1.linear_damping = 0.1
    assert_includes(0..0.2, body1.linear_damping, "check change lin damping")

    # check velocity
    x2, y2 = body1.linear_velocity
    assert_equal(1, x2, "check def lin velocity x")
    assert_equal(1, y2, "check def lin velocity y")
    body1.linear_velocity = 4, 5
    x3, y3 = body1.linear_velocity
    assert_equal(4, x3, "check change lin velocity x")
    assert_equal(5, y3, "check change lin velocity y")

    # check mass
    assert_includes(0.1..0.2, body1.mass, "check def mass")
    body1.mass = 10
    assert_equal(10, body1.mass, "check change mass")
    body1.mass_data = 3, 5, 10, 1
    x4, y4, mass4, inertia4 = body1.mass_data
    assert_equal(3, x4, "check mass data change x")
    assert_equal(5, y4, "check mass data change y")
    assert_equal(10, mass4, "check mass data change mass")
    assert_includes(340..341, inertia4, "check mass data change inertia")
    body1.reset_mass_data
    x5, y5, mass5, inertia5 = body1.mass_data
    assert_includes(5..6, x5, "check mass data reset x")
    assert_includes(5..6, y5, "check mass data reset y")
    assert_includes(0.1..0.2, mass5, "check mass data reset mass")
    assert_includes(5..6, inertia5, "check mass data reset inertia")
    assert_false(body1.custom_mass_data?)

    # check position
    x6, y6 = body1.position
    assert_includes(-1..0, x6, "check position x")
    assert_includes(0..1, y6, "check position y")
    body1.position = 10, 4
    x7, y7 = body1.position
    assert_equal(x7, 10, "check set position x")
    assert_equal(y7, 4, "check set position y")

    # check type
    body1.type = :kinematic
    body1.type = :static

    # check userdata
    assert_nil(body1.user_data, "check user data")
    body1.user_data = { love: "cool" }
    assert_equal("cool", body1.user_data[:love], "check set user data")

    # check x/y direct
    assert_equal(10, body1.x.floor, "check get x")
    assert_equal(4, body1.y.floor, "check get y")
    body1.x = 0
    body1.y = 0
    assert_equal(0, body1.x, "check get x")
    assert_equal(0, body1.y, "check get y")

    # apply angular impulse
    vel = body2.angular_velocity
    assert_includes(0..0, vel, "check velocity before")
    body2.apply_angular_impulse(10)
    vel1 = body2.angular_velocity
    assert_includes(5..6, vel1, "check velocity after 1")

    # apply standard force
    ang1 = body2.angle
    assert_includes(0.1..0.2, ang1, "check initial angle 1")
    body2.apply_force(2, 3)
    world.update(2)
    vel2 = body2.angular_velocity
    ang2 = body2.angle
    assert_includes(-0.1..0, ang2, "check angle after 2")
    assert_includes(1..2, vel2, "check velocity after 2")

    # apply linear impulse
    body2.apply_linear_impulse(-4, -59)
    world.update(1)
    ang3 = body2.angle
    vel3 = body2.angular_velocity
    assert_includes(-2..-1, ang3, "check angle after 3")
    assert_includes(0..1, vel3, "check velocity after 3")

    # apply torque
    body2.apply_torque(4)
    world.update(2)
    ang4 = body2.angle
    vel4 = body2.angular_velocity
    assert_includes(-1..0, ang4, "check angle after 4")
    assert_includes(0..1, vel4, "check velocity after 4")

    # check destroy
    assert_false(body1.destroyed?, "check not destroyed")
    body1.destroy
    assert_true(body1.destroyed?, "check destroyed")
  end

  # Translated to Ruby from love.test.physics.Joint (physics.lua:301-348),
  # by the rules of test_body: newDistanceJoint becomes DistanceJoint.new
  # (rule 2), whose collideConnected follows its anchors. Lua's
  # rx2, ry2 = joint:getReactionTorque(1) takes the one Float it returns
  # and nil, as Ruby's multiple assignment does. Its check of getType is
  # left out.
  def test_joint
    # make joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :dynamic)
    body2 = Lota::Physics::Body.new(world, 20, 20, :dynamic)
    joint = Lota::Physics::DistanceJoint.new(body1, body2, 10, 10, 20, 20, true)
    assert_object(joint)

    # check not destroyed
    assert_false(joint.destroyed?, "check not destroyed")

    # check reaction props
    world.update(1)
    rx1, ry1 = joint.reaction_force(1)
    assert_equal(0, rx1, "check reaction force x")
    assert_equal(0, ry1, "check reaction force y")
    rx2, ry2 = joint.reaction_torque(1)
    assert_equal(0, rx2, "check reaction torque x")
    assert_nil(ry2, "check reaction torque y")

    # check body pointer
    b1, b2 = joint.bodies
    assert_equal(body1.x, b1.x, "check body 1")
    assert_equal(body2.x, b2.x, "check body 2")

    # check joint anchors
    x1, y1, x2, y2 = joint.anchors
    assert_includes(10..11, x1, "check anchor x1")
    assert_includes(10..11, y1, "check anchor y1")
    assert_includes(20..21, x2, "check anchor x2")
    assert_includes(20..21, y2, "check anchor y2")
    assert_true(joint.collide_connected, "check not colliding")

    # test userdata
    assert_nil(joint.user_data, "check no data by def")
    joint.user_data = "hello"
    assert_equal("hello", joint.user_data, "check set userdata")

    # destroy
    joint.destroy
    assert_true(joint.destroyed?, "check destroyed")
  end

  # Translated to Ruby from love.test.physics.Shape (physics.lua:353-504),
  # by the rules of test_body. getCategory's and getMask's several values
  # are an Array (rule 4), so Lua's {shape1:getCategory()} is that Array,
  # and getMask's none, which Lua reads as nil, is its first, nil.
  # setCategory and setMask take their several values as an Array (rule
  # 6). Its check of getType, and its collision checks from line 466 on,
  # which count the calls of a callback World:setCallbacks sets, are left
  # out.
  def test_shape
    # create shape
    world = Lota::Physics::World.new(0, 0, false)
    body1 = Lota::Physics::Body.new(world, 0, 0, :dynamic)
    shape1 = Lota::Physics::RectangleShape.new(body1, 5, 5, 10, 10)
    assert_object(shape1)

    # check child count
    assert_equal(1, shape1.child_count, "check child count")

    # check radius
    assert_includes(0..0.4, shape1.radius, "check radius")

    # check body pointer
    assert_equal(0, shape1.body.x, "check body link")

    # check category
    assert_equal(1, shape1.category.first, "check def category")
    shape1.category = 3, 5, 6
    categories = shape1.category
    assert_equal(14, categories[0] + categories[1] + categories[2], "check set category")

    # check sensor prop
    assert_false(shape1.sensor?, "check sensor def")
    shape1.sensor = true
    assert_true(shape1.sensor?, "check set sensor")
    shape1.sensor = false

    # check not destroyed
    assert_false(shape1.destroyed?, "check not destroyed")

    # check user data
    assert_nil(shape1.user_data, "check no user data")
    shape1.user_data = { test: 14 }
    assert_equal(14, shape1.user_data[:test], "check user data set")

    # check bounding box
    # polygons have an additional skin radius to help with collisions
    # so this wont be 0, 0, 10, 10 as you'd think but has an additional 0.3 padding
    top_left_x, top_left_y, bottom_right_x, bottom_right_y = shape1.compute_aabb(0, 0, 0, 1)
    tlx, tly, brx, bry = shape1.bounding_box(1)
    assert_equal(top_left_x, tlx, "check bbox methods match tlx")
    assert_equal(top_left_y, tly, "check bbox methods match tly")
    assert_equal(bottom_right_x, brx, "check bbox methods match brx")
    assert_equal(bottom_right_y, bry, "check bbox methods match bry")
    assert_equal(top_left_x, top_left_y, "check bbox tl 1")
    assert_includes(-0.3..-0.2, top_left_y, "check bbox tl 2")
    assert_equal(bottom_right_x, bottom_right_y, "check bbox br 1")
    assert_includes(10.3..10.4, bottom_right_x, "check bbox br 2")

    # check density
    assert_equal(1, shape1.density, "check def density")
    shape1.density = 5
    assert_equal(5, shape1.density, "check set density")

    # check mass
    x1, y1, mass1, inertia1 = shape1.mass_data
    assert_includes(5..5.1, x1, "check shape mass pos x")
    assert_includes(5..5.1, y1, "check shape mass pos y")
    assert_includes(0.5..0.6, mass1, "check mass at 1 density")
    assert_includes(0..0.1, inertia1, "check intertia at 1 density")
    _x2, _y2, mass2, inertia2 = shape1.compute_mass(1000)
    assert_includes(111..112, mass2, "check mass at 1000 density")
    assert_includes(7407..7408, inertia2, "check intertia at 1000 density")

    # check friction
    assert_includes(0.2..0.3, shape1.friction, "check def friction")
    shape1.friction = 1
    assert_equal(1, shape1.friction, "check set friction")

    # check restitution
    assert_equal(0, shape1.restitution, "check def restitution")
    shape1.restitution = 0.5
    assert_includes(0.5..0.6, shape1.restitution, "check set restitution")

    # check points
    bodyp = Lota::Physics::Body.new(world, 0, 0, :dynamic)
    shape2 = Lota::Physics::RectangleShape.new(bodyp, 5, 5, 10, 10)
    assert_true(shape2.test_point(5, 5), "check point 5,5")
    assert_true(shape2.test_point(10, 10, 0, 15, 15), "check point 15,15 after translate 10,10")
    assert_false(shape2.test_point(5, 5, 90, 10, 10), "check point 10,10 after translate 5,5,90")
    assert_false(shape2.test_point(10, 10, 90, 5, 5), "check point 5,5 after translate 10,10,90")
    assert_false(shape2.test_point(15, 15), "check point 15,15")

    # check ray cast
    xn1, _yn1, _fraction1 = shape2.ray_cast(-20, -20, 20, 20, 100, 0, 0, 0, 1)
    refute_equal(nil, xn1, "check ray 1 x")
    refute_equal(nil, xn1, "check ray 1 y")
    xn2, yn2, _fraction2 = shape2.ray_cast(10, 10, -150, -150, 100, 0, 0, 0, 1)
    assert_nil(xn2, "check ray 2 x")
    assert_nil(yn2, "check ray 2 y")

    # check filtering
    assert_nil(shape2.mask.first, "check no mask")
    shape2.mask = 1, 2, 3
    assert_equal(3, shape2.mask.size, "check set mask")
    assert_equal(0, shape2.group_index, "check no index")
    shape2.group_index = -1
    assert_equal(-1, shape2.group_index, "check set index")
    cat, mask, group = shape2.filter_data
    assert_equal(1, cat, "check filter cat")
    assert_equal(65528, mask, "check filter mask")
    assert_equal(-1, group, "check filter group")

    # check destroyed
    shape1.destroy
    assert_true(shape1.destroyed?, "check destroyed")
    shape2.destroy
  end

  # Translated to Ruby from love.test.physics.World (physics.lua:508-607),
  # by the rules of test_body. queryShapesInArea's and rayCast's functions
  # become blocks (rule 12), which end with what the Lua functions return,
  # nil and 1, since Ruby's block returns its last value where a Lua
  # function without a return returns nothing; rayCastClosest's and
  # rayCastAny's several values are an Array (rule 4), of which Lua's
  # comparison keeps the first. Its checks of the callbacks
  # World:getCallbacks gives and World:setCallbacks and setContactFilter
  # set are left out, and its steps kept.
  def test_world
    # create new world
    world = Lota::Physics::World.new(0, 0, false)
    body1 = Lota::Physics::Body.new(world, 0, 0, :dynamic)
    rectangle1 = Lota::Physics::RectangleShape.new(body1, 0, 0, 10, 10)
    assert_object(world)

    # check bodies in world
    assert_equal(1, world.bodies.size, "check 1 body")
    assert_equal(0, world.bodies[0].x, "check body prop x")
    assert_equal(0, world.bodies[0].y, "check body prop y")
    world.translate_origin(-10, -10) # check affects bodies
    assert_includes(9..11, world.bodies[0].x, "check body prop change x")
    assert_includes(9..11, world.bodies[0].y, "check body prop change y")
    assert_equal(1, world.body_count, "check 1 body count")

    # check shapes in world
    assert_equal(1, world.shapes_in_area(0, 0, 10, 10).size, "check shapes in area #1")
    assert_equal(0, world.shapes_in_area(20, 20, 30, 30).size, "check shapes in area #1")

    # check world status
    assert_false(world.locked?, "check not updating")
    assert_false(world.sleeping_allowed?, "check no sleep (till brooklyn)")
    world.sleeping_allowed = true
    assert_true(world.sleeping_allowed?, "check can sleep")

    # check world objects
    assert_equal(0, world.joints.size, "check no joints")
    assert_equal(0, world.joint_count, "check no joints count")
    assert_equal(0, world.gravity.first, "check def gravity")
    assert_equal(0, world.contacts.size, "check no contacts")
    assert_equal(0, world.contact_count, "check no contact count")

    # setup so we can collide stuff to call the callbacks
    body2 = Lota::Physics::Body.new(world, 10, 10, :dynamic)
    Lota::Physics::RectangleShape.new(body2, 0, 0, 10, 10)
    world.update(1)
    body2.position = 100, 100
    world.update(1)

    # check point checking
    shapes = 0
    world.query_shapes_in_area(0, 0, 10, 10) do |_x|
      shapes += 1
      nil
    end
    assert_equal(1, shapes, "check shapes in area")

    # check raycast
    world.ray_cast(0, 0, 200, 200) do |_x|
      shapes += 1
      1
    end
    assert_equal(3, shapes, "check shapes in raycast")
    assert_equal(world.ray_cast_closest(0, 0, 200, 200).first, rectangle1, "check closest raycast")
    refute_equal(nil, world.ray_cast_any(0, 0, 200, 200).first, "check any raycast")

    # change collision logic
    world.update(1)
    body2.position = 10, 10
    world.update(1)

    # check gravity
    world.gravity = 1, 1
    assert_equal(1, world.gravity.first, "check grav change")

    # check destruction
    assert_false(world.destroyed?, "check not destroyed")
    world.destroy
    assert_true(world.destroyed?, "check world destroyed")
  end

  # Translated to Ruby from love.test.physics.getDistance
  # (physics.lua:618-626): getDistance becomes distance (rule 3), whose
  # several values are an Array (rule 4), of which Lua's assertRange takes
  # the first.
  def test_get_distance
    # setup two fixtues to check
    world = Lota::Physics::World.new(0, 0, false)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    shape1 = Lota::Physics::EdgeShape.new(body, 0, 0, 5, 5)
    shape2 = Lota::Physics::EdgeShape.new(body, 10, 10, 15, 15)
    # check distance between them
    assert_includes(6..7, Lota::Physics.distance(shape1, shape2).first, "check distance matches")
  end

  # Translated to Ruby from love.test.physics.getMeter (physics.lua:630-634):
  # getMeter becomes meter (rule 3), and setMeter the writer meter=
  # (rule 5).
  def test_get_meter
    # check value set is returned
    Lota::Physics.meter = 30
    assert_equal(30, Lota::Physics.meter, "check meter matches")
  end

  # Translated to Ruby from love.test.physics.newBody, newChainShape,
  # newCircleShape, newDistanceJoint, newEdgeShape, newFrictionJoint,
  # newGearJoint, newMotorJoint, newMouseJoint, newPolygonShape,
  # newPrismaticJoint, newPulleyJoint, newRectangleShape,
  # newRevoluteJoint, newRopeJoint, newWeldJoint, newWheelJoint, and
  # newWorld (physics.lua:639-825): each factory becomes its class's new
  # (rule 2), RectangleShape.new for the PolygonShape newRectangleShape
  # makes, and newPolygonShape's table becomes an Array.
  def test_new_body
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    assert_object(body)
  end

  def test_new_chain_shape
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    assert_object(Lota::Physics::ChainShape.new(body, true, 0, 0, 1, 0, 1, 1, 0, 1))
  end

  def test_new_circle_shape
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    assert_object(Lota::Physics::CircleShape.new(body, 10))
  end

  def test_new_distance_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::DistanceJoint.new(body1, body2, 10, 10, 20, 20, true)
    assert_object(obj)
  end

  def test_new_edge_shape
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    obj = Lota::Physics::EdgeShape.new(body, 0, 0, 10, 10)
    assert_object(obj)
  end

  def test_new_friction_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::FrictionJoint.new(body1, body2, 15, 15, true)
    assert_object(obj)
  end

  def test_new_gear_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :dynamic)
    body2 = Lota::Physics::Body.new(world, 20, 20, :dynamic)
    body3 = Lota::Physics::Body.new(world, 30, 30, :dynamic)
    body4 = Lota::Physics::Body.new(world, 40, 40, :dynamic)
    joint1 = Lota::Physics::PrismaticJoint.new(body1, body2, 10, 10, 20, 20, true)
    joint2 = Lota::Physics::PrismaticJoint.new(body3, body4, 30, 30, 40, 40, true)
    obj = Lota::Physics::GearJoint.new(joint1, joint2, 1, true)
    assert_object(obj)
  end

  def test_new_motor_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::MotorJoint.new(body1, body2, 1)
    assert_object(obj)
  end

  def test_new_mouse_joint
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    obj = Lota::Physics::MouseJoint.new(body, 10, 10)
    assert_object(obj)
  end

  def test_new_polygon_shape
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    obj = Lota::Physics::PolygonShape.new(body, [0, 0, 2, 3, 2, 1, 3, 1, 5, 1])
    assert_object(obj)
  end

  def test_new_prismatic_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::PrismaticJoint.new(body1, body2, 10, 10, 20, 20, true)
    assert_object(obj)
  end

  def test_new_pulley_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::PulleyJoint.new(body1, body2, 10, 10, 20, 20, 15, 15, 25, 25, 1, true)
    assert_object(obj)
  end

  def test_new_rectangle_shape
    world = Lota::Physics::World.new(1, 1, true)
    body = Lota::Physics::Body.new(world, 10, 10, :static)
    shape1 = Lota::Physics::RectangleShape.new(body, 10, 20)
    shape2 = Lota::Physics::RectangleShape.new(body, 10, 10, 40, 30, 10)
    assert_object(shape1)
    assert_object(shape2)
  end

  def test_new_revolute_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::RevoluteJoint.new(body1, body2, 10, 10, true)
    assert_object(obj)
  end

  def test_new_rope_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::RopeJoint.new(body1, body2, 10, 10, 20, 20, 50, true)
    assert_object(obj)
  end

  def test_new_weld_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::WeldJoint.new(body1, body2, 10, 10, true)
    assert_object(obj)
  end

  def test_new_wheel_joint
    world = Lota::Physics::World.new(1, 1, true)
    body1 = Lota::Physics::Body.new(world, 10, 10, :static)
    body2 = Lota::Physics::Body.new(world, 20, 20, :static)
    obj = Lota::Physics::WheelJoint.new(body1, body2, 10, 10, 5, 5, true)
    assert_object(obj)
  end

  def test_new_world
    world = Lota::Physics::World.new(1, 1, true)
    assert_object(world)
  end

  # Translated to Ruby from love.test.physics.setMeter
  # (physics.lua:829-839), by the rules of test_get_meter.
  def test_set_meter
    # set initial meter
    world = Lota::Physics::World.new(1, 1, true)
    Lota::Physics.meter = 30
    body = Lota::Physics::Body.new(world, 300, 300, :dynamic)
    # check changing meter changes pos value relatively
    Lota::Physics.meter = 10
    x, y = body.position
    assert_equal(100, x, "check pos x")
    assert_equal(100, y, "check pos y")
  end
  # SPDX-SnippetEnd
end
