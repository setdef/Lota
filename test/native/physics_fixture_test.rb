# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# LÖVE 11's way of giving a Body a Shape, which LÖVE 12 keeps deprecated
# and Lövetest does not test: a Shape made with no Body
# (luax_optbodyforshape, wrap_Physics.cpp:298-305), and newFixture, which
# attaches a copy of one to a Body (wrap_Physics.cpp:282-296,
# Physics.cpp:133-163). Each prints LÖVE's notice on its first use, which
# the tests that check a notice clear first, as the record of deprecated
# names lasts as long as the process.
class PhysicsFixtureTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @body = Physics::Body.new(@world, 0, 0, :dynamic)
  end

  def rounded(values)
    values.map { |value| value.round(3) }
  end

  # Each factory's form without a Body makes a Shape on none, as LÖVE's
  # does when the first argument is not one of its objects.
  def test_each_shape_can_be_made_without_a_body
    circle = Physics::CircleShape.new(5)
    placed = Physics::CircleShape.new(1, 2, 5)
    rectangle = Physics::RectangleShape.new(10, 20)
    polygon = Physics::PolygonShape.new([0, 0, 30, 0, 0, 30])
    edge = Physics::EdgeShape.new(0, 0, 30, 30)
    chain = Physics::ChainShape.new(false, 0, 0, 30, 0, 30, 30)

    [circle, placed, rectangle, polygon, edge, chain].each { |shape| assert_nil shape.body }
    assert_instance_of Physics::CircleShape, circle
    assert_in_delta 5, circle.radius, 0.0001
    assert_equal [1.0, 2.0], rounded(placed.point)
    assert_instance_of Physics::PolygonShape, rectangle
    assert_equal [-5.0, -10.0, 5.0, -10.0, 5.0, 10.0, -5.0, 10.0], rounded(rectangle.points)
    assert_equal 3, polygon.points.size / 2
    assert_equal [0.0, 0.0, 30.0, 30.0], rounded(edge.points)
    assert_equal 3, chain.vertex_count
  end

  # Their first use prints LÖVE's notice for the function variant, naming
  # the line that called it (luax_markdeprecated, runtime.cpp:1074-1091).
  def test_each_form_without_a_body_prints_lovees_notice
    names = %w[CircleShape RectangleShape PolygonShape EdgeShape ChainShape].map { |kind| "Lota::Physics::#{kind}.new" }
    names.each { |name| Lota::Deprecation.instance_variable_get(:@deprecated).delete(name) }
    out = with_deprecation_output do
      Physics::CircleShape.new(5)
      Physics::RectangleShape.new(10, 20)
      Physics::PolygonShape.new(0, 0, 30, 0, 0, 30)
      Physics::EdgeShape.new(0, 0, 30, 30)
      Physics::ChainShape.new(true, 0, 0, 30, 0, 30, 30)
    end

    names.each do |name|
      assert_match(/^Lota - Warning: #{Regexp.escape(__FILE__)}:\d+: Using deprecated function variant in #{Regexp.escape(name)} \(replaced by variant with Body parameter\)$/, out)
    end
  end

  # The forms with a Body print nothing.
  def test_the_forms_with_a_body_are_not_deprecated
    out = with_deprecation_output do
      Physics::CircleShape.new(@body, 5)
      Physics::RectangleShape.new(@body, 10, 20)
      Physics::PolygonShape.new(@body, 0, 0, 30, 0, 0, 30)
      Physics::EdgeShape.new(@body, 0, 0, 30, 30)
      Physics::ChainShape.new(@body, true, 0, 0, 30, 0, 30, 30)
    end

    assert_empty out
  end

  # A Shape on no Body has no fixture, so what only a fixture has raises
  # (Shape::throwIfFixtureNotValid, Shape.cpp:165-169).
  def test_a_shape_without_a_body_has_no_fixture
    circle = Physics::CircleShape.new(5)

    error = assert_raises(RuntimeError) { circle.density }

    assert_equal "Shape must be active in the physics World to use this method.", error.message
  end

  # newFixture attaches a copy of the Shape to the Body at the density
  # given, 1 by default, and leaves the Shape it copied on no Body.
  def test_fixture_attaches_a_copy_of_a_shape_without_a_body
    prototype = Physics::CircleShape.new(3, 4, 10)
    shape = Physics::Fixture.new(@body, prototype, 2)

    assert_instance_of Physics::CircleShape, shape
    refute_same prototype, shape
    assert_same @body, shape.body
    assert_equal [shape], @body.shapes
    assert_in_delta 2, shape.density, 0.0001
    assert_in_delta 10, shape.radius, 0.0001
    assert_equal [3.0, 4.0], rounded(shape.point)
    assert_nil prototype.body
    assert_operator @body.mass, :>, 0
    other = Physics::Fixture.new(Physics::Body.new(@world, 0, 0, :dynamic), Physics::RectangleShape.new(10, 10))

    assert_instance_of Physics::PolygonShape, other
    assert_in_delta 1, other.density, 0.0001
  end

  # newFixture is deprecated, replaced by the shapes' factories with a
  # Body (wrap_Physics.cpp:284).
  def test_fixture_prints_lovees_notice
    Lota::Deprecation.instance_variable_get(:@deprecated).delete("Lota::Physics::Fixture.new")
    prototype = Physics::EdgeShape.new(0, 0, 30, 0)
    out = with_deprecation_output { Physics::Fixture.new(@body, prototype) }

    assert_match(%r{\ALota - Warning: #{Regexp.escape(__FILE__)}:\d+: Using deprecated function Lota::Physics::Fixture\.new \(replaced by Lota::Physics::Circle/Rectangle/Polygon/Edge/ChainShape\.new\)\n\z}, out)
  end

  # Rule 27 of doc/contributors/design/translation.md: newFixture makes a Shape,
  # which records nothing of the factory that made it, so Fixture === is true of
  # every Shape.
  def test_fixture_matches_every_shape
    assert_operator Physics::Fixture, :===, Physics::CircleShape.new(@body, 5)
    assert_operator Physics::Fixture, :===, Physics::Fixture.new(@body, Physics::CircleShape.new(5))
    refute_operator Physics::Fixture, :===, @body
    refute_operator Physics::Fixture, :===, nil
  end

  # newAttachedShape refuses a Shape that is part of the World
  # (Physics.cpp:135-136), and Lota refuses a destroyed Shape, which has
  # nothing left to copy and which LÖVE would read through a null pointer.
  def test_fixture_refuses_a_shape_on_a_body_or_destroyed
    attached = Physics::CircleShape.new(@body, 5)

    error = assert_raises(RuntimeError) { Physics::Fixture.new(@body, attached) }

    assert_equal "The given Shape must not be part of the World.", error.message
    attached.destroy
    error = assert_raises(RuntimeError) { Physics::Fixture.new(@body, attached) }

    assert_equal "Cannot call this method on a destroyed Shape.", error.message
  end

  # luax_checkbody refuses a destroyed Body (wrap_Body.cpp:32-38).
  def test_fixture_refuses_a_destroyed_body
    @body.destroy

    error = assert_raises(RuntimeError) { Physics::Fixture.new(@body, Physics::CircleShape.new(5)) }

    assert_equal "Attempt to use destroyed body.", error.message
  end

  private def with_deprecation_output
    output = Lota::Deprecation.output?
    capture_io { Lota::Deprecation.output = true }
    out, = capture_io { yield }
    out
  ensure
    capture_io { Lota::Deprecation.output = output }
  end
end
