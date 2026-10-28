# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Physics beyond what Lövetest's tests for it check
# (test/lovetest/tests/physics.rb): one Ruby object for each engine
# object, as LÖVE pushes one Lua value for each; user data that outlives
# its wrapper; the forms of LÖVE's functions chosen by their arguments'
# count; the arguments LÖVE passes on to a query's and a ray's function;
# and the errors LÖVE raises.
class PhysicsBindingsTest < Minitest::Test
  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @body = Physics::Body.new(@world, 0, 0, :dynamic)
  end

  # luax_pushtype pushes the Lua value it pushed before for an object
  # still alive, so Lua's == holds of a Shape read back twice.
  def test_an_engine_object_read_back_is_the_same_ruby_object
    shape = Physics::CircleShape.new(@body, 5)

    assert_same shape, @body.shape
    assert_same shape, @body.shapes.first
    assert_same @body, shape.body
    assert_same @world, @body.world
    assert_same @body, @world.bodies.first
    assert_instance_of Physics::CircleShape, @world.shapes_in_area(-10, -10, 10, 10).first
  end

  # A Lua reference keeps the user data while the Body lives, however long
  # nothing else refers to it.
  def test_user_data_lives_as_long_as_its_body
    @body.user_data = Array.new(3) { |i| "value #{i}" }
    GC.start
    GC.compact if GC.respond_to?(:compact)

    assert_equal ["value 0", "value 1", "value 2"], @body.user_data
    @body.destroy
    assert_raises(RuntimeError) { @body.user_data }
  end

  def test_a_destroyed_body_raises_lovees_error
    @body.destroy
    error = assert_raises(RuntimeError) { @body.x }

    assert_equal "Attempt to use destroyed body.", error.message
    assert @body.destroyed?
  end

  # newCircleShape and newRectangleShape choose their form by how many
  # numbers follow the Body, and refuse any other count.
  def test_shape_factories_choose_their_form_by_their_arguments
    circle = Physics::CircleShape.new(@body, 1, 2, 3)

    assert_in_delta 3, circle.radius
    rectangle = Physics::RectangleShape.new(@body, 10, 10, 4, 2, Math::PI / 2)
    x1, y1, x2, y2 = rectangle.bounding_box

    assert_in_delta 2, x2 - x1, 0.7
    assert_in_delta 4, y2 - y1, 0.7
    assert_equal "Incorrect number of parameters", assert_raises(RuntimeError) { Physics::CircleShape.new(@body, 1, 2) }.message
    assert_raises(RuntimeError) { Physics::RectangleShape.new(@body, 1, 2, 3) }
    assert_equal "Number of vertex components must be a multiple of two.",
      assert_raises(RuntimeError) { Physics::PolygonShape.new(@body, 0, 0, 1) }.message
  end

  # RevoluteJoint, PrismaticJoint, and the like read their second anchor
  # only when there are numbers enough for it (lua_gettop), and their
  # collideConnected after the anchors.
  def test_joint_factories_choose_their_form_by_their_count
    other = Physics::Body.new(@world, 20, 0, :dynamic)
    shared = Physics::RevoluteJoint.new(@body, other, 10, 0)
    apart = Physics::WeldJoint.new(@body, other, 1, 2, 3, 4, true)

    assert_equal [10.0, 0.0, 10.0, 0.0], shared.anchors
    assert_equal false, shared.collide_connected
    [1, 2, 3, 4].zip(apart.anchors).each { |expected, actual| assert_in_delta expected, actual, 1e-5 }
    assert_equal true, apart.collide_connected
    assert_equal [@body, other], shared.bodies
    assert_same shared, @body.joints.find { |joint| joint.is_a?(Physics::RevoluteJoint) }
    assert_equal true, Physics::PulleyJoint.new(@body, other, 0, 0, 1, 1, 0, 0, 1, 1).collide_connected
  end

  # applyForce wakes the Body by default, takes a point, and refuses one
  # number after the force (wrap_Body.cpp:220-250).
  def test_apply_force_reads_its_forms
    @body.apply_force(1, 0, false)
    @body.apply_force(1, 0, 0, 1)

    assert_equal "Wrong number of parameters.", assert_raises(RuntimeError) { @body.apply_force(1, 0, 5) }.message
  end

  # LÖVE passes the arguments after a query's or a ray's function on to
  # it, and stops a query at its function's first false.
  def test_query_and_ray_pass_their_arguments_and_obey_the_block
    Physics::CircleShape.new(@body, 5)
    Physics::CircleShape.new(Physics::Body.new(@world, 2, 0), 5)
    seen = []
    @world.query_shapes_in_area(-10, -10, 10, 10, :extra, 7) do |shape, *rest|
      seen << [shape.class, rest]
      false
    end

    assert_equal [[Physics::CircleShape, [:extra, 7]]], seen
    hits = []
    @world.ray_cast(-20, 0, 20, 0, :more) do |shape, x, y, xn, yn, fraction, *rest|
      hits << [shape, x, y, xn, yn, fraction, rest].map(&:class)
      -1
    end

    assert_equal [Physics::CircleShape, Float, Float, Float, Float, Float, Array], hits.first
    error = assert_raises(RuntimeError) { @world.ray_cast(-20, 0, 20, 0) { :not_a_number } }
    assert_equal "Raycast callback didn't return a number!", error.message
  end

  # A ray that hits nothing returns no values, an empty Array (ADR 001,
  # rule 4).
  def test_a_ray_that_misses_returns_an_empty_array
    assert_equal [], @world.ray_cast_closest(100, 100, 200, 200)
    assert_equal [], @world.ray_cast_any(100, 100, 200, 200)
  end

  # getMeter pushes the meter as a Lua integer.
  def test_the_meter_reads_as_an_integer
    Physics.meter = 30.5

    assert_equal 30, Physics.meter
    assert_equal "Physics error: invalid meter", assert_raises(RuntimeError) { Physics.meter = 0.5 }.message
  ensure
    Physics.meter = 30
  end

  # A Contact's wrapper keeps its World, which a Contact uses when it is
  # destroyed, until the wrapper goes, in whatever order Ruby collects
  # them.
  def test_a_contact_outlives_its_world_safely
    other = Physics::Body.new(@world, 1, 0, :dynamic)
    Physics::CircleShape.new(@body, 5)
    Physics::CircleShape.new(other, 5)
    @world.update(0.01)
    contacts = @world.contacts

    assert_equal 1, contacts.size
    assert_instance_of Physics::Contact, contacts.first
    assert_equal [1, 1], contacts.first.children
    @world = @body = other = nil
    GC.start
    assert(contacts.first.touching?)
  end
end
