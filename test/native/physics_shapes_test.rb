# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The methods of Lota::Physics's Shape classes that Lövetest does not test
# (wrap_Shape.cpp, wrap_CircleShape.cpp, wrap_PolygonShape.cpp,
# wrap_EdgeShape.cpp, wrap_ChainShape.cpp): each shape's geometry read
# back in pixels, the setters' effect on collisions and mass, and the
# deprecated names, each with LÖVE's notice.
class PhysicsShapesTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @body = Physics::Body.new(@world, 0, 0, :dynamic)
  end

  def test_a_circle_reads_back_its_radius_and_center
    circle = Physics::CircleShape.new(@body, 3, 4, 5)

    assert_in_delta 5, circle.radius, 0.0001
    assert_equal [3.0, 4.0], circle.point.map { |value| value.round(4) }
    circle.radius = 10
    circle.point = -6, 2

    assert_in_delta 10, circle.radius, 0.0001
    assert_equal [-6.0, 2.0], circle.point.map { |value| value.round(4) }
  end

  # A larger circle is a heavier one once the Body's mass is reset from
  # its Shapes.
  def test_a_circle_radius_changes_the_mass
    circle = Physics::CircleShape.new(@body, 5)
    small = @body.mass
    circle.radius = 10
    @body.reset_mass_data

    assert_in_delta small * 4, @body.mass, small * 0.001
  end

  # Box2D keeps a polygon's vertices in the order of the convex hull it
  # computes (b2PolygonShape::Set), which getPoints gives back.
  def test_a_polygon_gives_its_vertices_and_validates
    triangle = Physics::PolygonShape.new(@body, 0, 0, 30, 0, 0, 30)

    assert_equal [30.0, 0.0, 0.0, 30.0, 0.0, 0.0], triangle.points.map { |value| value.round(4) }
    assert triangle.validate
    assert_equal [-5.0, -5.0, 5.0, -5.0, 5.0, 5.0, -5.0, 5.0],
      Physics::RectangleShape.new(@body, 10, 10).points.map { |value| value.round(4) }
  end

  def test_an_edge_gives_its_points_and_its_neighbors
    edge = Physics::EdgeShape.new(@body, 0, 0, 30, 15)

    assert_equal [0.0, 0.0, 30.0, 15.0], edge.points.map { |value| value.round(4) }
    edge.next_vertex = 60, 15
    edge.previous_vertex = -30, 0

    assert_equal [60.0, 15.0], edge.next_vertex.map { |value| value.round(4) }
    assert_equal [-30.0, 0.0], edge.previous_vertex.map { |value| value.round(4) }
  end

  def test_a_chain_gives_its_vertices_one_by_one_and_all_together
    chain = Physics::ChainShape.new(@body, false, 0, 0, 30, 0, 30, 30)

    assert_equal 3, chain.vertex_count
    assert_equal [0.0, 0.0, 30.0, 0.0, 30.0, 30.0], chain.points.map { |value| value.round(4) }
    assert_equal [30.0, 0.0], chain.point(2).map { |value| value.round(4) }
    error = assert_raises(RuntimeError) { chain.point(4) }

    assert_equal "Physics error: index out of bounds", error.message
  end

  def test_a_chain_sets_its_neighbors
    chain = Physics::ChainShape.new(@body, false, 0, 0, 30, 0, 30, 30)
    chain.next_vertex = 60, 30
    chain.previous_vertex = -30, 0

    assert_equal [60.0, 30.0], chain.next_vertex.map { |value| value.round(4) }
    assert_equal [-30.0, 0.0], chain.previous_vertex.map { |value| value.round(4) }
  end

  # ChainShape:getChildEdge makes an EdgeShape of one edge, on no Body,
  # and its first use prints LÖVE's notice (wrap_ChainShape.cpp:55-65).
  def test_child_edge_makes_an_edge_with_a_deprecation_notice
    chain = Physics::ChainShape.new(@body, false, 0, 0, 30, 0, 30, 30)
    edge = nil
    out = with_deprecation_output { edge = chain.child_edge(2) }

    assert_instance_of Physics::EdgeShape, edge
    assert_equal [30.0, 0.0, 30.0, 30.0], edge.points.map { |value| value.round(4) }
    assert_match(/\ALota - Warning: .*physics_shapes_test\.rb:\d+: Using deprecated method Lota::Physics::ChainShape#child_edge\n\z/, out)
  end

  # setFilterData sets the categories, the mask, and the group at once,
  # and two Shapes whose masks leave each other out never touch.
  def test_filter_data_sets_what_collides
    shape = Physics::CircleShape.new(@body, 5)
    shape.filter_data = 2, 0xFFFF & ~4, -1

    assert_equal [2, 0xFFFF & ~4, -1], shape.filter_data
    assert_equal [2], shape.category
    other = Physics::CircleShape.new(Physics::Body.new(@world, 3, 0, :dynamic), 5)
    other.filter_data = 4, 0xFFFF, 0
    @world.update(1 / 60.0)

    assert_empty @world.contacts
  end

  # Fixture:getShape gave a fixture's Shape; a Shape is its own fixture in
  # LÖVE 12, so it gives itself, and its first use prints LÖVE's notice
  # (wrap_Shape.cpp:170-176).
  def test_shape_is_the_shape_itself_with_a_deprecation_notice
    shape = Physics::CircleShape.new(@body, 5)
    found = nil
    out = with_deprecation_output { found = shape.shape }

    assert_same shape, found
    assert_match(/\ALota - Warning: .*physics_shapes_test\.rb:\d+: Using deprecated method Lota::Physics::Shape#shape\n\z/, out)
  end

  def test_a_setter_takes_only_numbers
    assert_raises(TypeError) { Physics::CircleShape.new(@body, 5).radius = "5" }
    assert_raises(TypeError) { Physics::CircleShape.new(@body, 5).filter_data = "1", 1, 1 }
  end

  private def with_deprecation_output
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    out, = capture_io { yield }
    out
  ensure
    capture_io { Lota::Deprecation.output = output }
  end
end
