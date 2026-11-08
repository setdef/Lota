# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The methods of Lota::Physics::Contact and World that Lövetest does not
# test (wrap_Contact.cpp, wrap_World.cpp): a contact's tangent speed, its
# destruction, and the deprecated names, each with LÖVE's notice.
class PhysicsContactTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @a = Physics::CircleShape.new(Physics::Body.new(@world, 0, 0, :dynamic), 10)
    @b = Physics::CircleShape.new(Physics::Body.new(@world, 15, 0, :dynamic), 10)
    @world.update(1 / 60.0)
    @contact = @world.contacts.first
  end

  def test_tangent_speed_reads_back_what_is_set
    assert_in_delta 0, @contact.tangent_speed, 0.0001

    @contact.tangent_speed = 2.5

    assert_in_delta 2.5, @contact.tangent_speed, 0.0001
  end

  # A Contact ends when its Shapes stop touching; the engine object then
  # answers that it is destroyed, and its other methods raise LÖVE's error.
  def test_a_contact_whose_shapes_part_is_destroyed
    refute_predicate @contact, :destroyed?

    @b.body.position = 300, 0
    @world.update(1 / 60.0)

    assert_predicate @contact, :destroyed?
    error = assert_raises(RuntimeError) { @contact.tangent_speed = 1 }

    assert_equal "Attempt to use destroyed contact.", error.message
    assert_raises(RuntimeError) { @contact.tangent_speed }
  end

  # Contact:getFixtures is Contact:getShapes under LÖVE 11's name, and its
  # first use prints LÖVE's notice (wrap_Contact.cpp:154-158).
  def test_fixtures_is_shapes_with_a_deprecation_notice
    fixtures = nil
    out = with_deprecation_output { fixtures = @contact.fixtures }

    assert_equal @contact.shapes, fixtures
    assert_match(/\ALota - Warning: .*physics_contact_test\.rb:\d+: Using deprecated method Lota::Physics::Contact#fixtures \(replaced by Lota::Physics::Contact#shapes\)\n\z/, out)
  end

  # World:queryBoundingBox is World:queryShapesInArea under LÖVE 11's name
  # (wrap_World.cpp:188-192).
  def test_query_bounding_box_queries_with_a_deprecation_notice
    found = []
    out = with_deprecation_output { @world.query_bounding_box(-20, -20, 40, 20, :extra) { |shape, extra| found << [shape, extra] } }

    assert_equal [@a, @b].to_set, found.to_set(&:first)
    assert_equal [:extra], found.map(&:last).uniq
    assert_match(/\ALota - Warning: .*physics_contact_test\.rb:\d+: Using deprecated method Lota::Physics::World#query_bounding_box \(renamed to Lota::Physics::World#query_shapes_in_area\)\n\z/, out)
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
