# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
      Native::Physics.distance(shape1.__send__(:native), shape2.__send__(:native))
    end

    # The linear stiffness and damping that give a spring between +body1+ and
    # +body2+ the +frequency+, in hertz, and the +damping_ratio+, as an Array
    # of two Floats, matching love.physics.computeLinearStiffness
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_computeLinearStiffness).
    #
    # [body2] The other Lota::Physics::Body, or +nil+ for the World's
    #   ground, as LÖVE takes none.
    #
    # Raises RuntimeError ("Attempt to use destroyed body.") for a
    # destroyed Body.
    #
    # === Example
    #
    #   stiffness, damping = Lota::Physics.compute_linear_stiffness(5, 0.7, body)
    def self.compute_linear_stiffness(frequency, damping_ratio, body1, body2 = nil)
      Native::Physics.compute_linear_stiffness(frequency, damping_ratio, body1.__send__(:native), body2&.__send__(:native))
    end

    # The frequency, in hertz, and the damping ratio of a spring of linear
    # +stiffness+ and +damping+ between +body1+ and +body2+, as an Array of
    # two Floats, the inverse of #compute_linear_stiffness, matching
    # love.physics.computeLinearFrequency
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_computeLinearFrequency).
    #
    # [body2] The other Lota::Physics::Body, or +nil+ for the World's
    #   ground, as LÖVE takes none.
    #
    # Raises RuntimeError ("Attempt to use destroyed body.") for a
    # destroyed Body.
    #
    # === Example
    #
    #   frequency, ratio = Lota::Physics.compute_linear_frequency(joint.stiffness, joint.damping, body)
    def self.compute_linear_frequency(stiffness, damping, body1, body2 = nil)
      Native::Physics.compute_linear_frequency(stiffness, damping, body1.__send__(:native), body2&.__send__(:native))
    end

    # The angular stiffness and damping that give a spring turning +body1+
    # against +body2+ the +frequency+, in hertz, and the +damping_ratio+, as
    # an Array of two Floats, matching love.physics.computeAngularStiffness
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_computeAngularStiffness).
    #
    # [body2] The other Lota::Physics::Body, or +nil+ for the World's
    #   ground, as LÖVE takes none.
    #
    # Raises RuntimeError ("Attempt to use destroyed body.") for a
    # destroyed Body.
    #
    # === Example
    #
    #   stiffness, damping = Lota::Physics.compute_angular_stiffness(5, 0.7, body)
    def self.compute_angular_stiffness(frequency, damping_ratio, body1, body2 = nil)
      Native::Physics.compute_angular_stiffness(frequency, damping_ratio, body1.__send__(:native), body2&.__send__(:native))
    end

    # The frequency, in hertz, and the damping ratio of a spring of angular
    # +stiffness+ and +damping+ turning +body1+ against +body2+, as an Array
    # of two Floats, the inverse of #compute_angular_stiffness, matching
    # love.physics.computeAngularFrequency
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_computeAngularFrequency).
    #
    # [body2] The other Lota::Physics::Body, or +nil+ for the World's
    #   ground, as LÖVE takes none.
    #
    # Raises RuntimeError ("Attempt to use destroyed body.") for a
    # destroyed Body.
    #
    # === Example
    #
    #   frequency, ratio = Lota::Physics.compute_angular_frequency(joint.stiffness, joint.damping, body)
    def self.compute_angular_frequency(stiffness, damping, body1, body2 = nil)
      Native::Physics.compute_angular_frequency(stiffness, damping, body1.__send__(:native), body2&.__send__(:native))
    end

    # A Body in +world+ with a circle on it, as an Array of the
    # Lota::Physics::Body and its Lota::Physics::CircleShape, matching
    # love.physics.newCircleBody (src/modules/physics/box2d/wrap_Physics.cpp,
    # w_newCircleBody), which returns both. Ruby's +new+ makes one object,
    # so a factory that makes two stays a method (rule 17 of
    # doc/contributors/design/translation.md), and returns the two as an Array
    # (rule 4).
    #
    # [type] Symbol <tt>:static</tt>, <tt>:dynamic</tt>, or
    #   <tt>:kinematic</tt> (rule 9 of doc/contributors/design/translation.md),
    #   which LÖVE requires here.
    # [x] Float or Integer position along x of the Body, and of the
    #   circle's center, in pixels.
    # [y] Float or Integer position along y.
    # [radius] Float or Integer radius, in pixels.
    #
    # Raises ArgumentError for a type LÖVE does not know, and
    # RuntimeError for a destroyed World.
    #
    # === Example
    #
    #   body, shape = Lota::Physics.new_circle_body(world, :dynamic, 400, 0, 10)
    def self.new_circle_body(world, type, x, y, radius)
      body, shape = Native::Physics.new_circle_body(world.__send__(:native), EnumName.of(type), x, y, radius)
      [Body.__send__(:from_native, body), CircleShape.__send__(:from_native, shape)]
    end

    # A Body in +world+ with a rectangle on it, as an Array of the
    # Lota::Physics::Body and its Lota::Physics::PolygonShape, matching
    # love.physics.newRectangleBody
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_newRectangleBody), as
    # #new_circle_body is named.
    #
    # [type] Symbol, as #new_circle_body takes it.
    # [x] Float or Integer position along x of the Body, and of the
    #   rectangle's center, in pixels.
    # [y] Float or Integer position along y.
    # [width] Float or Integer width, in pixels.
    # [height] Float or Integer height.
    # [angle] Float or Integer angle of the rectangle on the Body, in
    #   radians.
    #
    # Raises ArgumentError for a type LÖVE does not know, and
    # RuntimeError for a destroyed World.
    #
    # === Example
    #
    #   ground, shape = Lota::Physics.new_rectangle_body(world, :static, 400, 580, 800, 40)
    def self.new_rectangle_body(world, type, x, y, width, height, angle = 0)
      body, shape = Native::Physics.new_rectangle_body(world.__send__(:native), EnumName.of(type), x, y, width, height,
        angle)
      [Body.__send__(:from_native, body), PolygonShape.__send__(:from_native, shape)]
    end

    # A Body in +world+ with a convex polygon on it, as an Array of the
    # Lota::Physics::Body and its Lota::Physics::PolygonShape, matching
    # love.physics.newPolygonBody
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_newPolygonBody), as
    # #new_circle_body is named. The Body is at the vertices' average, and
    # the polygon's vertices are where they are given, in the World.
    #
    # [type] Symbol, as #new_circle_body takes it.
    # [coordinates] An x and a y Float or Integer for each of three to
    #   eight vertices, in pixels, or an Array of them, as LÖVE takes a
    #   table.
    #
    # Raises ArgumentError for a type LÖVE does not know, and
    # RuntimeError, with LÖVE's message, for an odd number of coordinates,
    # for a polygon Box2D cannot make, and for a destroyed World.
    #
    # === Example
    #
    #   body, triangle = Lota::Physics.new_polygon_body(world, :dynamic, 0, 0, 30, 0, 0, 30)
    def self.new_polygon_body(world, type, *coordinates)
      body, shape = Native::Physics.new_polygon_body(world.__send__(:native), EnumName.of(type), coordinates.flatten)
      [Body.__send__(:from_native, body), PolygonShape.__send__(:from_native, shape)]
    end

    # A Body in +world+ with the segment from +x1+, +y1+ to +x2+, +y2+ on
    # it, as an Array of the Lota::Physics::Body and its
    # Lota::Physics::EdgeShape, matching love.physics.newEdgeBody
    # (src/modules/physics/box2d/wrap_Physics.cpp, w_newEdgeBody), as
    # #new_circle_body is named. The segment is where it is given, in the
    # World; the Body is at half of the difference of its points, as LÖVE
    # puts it (src/modules/physics/box2d/Physics.cpp, newEdgeBody).
    #
    # [type] Symbol, as #new_circle_body takes it.
    # [prevx] Nothing, or the previous vertex's x, then its y, and the
    #   next vertex's x and y, all four, for smooth collisions along a run
    #   of edges, as Lota::Physics::EdgeShape.new takes them.
    #
    # Raises ArgumentError for a type LÖVE does not know, and
    # RuntimeError for a destroyed World.
    #
    # === Example
    #
    #   floor, edge = Lota::Physics.new_edge_body(world, :static, 0, 600, 800, 600)
    def self.new_edge_body(world, type, x1, y1, x2, y2, prevx = nil, prevy = nil, nextx = nil, nexty = nil)
      body, shape = Native::Physics.new_edge_body(world.__send__(:native), EnumName.of(type), x1, y1, x2, y2, prevx,
        prevy, nextx, nexty)
      [Body.__send__(:from_native, body), EdgeShape.__send__(:from_native, shape)]
    end

    # A Body in +world+ with a run of edges on it, as an Array of the
    # Lota::Physics::Body and its Lota::Physics::ChainShape, matching
    # love.physics.newChainBody (src/modules/physics/box2d/wrap_Physics.cpp,
    # w_newChainBody), as #new_circle_body is named. The Body is at the
    # vertices' average, and the edges are where they are given, in the
    # World.
    #
    # [type] Symbol, as #new_circle_body takes it.
    # [loop] Whether the last vertex joins the first.
    # [coordinates] An x and a y Float or Integer for each vertex, in
    #   pixels, or an Array of them.
    #
    # Raises ArgumentError for a type LÖVE does not know, and
    # RuntimeError ("Number of vertex components must be a multiple of
    # two.") for none or an odd number of coordinates, and for a destroyed
    # World.
    #
    # === Example
    #
    #   hill, chain = Lota::Physics.new_chain_body(world, :static, false, 0, 600, 400, 500, 800, 600)
    def self.new_chain_body(world, type, loop, *coordinates)
      body, shape = Native::Physics.new_chain_body(world.__send__(:native), EnumName.of(type), loop, coordinates.flatten)
      [Body.__send__(:from_native, body), ChainShape.__send__(:from_native, shape)]
    end

    # The Lota::Physics::Shape that wraps +native+, of its own class, or
    # +nil+. :nodoc:
    private_class_method def self.shape(native)
      case native
      when Native::CircleShape then CircleShape.__send__(:from_native, native)
      when Native::PolygonShape then PolygonShape.__send__(:from_native, native)
      when Native::EdgeShape then EdgeShape.__send__(:from_native, native)
      when Native::ChainShape then ChainShape.__send__(:from_native, native)
      when Native::Shape then Shape.__send__(:from_native, native)
      end
    end

    # The Lota::Physics::Joint that wraps +native+, of its own class, or
    # +nil+. :nodoc:
    private_class_method def self.joint(native)
      case native
      when Native::DistanceJoint then DistanceJoint.__send__(:from_native, native)
      when Native::FrictionJoint then FrictionJoint.__send__(:from_native, native)
      when Native::GearJoint then GearJoint.__send__(:from_native, native)
      when Native::MotorJoint then MotorJoint.__send__(:from_native, native)
      when Native::MouseJoint then MouseJoint.__send__(:from_native, native)
      when Native::PrismaticJoint then PrismaticJoint.__send__(:from_native, native)
      when Native::PulleyJoint then PulleyJoint.__send__(:from_native, native)
      when Native::RevoluteJoint then RevoluteJoint.__send__(:from_native, native)
      when Native::RopeJoint then RopeJoint.__send__(:from_native, native)
      when Native::WeldJoint then WeldJoint.__send__(:from_native, native)
      when Native::WheelJoint then WheelJoint.__send__(:from_native, native)
      when Native::Joint then Joint.__send__(:from_native, native)
      end
    end
  end
end

require_relative "physics/world"
require_relative "physics/body"
require_relative "physics/shape"
require_relative "physics/joint"
require_relative "physics/contact"
