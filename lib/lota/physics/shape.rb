# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Physics
    # The geometry of a Body, which gives it its mass and what it collides
    # with, matching LÖVE's Shape (src/modules/physics/box2d/Shape.h), which
    # in LÖVE 12 is also what LÖVE 11 called a Fixture.
    #
    # Each Shape is of one of its subclasses: CircleShape, PolygonShape
    # (which RectangleShape.new makes), EdgeShape, or ChainShape. LÖVE's
    # Shape:getType, whose name rule 16 gives Lota::Object#type, waits for
    # the maintainer.
    #
    # === Example
    #
    #   shape = Lota::Physics::RectangleShape.new(body, 10, 10)
    #   shape.friction = 0.5
    class Shape
      include Object

      # The engine's Shape, for Lota's own modules. :nodoc:
      attr_reader :native

      # The Shape that wraps +native+, one for each engine Shape while it
      # lives. :nodoc:
      def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        shape = allocate
        shape.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, shape)
        shape
      end

      # The Body the Shape is attached to, or +nil+, matching
      # Shape:getBody.
      #
      # === Example
      #
      #   shape.body.x # => 0.0
      def body
        native = @native.body
        native && Body.from_native(native)
      end

      # How many children the Shape has, as an Integer: one, but for a
      # ChainShape, one for each edge, matching Shape:getChildCount.
      #
      # === Example
      #
      #   shape.child_count # => 1
      def child_count
        @native.child_count
      end

      # The Shape's radius, as a Float, matching Shape:getRadius: a
      # circle's, or the skin a polygon keeps around itself.
      #
      # === Example
      #
      #   shape.radius # => 20.0
      def radius
        @native.radius
      end

      # Whether the Shape only senses what overlaps it, without colliding,
      # matching Shape:isSensor.
      #
      # === Example
      #
      #   shape.sensor? # => false
      def sensor?
        @native.sensor?
      end

      # Sets whether the Shape only senses, matching Shape:setSensor.
      #
      # === Example
      #
      #   shape.sensor = true
      def sensor=(sensor)
        @native.set_sensor(sensor)
      end

      # The density, as a Float, matching Shape:getDensity.
      #
      # === Example
      #
      #   shape.density # => 1.0
      def density
        @native.density
      end

      # Sets the density, matching Shape:setDensity; the Body's mass
      # follows at its next Body#reset_mass_data.
      #
      # === Example
      #
      #   shape.density = 5
      def density=(density)
        @native.set_density(density)
      end

      # The friction, as a Float, matching Shape:getFriction.
      #
      # === Example
      #
      #   shape.friction # => 0.2
      def friction
        @native.friction
      end

      # Sets the friction, matching Shape:setFriction.
      #
      # === Example
      #
      #   shape.friction = 1
      def friction=(friction)
        @native.set_friction(friction)
      end

      # The restitution, how much it bounces, as a Float, matching
      # Shape:getRestitution.
      #
      # === Example
      #
      #   shape.restitution # => 0.0
      def restitution
        @native.restitution
      end

      # Sets the restitution, matching Shape:setRestitution.
      #
      # === Example
      #
      #   shape.restitution = 0.5
      def restitution=(restitution)
        @native.set_restitution(restitution)
      end

      # The categories the Shape is in, from 1 to 16, as an Array of
      # Integers, matching Shape:getCategory.
      #
      # === Example
      #
      #   shape.category # => [1]
      def category
        @native.category
      end

      # Puts the Shape in the +categories+, from 1 to 16, matching
      # Shape:setCategory, whose several values rule 6 of ADR 001 makes one
      # Array, as it does LÖVE's table of them.
      #
      # Raises RuntimeError ("Values must be in range 1-16.") outside that
      # range.
      #
      # === Example
      #
      #   shape.category = 3, 5, 6
      def category=(categories)
        @native.set_category(categories.is_a?(Array) ? categories : [categories])
      end

      # The categories the Shape does not collide with, as an Array of
      # Integers, matching Shape:getMask.
      #
      # === Example
      #
      #   shape.mask # => []
      def mask
        @native.mask
      end

      # Sets the categories the Shape does not collide with, matching
      # Shape:setMask, as #category= reads them.
      #
      # === Example
      #
      #   shape.mask = 1, 2, 3
      def mask=(masks)
        @native.set_mask(masks.is_a?(Array) ? masks : [masks])
      end

      # The collision group, as an Integer, matching Shape:getGroupIndex:
      # Shapes in the same positive group always collide, and in the same
      # negative group never.
      #
      # === Example
      #
      #   shape.group_index # => 0
      def group_index
        @native.group_index
      end

      # Sets the collision group, matching Shape:setGroupIndex.
      #
      # === Example
      #
      #   shape.group_index = -1
      def group_index=(index)
        @native.set_group_index(index)
      end

      # The category bits, the mask bits, and the group, as an Array of
      # Integers, matching Shape:getFilterData.
      #
      # === Example
      #
      #   categories, mask, group = shape.filter_data
      def filter_data
        @native.filter_data
      end

      # Whether the point +x+, +y+ is inside the Shape, matching
      # Shape:testPoint: where its Body is, or, given an angle and a point,
      # with the Shape placed at +x+, +y+ turned by +angle+ and +px+, +py+
      # the point.
      #
      # === Examples
      #
      #   shape.test_point(5, 5)
      #   shape.test_point(10, 10, 0, 15, 15)
      def test_point(x, y, angle = nil, px = nil, py = nil)
        @native.test_point(x, y, angle, px, py)
      end

      # Where the ray from +x1+, +y1+ to +x2+, +y2+, as far as
      # +max_fraction+ of its length, hits the Shape, matching
      # Shape:rayCast: an Array of the normal's x and y and the fraction of
      # the ray at the hit, or an empty Array when it misses (ADR 001, rule
      # 4).
      #
      # [arguments] The child to cast against, counting from 1, or the
      #   Shape's own x, y, and angle to place it at, then the child.
      #
      # === Example
      #
      #   xn, yn, fraction = shape.ray_cast(-20, -20, 20, 20, 100)
      def ray_cast(x1, y1, x2, y2, max_fraction, *arguments)
        @native.ray_cast([x1, y1, x2, y2, max_fraction], arguments)
      end

      # The bounding box of the Shape placed at +x+, +y+ turned by
      # +angle+, as an Array of its top left's x and y and its bottom
      # right's, matching Shape:computeAABB.
      #
      # [child] Integer child, counting from 1.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = shape.compute_aabb(0, 0, 0)
      def compute_aabb(x, y, angle, child = 1)
        @native.compute_aabb(x, y, angle, child)
      end

      # The bounding box of the Shape where its Body is, as #compute_aabb
      # gives it, matching Shape:getBoundingBox.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = shape.bounding_box
      def bounding_box(child = 1)
        @native.bounding_box(child)
      end

      # The center of mass, the mass, and the inertia the Shape would have
      # at +density+, as an Array of four Floats, matching
      # Shape:computeMass.
      #
      # === Example
      #
      #   x, y, mass, inertia = shape.compute_mass(1000)
      def compute_mass(density)
        @native.compute_mass(density)
      end

      # The center of mass, the mass, and the inertia the Shape gives its
      # Body, as an Array of four Floats, matching Shape:getMassData.
      #
      # === Example
      #
      #   x, y, mass, inertia = shape.mass_data
      def mass_data
        @native.mass_data
      end

      # The value the game attached to the Shape, or +nil+, matching
      # Shape:getUserData.
      #
      # === Example
      #
      #   shape.user_data # => "player"
      def user_data
        @native.user_data
      end

      # Attaches any value to the Shape, matching Shape:setUserData.
      #
      # === Example
      #
      #   shape.user_data = "player"
      def user_data=(value)
        @native.set_user_data(value)
      end

      # Whether the Shape was destroyed, matching Shape:isDestroyed.
      #
      # === Example
      #
      #   shape.destroyed? # => false
      def destroyed?
        @native.destroyed?
      end

      # Takes the Shape off its Body, matching Shape:destroy.
      #
      # === Example
      #
      #   shape.destroy
      def destroy
        @native.destroy
      end
    end

    # A circle, matching LÖVE's CircleShape
    # (src/modules/physics/box2d/CircleShape.h).
    #
    # === Example
    #
    #   Lota::Physics::CircleShape.new(body, 20)
    class CircleShape < Shape
      # Attaches a circle to +body+, matching love.physics.newCircleShape
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newCircleShape):
      # <tt>CircleShape.new(body, radius)</tt> at the Body's origin, or
      # <tt>CircleShape.new(body, x, y, radius)</tt> centered at +x+, +y+.
      #
      # Raises RuntimeError ("Incorrect number of parameters") for any other
      # number of arguments after the Body.
      #
      # === Example
      #
      #   Lota::Physics::CircleShape.new(body, 0, 0, 20)
      def self.new(body, *arguments)
        native = case arguments.size
        when 1 then Native::Physics.new_circle_shape(body.native, 0, 0, arguments.fetch(0))
        when 3 then Native::Physics.new_circle_shape(body.native, arguments.fetch(0), arguments.fetch(1), arguments.fetch(2))
        else raise "Incorrect number of parameters"
        end
        from_native(native)
      end
    end

    # A convex polygon of up to eight vertices, matching LÖVE's
    # PolygonShape (src/modules/physics/box2d/PolygonShape.h).
    #
    # === Example
    #
    #   Lota::Physics::PolygonShape.new(body, 0, 0, 10, 0, 5, 10)
    class PolygonShape < Shape
      # Attaches a polygon to +body+, matching love.physics.newPolygonShape
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newPolygonShape).
      #
      # [coordinates] An x and a y Float or Integer for each vertex, or an
      #   Array of them, as LÖVE takes a table.
      #
      # Raises RuntimeError, with LÖVE's message, for an odd number of
      # coordinates and for a polygon Box2D cannot make.
      #
      # === Example
      #
      #   Lota::Physics::PolygonShape.new(body, [0, 0, 2, 3, 2, 1])
      def self.new(body, *coordinates)
        from_native(Native::Physics.new_polygon_shape(body.native, coordinates.flatten))
      end
    end

    # A line segment, matching LÖVE's EdgeShape
    # (src/modules/physics/box2d/EdgeShape.h).
    #
    # === Example
    #
    #   Lota::Physics::EdgeShape.new(body, 0, 0, 10, 10)
    class EdgeShape < Shape
      # Attaches the segment from +x1+, +y1+ to +x2+, +y2+ to +body+,
      # matching love.physics.newEdgeShape
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newEdgeShape).
      #
      # [neighbors] Nothing, or the previous vertex's x and y and the next
      #   one's, for smooth collisions along a run of edges.
      #
      # === Example
      #
      #   Lota::Physics::EdgeShape.new(body, 0, 0, 10, 10)
      def self.new(body, x1, y1, x2, y2, *neighbors)
        from_native(Native::Physics.new_edge_shape(body.native, [x1, y1, x2, y2, *neighbors]))
      end
    end

    # A run of edges, open or closed, matching LÖVE's ChainShape
    # (src/modules/physics/box2d/ChainShape.h).
    #
    # === Example
    #
    #   Lota::Physics::ChainShape.new(body, true, 0, 0, 1, 0, 1, 1, 0, 1)
    class ChainShape < Shape
      # Attaches a chain of edges to +body+, matching
      # love.physics.newChainShape (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newChainShape).
      #
      # [loop] Whether the last vertex joins the first.
      # [coordinates] An x and a y Float or Integer for each vertex, or an
      #   Array of them.
      #
      # Raises RuntimeError ("Number of vertex components must be a
      # multiple of two.") for none or an odd number.
      #
      # === Example
      #
      #   Lota::Physics::ChainShape.new(body, false, [0, 0, 10, 0, 10, 10])
      def self.new(body, loop, *coordinates)
        from_native(Native::Physics.new_chain_shape(body.native, loop, coordinates.flatten))
      end
    end

    # LÖVE's love.physics.newRectangleShape, which makes a PolygonShape:
    # LÖVE has no RectangleShape class, so rule 2 of ADR 001 makes
    # RectangleShape a module whose +new+ returns the PolygonShape. What
    # <tt>RectangleShape ===</tt> asks is not settled yet, so it asks
    # Ruby's own question, whether its argument includes this module,
    # which no Shape does.
    #
    # === Example
    #
    #   Lota::Physics::RectangleShape.new(body, 10, 20)
    module RectangleShape
      # Attaches a rectangle to +body+, matching
      # love.physics.newRectangleShape (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newRectangleShape), as a PolygonShape:
      # <tt>RectangleShape.new(body, width, height)</tt> centered at the
      # Body's origin, or <tt>RectangleShape.new(body, x, y, width, height,
      # angle = 0)</tt> centered at +x+, +y+ and turned by +angle+.
      #
      # Raises RuntimeError ("Incorrect number of parameters") for any other
      # number of arguments after the Body.
      #
      # === Example
      #
      #   Lota::Physics::RectangleShape.new(body, 5, 5, 10, 10)
      def self.new(body, *arguments)
        placement = case arguments.size
        when 2 then [0, 0, *arguments, 0]
        when 4 then [*arguments, 0]
        when 5 then arguments
        else raise "Incorrect number of parameters"
        end
        PolygonShape.from_native(Native::Physics.new_rectangle_shape(body.native, placement))
      end
    end
  end
end
