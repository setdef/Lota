# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Physics's body factories, which Lövetest does not test: LÖVE's
# newCircleBody, newRectangleBody, newPolygonBody, newEdgeBody, and
# newChainBody each make a Body and a Shape on it and return both
# (wrap_Physics.cpp:85-280), so each is a module function that returns
# the two as an Array (rules 17 and 4 of
# doc/contributors/design/translation.md). Where each puts the Body and its
# Shape is Physics.cpp's (lines 63-131).
class PhysicsBodyFactoriesTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
  end

  def rounded(values)
    values.map { |value| value.round(3) }
  end

  # newCircleBody puts the Body at x, y, and the circle at its origin.
  def test_a_circle_body_is_a_body_and_its_circle
    body, circle = Physics.new_circle_body(@world, :dynamic, 30, 60, 15)

    assert_instance_of Physics::Body, body
    assert_instance_of Physics::CircleShape, circle
    assert_same body, circle.body
    assert_equal [circle], body.shapes
    assert_equal :dynamic, body.get_type
    assert_equal [30.0, 60.0], body.position
    assert_in_delta 15, circle.radius, 0.0001
    assert_equal [0.0, 0.0], rounded(circle.point)
    assert_includes @world.bodies, body
    assert_operator body.mass, :>, 0
  end

  # newRectangleBody puts the Body at x, y, and the rectangle around its
  # origin, turned by the angle.
  def test_a_rectangle_body_is_a_body_and_its_rectangle
    body, rectangle = Physics.new_rectangle_body(@world, :static, 100, 50, 20, 10)

    assert_instance_of Physics::PolygonShape, rectangle
    assert_same body, rectangle.body
    assert_equal :static, body.get_type
    assert_equal [100.0, 50.0], body.position
    assert_equal [-10.0, -5.0, 10.0, -5.0, 10.0, 5.0, -10.0, 5.0], rounded(rectangle.points)
    _, turned = Physics.new_rectangle_body(@world, :static, 0, 0, 20, 10, Math::PI / 2)

    assert_equal [5.0, -10.0, 5.0, 10.0, -5.0, 10.0, -5.0, -10.0], rounded(turned.points)
  end

  # newPolygonBody puts the Body at the vertices' average and the polygon
  # where its vertices were given, as numbers or as one Array.
  def test_a_polygon_body_is_at_the_average_of_its_vertices
    body, triangle = Physics.new_polygon_body(@world, :dynamic, 0, 0, 30, 0, 0, 30)

    assert_instance_of Physics::PolygonShape, triangle
    assert_same body, triangle.body
    assert_equal [10.0, 10.0], rounded(body.position)
    assert_equal [0.0, 0.0, 30.0, 0.0, 0.0, 30.0].sort, rounded(body.world_points(*triangle.points)).sort
    other, = Physics.new_polygon_body(@world, :dynamic, [0, 0, 30, 0, 0, 30])

    assert_equal [10.0, 10.0], rounded(other.position)
  end

  # newEdgeBody puts the Body at half the difference of the two points,
  # as Physics.cpp computes it (lines 96-104), and the edge where it was
  # given; given the previous and next vertices too, it keeps them.
  def test_an_edge_body_keeps_its_edge_where_it_was_given
    body, edge = Physics.new_edge_body(@world, :static, 0, 600, 800, 600)

    assert_instance_of Physics::EdgeShape, edge
    assert_same body, edge.body
    assert_equal [400.0, 0.0], rounded(body.position)
    assert_equal [0.0, 600.0, 800.0, 600.0], rounded(body.world_points(*edge.points))
    smooth, edge = Physics.new_edge_body(@world, :static, 0, 0, 30, 0, -30, 0, 60, 0)

    assert_equal [15.0, 0.0], rounded(smooth.position)
    assert_equal [-45.0, 0.0], rounded(edge.previous_vertex)
    assert_equal [45.0, 0.0], rounded(edge.next_vertex)
  end

  # newChainBody puts the Body at the vertices' average and the chain
  # where its vertices were given. A loop repeats its first vertex at its
  # end, as Box2D's b2ChainShape::CreateLoop makes it, so three vertices
  # are four.
  def test_a_chain_body_is_at_the_average_of_its_vertices
    body, chain = Physics.new_chain_body(@world, :static, false, 0, 0, 30, 0, 30, 30)

    assert_instance_of Physics::ChainShape, chain
    assert_same body, chain.body
    assert_equal [20.0, 10.0], rounded(body.position)
    assert_equal [0.0, 0.0, 30.0, 0.0, 30.0, 30.0], rounded(body.world_points(*chain.points))
    _, loop = Physics.new_chain_body(@world, :static, true, [0, 0, 30, 0, 30, 30])

    assert_equal 4, loop.vertex_count
  end

  # Each factory requires the Body's type, and raises luax_enumerror's
  # error for a name LÖVE does not know (wrap_Physics.cpp:89-92).
  def test_an_unknown_body_type_raises
    error = assert_raises(ArgumentError) { Physics.new_circle_body(@world, :flying, 0, 0, 1) }

    assert_match(/\AInvalid Body type 'flying', expected one of: /, error.message)
    assert_raises(ArgumentError) { Physics.new_rectangle_body(@world, :flying, 0, 0, 1, 1) }
    assert_raises(ArgumentError) { Physics.new_polygon_body(@world, :flying, 0, 0, 1, 0, 0, 1) }
    assert_raises(ArgumentError) { Physics.new_edge_body(@world, :flying, 0, 0, 1, 1) }
    assert_raises(ArgumentError) { Physics.new_chain_body(@world, :flying, false, 0, 0, 1, 1) }
  end

  # LÖVE's messages for vertices it cannot use (wrap_Physics.cpp:150-151
  # and 243-244, Physics.cpp:200-204).
  def test_vertices_lovee_cannot_use_raise_its_errors
    odd = "Number of vertex components must be a multiple of two."

    assert_equal odd, assert_raises(RuntimeError) { Physics.new_polygon_body(@world, :static, 0, 0, 1) }.message
    assert_equal odd, assert_raises(RuntimeError) { Physics.new_chain_body(@world, :static, false) }.message
    assert_equal odd, assert_raises(RuntimeError) { Physics.new_chain_body(@world, :static, false, 0, 0, 1) }.message
    assert_equal "Expected a minimum of 3 vertices, got 2.",
      assert_raises(RuntimeError) { Physics.new_polygon_body(@world, :static, 0, 0, 1, 1) }.message
  end

  # luax_checkworld refuses a destroyed World (wrap_World.cpp:30-36).
  def test_a_destroyed_world_raises_lovees_error
    @world.destroy

    [
      -> { Physics.new_circle_body(@world, :static, 0, 0, 1) },
      -> { Physics.new_rectangle_body(@world, :static, 0, 0, 1, 1) },
      -> { Physics.new_polygon_body(@world, :static, 0, 0, 1, 0, 0, 1) },
      -> { Physics.new_edge_body(@world, :static, 0, 0, 1, 1) },
      -> { Physics.new_chain_body(@world, :static, false, 0, 0, 1, 1) },
    ].each do |factory|
      assert_equal "Attempt to use destroyed world.", assert_raises(RuntimeError) { factory.call }.message
    end
  end
end
