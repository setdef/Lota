# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # Rigid bodies that fall, bounce, roll, and collide, translated from
  # love.physics.
  #
  # A game whose crates topple, whose balls ricochet, or whose ragdolls
  # fold needs a physics engine: something that steps every body forward
  # in time and resolves every collision, the same way every time.
  #
  # Lota::Physics is the one LÖVE runs, Box2D 2.4, through LÖVE's own
  # classes, so bodies move in Lota exactly as they move in LÖVE. Make a
  # World, add Bodies to it, give each Body Shapes, link Bodies with Joints,
  # and call World#update each frame. Distances are in pixels, as in LÖVE,
  # which divides them by the #meter, 30 pixels by default, for Box2D.
  #
  # Use it for anything that should move by forces and collide.
  #
  # === Example
  #
  #   world = Lota::Physics::World.new(0, 9.81 * 30)
  #   ground = Lota::Physics::Body.new(world, 400, 580)
  #   Lota::Physics::RectangleShape.new(ground, 800, 40)
  #   ball = Lota::Physics::Body.new(world, 400, 0, :dynamic)
  #   Lota::Physics::CircleShape.new(ball, 20)
  #   world.update(1 / 60.0)
  module Physics
    # How many pixels make a meter, as an Integer, matching
    # love.physics.getMeter (src/modules/physics/box2d/wrap_Physics.cpp,
    # w_getMeter), which LÖVE pushes as a Lua integer, so a meter of 30.5
    # reads as 30.
    #
    # === Example
    #
    #   Lota::Physics.meter # => 30
    def self.meter
      Native::Physics.meter
    end

    # Sets how many pixels make a meter, matching love.physics.setMeter
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_setMeter).
    #
    # [scale] Float or Integer pixels, at least 1.
    #
    # Every position LÖVE gives or takes is divided by it for Box2D, so a
    # Body already made keeps its place in meters, and reads back at a new
    # place in pixels. Raises RuntimeError ("Physics error: invalid meter")
    # for a +scale+ below 1.
    #
    # === Example
    #
    #   Lota::Physics.meter = 64
    def self.meter=(scale)
      Native::Physics.set_meter(scale)
    end

    # The distance between two Shapes and the two points closest to each
    # other, as an Array of the distance, then the first point's x and y
    # and the second's, matching love.physics.getDistance
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_getDistance).
    #
    # [shape1] Lota::Physics::Shape attached to a Body.
    # [shape2] Lota::Physics::Shape attached to a Body.
    #
    # Raises RuntimeError, with LÖVE's message, for a Shape no longer in a
    # World.
    #
    # === Example
    #
    #   distance, x1, y1, x2, y2 = Lota::Physics.distance(left, right)
    def self.distance(shape1, shape2)
      Native::Physics.distance(shape1.native, shape2.native)
    end

    # The Lota::Physics::Shape that wraps +native+, of its own class, or
    # +nil+. :nodoc:
    def self.shape(native)
      case native
      when Native::CircleShape then CircleShape.from_native(native)
      when Native::PolygonShape then PolygonShape.from_native(native)
      when Native::EdgeShape then EdgeShape.from_native(native)
      when Native::ChainShape then ChainShape.from_native(native)
      when Native::Shape then Shape.from_native(native)
      end
    end

    # The Lota::Physics::Joint that wraps +native+, of its own class, or
    # +nil+. :nodoc:
    def self.joint(native)
      case native
      when Native::DistanceJoint then DistanceJoint.from_native(native)
      when Native::FrictionJoint then FrictionJoint.from_native(native)
      when Native::GearJoint then GearJoint.from_native(native)
      when Native::MotorJoint then MotorJoint.from_native(native)
      when Native::MouseJoint then MouseJoint.from_native(native)
      when Native::PrismaticJoint then PrismaticJoint.from_native(native)
      when Native::PulleyJoint then PulleyJoint.from_native(native)
      when Native::RevoluteJoint then RevoluteJoint.from_native(native)
      when Native::RopeJoint then RopeJoint.from_native(native)
      when Native::WeldJoint then WeldJoint.from_native(native)
      when Native::WheelJoint then WheelJoint.from_native(native)
      when Native::Joint then Joint.from_native(native)
      end
    end
  end
end

require_relative "physics/world"
require_relative "physics/body"
require_relative "physics/shape"
require_relative "physics/joint"
require_relative "physics/contact"
