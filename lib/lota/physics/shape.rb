# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Physics
    # The geometry of a Body, which gives it its mass and what it collides
    # with, matching LÖVE's Shape (src/modules/physics/box2d/Shape.h), which
    # in LÖVE 12 is also what LÖVE 11 called a Fixture.
    #
    # Each Shape is of one of its subclasses: CircleShape, PolygonShape
    # (which RectangleShape.new makes), EdgeShape, or ChainShape, which
    # #get_type names, as LÖVE's Shape:getType does; a Shape has no +type+
    # (rules 34 and 41 of doc/contributors/design/translation.md).
    #
    # === Example
    #
    #   shape = Lota::Physics::RectangleShape.new(body, 10, 10)
    #   shape.friction = 0.5
    class Shape < Object
      # The Shape that wraps +native+, one for each engine Shape while it
      # lives. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        shape = allocate
        shape.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, shape)
        shape
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Marks the deprecated form of the factory +name+ that takes no Body,
      # as luax_optbodyforshape marks it (src/modules/physics/box2d/
      # wrap_Physics.cpp:298-305) when the factory's first argument is
      # neither +nil+ nor one of LÖVE's objects, and prints its notice once,
      # naming the caller's line, which +locations+ gives. Each factory
      # reads a Body first otherwise, which must then be a Body. :nodoc:
      private_class_method def self.mark_without_body(name, locations)
        Deprecation.mark(name, :functionvariant, :replaced, "variant with Body parameter",
          where: Deprecation.where(locations))
      end

      # SPDX-SnippetEnd

      # The Body the Shape is attached to, or +nil+, matching
      # Shape:getBody.
      #
      # === Example
      #
      #   shape.body.x # => 0.0
      def body
        native = @native.body
        native && Body.__send__(:from_native, native)
      end

      # Which kind of Shape this is, as a Symbol, matching Shape:getType:
      # <tt>:circle</tt>, <tt>:polygon</tt>, <tt>:edge</tt>, or
      # <tt>:chain</tt> (rules 9 and 16 of
      # doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   Lota::Physics::RectangleShape.new(body, 10, 10).get_type # => :polygon
      def get_type
        @native.get_type.to_sym
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
      # Shape:setCategory, whose several values rule 6 of
      # doc/contributors/design/translation.md makes one Array, as it does
      # LÖVE's table of them.
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

      # Sets the category bits, the mask bits, and the group at once,
      # matching Shape:setFilterData, whose three Integers rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   shape.filter_data = 1, 65535, 0
      def filter_data=(filter_data)
        categories, mask, group = filter_data
        @native.set_filter_data(categories, mask, group)
      end

      # The Shape itself, matching Fixture:getShape, which LÖVE 12 keeps on
      # Shape now that a Shape is its own fixture, deprecated with no
      # replacement; its first use prints LÖVE's notice, with Lota's names.
      #
      # === Example
      #
      #   shape.shape.equal?(shape) # => true
      def shape
        Deprecation.mark("Lota::Physics::Shape#shape", :method, :noreplacement, nil,
          where: Deprecation.where(caller_locations(1, 1)))
        self
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
      # the ray at the hit, or an empty Array when it misses (rule 4 of
      # doc/contributors/design/translation.md).
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
      # LÖVE's deprecated forms without a Body,
      # <tt>CircleShape.new(radius)</tt> and <tt>CircleShape.new(x, y,
      # radius)</tt>, make a circle on no Body, for
      # Lota::Physics::Fixture.new to copy onto one; their first use prints
      # LÖVE's notice. Such a Shape answers its geometry, but raises
      # RuntimeError ("Shape must be active in the physics World to use
      # this method.") for what only a Shape on a Body has, as its density.
      #
      # Raises RuntimeError ("Incorrect number of parameters") for any other
      # number of arguments after the Body.
      #
      # === Example
      #
      #   Lota::Physics::CircleShape.new(body, 0, 0, 20)
      def self.new(first, *arguments)
        if first.nil? || first.is_a?(Object)
          body = first.__send__(:native)
          numbers = arguments
        else
          mark_without_body("Lota::Physics::CircleShape.new", caller_locations(1, 1))
          numbers = [first, *arguments]
        end
        native = case numbers.size
        when 1 then Native::Physics.new_circle_shape(body, 0, 0, numbers.fetch(0))
        when 3 then Native::Physics.new_circle_shape(body, numbers.fetch(0), numbers.fetch(1), numbers.fetch(2))
        else raise "Incorrect number of parameters"
        end
        from_native(native)
      end

      # Sets the circle's radius, matching CircleShape:setRadius.
      #
      # === Example
      #
      #   circle.radius = 30
      def radius=(radius)
        @native.set_radius(radius)
      end

      # The circle's center in its Body's frame, as an Array of its x and
      # y, matching CircleShape:getPoint.
      #
      # === Example
      #
      #   x, y = circle.point
      def point
        @native.point
      end

      # Moves the circle's center in its Body's frame, matching
      # CircleShape:setPoint, whose two values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   circle.point = 5, 0
      def point=(point)
        x, y = point
        @native.set_point(x, y)
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
      # Given no Body, with the coordinates first, it makes a polygon on no
      # Body, LÖVE's deprecated form, as CircleShape.new does.
      #
      # Raises RuntimeError, with LÖVE's message, for an odd number of
      # coordinates and for a polygon Box2D cannot make.
      #
      # === Example
      #
      #   Lota::Physics::PolygonShape.new(body, [0, 0, 2, 3, 2, 1])
      def self.new(first, *coordinates)
        if first.nil? || first.is_a?(Object)
          body = first.__send__(:native)
          numbers = coordinates
        else
          mark_without_body("Lota::Physics::PolygonShape.new", caller_locations(1, 1))
          numbers = [first, *coordinates]
        end
        from_native(Native::Physics.new_polygon_shape(body, numbers.flatten))
      end

      # Each vertex's x and y, in its Body's frame, as one Array, matching
      # PolygonShape:getPoints.
      #
      # === Example
      #
      #   x1, y1, x2, y2, x3, y3 = triangle.points
      def points
        @native.points
      end

      # Whether the polygon is convex, as Box2D needs it to be, matching
      # PolygonShape:validate.
      #
      # === Example
      #
      #   triangle.validate # => true
      def validate
        @native.validate
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
      # [arguments] +x1+, +y1+, +x2+, and +y2+, then nothing, or the
      #   previous vertex's x and y and the next one's, for smooth
      #   collisions along a run of edges.
      #
      # Given no Body, with +x1+ first, it makes a segment on no Body,
      # LÖVE's deprecated form, as CircleShape.new does.
      #
      # === Example
      #
      #   Lota::Physics::EdgeShape.new(body, 0, 0, 10, 10)
      def self.new(first, *arguments)
        if first.nil? || first.is_a?(Object)
          body = first.__send__(:native)
          numbers = arguments
        else
          mark_without_body("Lota::Physics::EdgeShape.new", caller_locations(1, 1))
          numbers = [first, *arguments]
        end
        raise ArgumentError, "wrong number of arguments (given #{numbers.size}, expected 4+)" if numbers.size < 4

        from_native(Native::Physics.new_edge_shape(body, numbers))
      end

      # The edge's two points in its Body's frame, as an Array of the first
      # one's x and y and the second's, matching EdgeShape:getPoints.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = edge.points
      def points
        @native.points
      end

      # The vertex after the edge, which smooths collisions along a run of
      # edges, as an Array of its x and y, matching EdgeShape:getNextVertex.
      #
      # === Example
      #
      #   x, y = edge.next_vertex
      def next_vertex
        @native.next_vertex
      end

      # Sets the vertex after the edge, matching EdgeShape:setNextVertex,
      # whose two values rule 6 of doc/contributors/design/translation.md makes
      # one Array.
      #
      # === Example
      #
      #   edge.next_vertex = 20, 10
      def next_vertex=(vertex)
        x, y = vertex
        @native.set_next_vertex(x, y)
      end

      # The vertex before the edge, as an Array of its x and y, matching
      # EdgeShape:getPreviousVertex.
      #
      # === Example
      #
      #   x, y = edge.previous_vertex
      def previous_vertex
        @native.previous_vertex
      end

      # Sets the vertex before the edge, matching
      # EdgeShape:setPreviousVertex, whose two values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   edge.previous_vertex = -10, 0
      def previous_vertex=(vertex)
        x, y = vertex
        @native.set_previous_vertex(x, y)
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
      # Given no Body, with +loop+ first, it makes a chain on no Body,
      # LÖVE's deprecated form, as CircleShape.new does.
      #
      # Raises RuntimeError ("Number of vertex components must be a
      # multiple of two.") for none or an odd number.
      #
      # === Example
      #
      #   Lota::Physics::ChainShape.new(body, false, [0, 0, 10, 0, 10, 10])
      def self.new(first, *arguments)
        if first.nil? || first.is_a?(Object)
          body = first.__send__(:native)
          loop = arguments.first #: bool
          coordinates = arguments.drop(1)
        else
          mark_without_body("Lota::Physics::ChainShape.new", caller_locations(1, 1))
          loop = first
          coordinates = arguments
        end
        from_native(Native::Physics.new_chain_shape(body, loop, coordinates.flatten))
      end

      # Each vertex's x and y, in its Body's frame, as one Array, matching
      # ChainShape:getPoints.
      #
      # === Example
      #
      #   chain.points # => [0.0, 0.0, 10.0, 0.0, 10.0, 10.0]
      def points
        @native.points
      end

      # How many vertices the chain has, as an Integer, matching
      # ChainShape:getVertexCount.
      #
      # === Example
      #
      #   chain.vertex_count # => 3
      def vertex_count
        @native.vertex_count
      end

      # Vertex +index+, counting from 1, as an Array of its x and y,
      # matching ChainShape:getPoint. Raises RuntimeError ("Physics error:
      # index out of bounds") for an index the chain does not have.
      #
      # === Example
      #
      #   x, y = chain.point(1)
      def point(index)
        @native.point(index)
      end

      # Edge +index+ of the chain, counting from 1, as a new EdgeShape on no
      # Body, matching ChainShape:getChildEdge, which LÖVE 12 deprecates with
      # no replacement; its first use prints LÖVE's notice, with Lota's
      # names.
      #
      # === Example
      #
      #   chain.child_edge(1).points # => [0.0, 0.0, 10.0, 0.0]
      def child_edge(index)
        Deprecation.mark("Lota::Physics::ChainShape#child_edge", :method, :noreplacement, nil,
          where: Deprecation.where(caller_locations(1, 1)))
        EdgeShape.__send__(:from_native, @native.child_edge(index))
      end

      # The vertex after the chain's last, as an Array of its x and y,
      # matching ChainShape:getNextVertex.
      #
      # === Example
      #
      #   x, y = chain.next_vertex
      def next_vertex
        @native.next_vertex
      end

      # Sets the vertex after the chain's last, matching
      # ChainShape:setNextVertex, whose two values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   chain.next_vertex = 20, 10
      def next_vertex=(vertex)
        x, y = vertex
        @native.set_next_vertex(x, y)
      end

      # The vertex before the chain's first, as an Array of its x and y,
      # matching ChainShape:getPreviousVertex.
      #
      # === Example
      #
      #   x, y = chain.previous_vertex
      def previous_vertex
        @native.previous_vertex
      end

      # Sets the vertex before the chain's first, matching
      # ChainShape:setPreviousVertex, whose two values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   chain.previous_vertex = -10, 0
      def previous_vertex=(vertex)
        x, y = vertex
        @native.set_previous_vertex(x, y)
      end
    end

    # LÖVE's love.physics.newRectangleShape, which makes a PolygonShape:
    # LÖVE has no RectangleShape class, so rule 2 of
    # doc/contributors/design/translation.md makes RectangleShape a module whose
    # +new+ returns the PolygonShape, and whose <tt>===</tt> is true of every
    # PolygonShape, as Image === is of every Texture.
    #
    # === Example
    #
    #   Lota::Physics::RectangleShape.new(body, 10, 20)
    module RectangleShape
      # Whether +object+ is a Lota::Physics::PolygonShape: newRectangleShape
      # makes one, and a PolygonShape records nothing of which factory made
      # it. Anything else is not a rectangle.
      #
      # === Example
      #
      #   Lota::Physics::RectangleShape === Lota::Physics::RectangleShape.new(body, 1, 1) # => true
      #   Lota::Physics::RectangleShape === Lota::Physics::CircleShape.new(body, 1)       # => false
      def self.===(object)
        case object
        when PolygonShape then true
        else false
        end
      end

      # Attaches a rectangle to +body+, matching
      # love.physics.newRectangleShape (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newRectangleShape), as a PolygonShape:
      # <tt>RectangleShape.new(body, width, height)</tt> centered at the
      # Body's origin, or <tt>RectangleShape.new(body, x, y, width, height,
      # angle = 0)</tt> centered at +x+, +y+ and turned by +angle+.
      #
      # Given no Body, with the numbers first, it makes a rectangle on no
      # Body, LÖVE's deprecated form, as CircleShape.new does.
      #
      # Raises RuntimeError ("Incorrect number of parameters") for any other
      # number of arguments after the Body.
      #
      # === Example
      #
      #   Lota::Physics::RectangleShape.new(body, 5, 5, 10, 10)
      def self.new(first, *arguments)
        if first.nil? || first.is_a?(Object)
          body = first.__send__(:native)
          numbers = arguments
        else
          Shape.__send__(:mark_without_body, "Lota::Physics::RectangleShape.new", caller_locations(1, 1))
          numbers = [first, *arguments]
        end
        placement = case numbers.size
        when 2 then [0, 0, *numbers, 0]
        when 4 then [*numbers, 0]
        when 5 then numbers
        else raise "Incorrect number of parameters"
        end
        PolygonShape.__send__(:from_native, Native::Physics.new_rectangle_shape(body, placement))
      end
    end

    # LÖVE's deprecated love.physics.newFixture, from LÖVE 11, where a
    # Fixture attached a Shape to a Body. In LÖVE 12 a Shape is its own
    # fixture and LÖVE has no Fixture class, so rules 25 and 27 of
    # doc/contributors/design/translation.md makes Fixture a module whose +new+
    # returns the new Shape, and whose <tt>===</tt> is true of every Shape, as
    # RectangleShape === is of every PolygonShape.
    #
    # === Example
    #
    #   prototype = Lota::Physics::CircleShape.new(20)
    #   shape = Lota::Physics::Fixture.new(body, prototype)
    module Fixture
      # Whether +object+ is a Lota::Physics::Shape: newFixture makes one,
      # and a Shape records nothing of which factory made it.
      #
      # === Example
      #
      #   Lota::Physics::Fixture === Lota::Physics::CircleShape.new(body, 1) # => true
      #   Lota::Physics::Fixture === body                                     # => false
      def self.===(object)
        case object
        when Shape then true
        else false
        end
      end

      # Attaches a copy of +shape+, a Shape on no Body, to +body+ at
      # +density+, and returns the copy, of the Shape's own class,
      # matching love.physics.newFixture
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newFixture), which
      # LÖVE 12 deprecates; its first use prints LÖVE's notice, with Lota's
      # names. The Shapes CircleShape.new and its kin make given no Body
      # are such Shapes.
      #
      # [density] Float or Integer density of the copy, which sets the
      #   Body's mass.
      #
      # Raises RuntimeError ("The given Shape must not be part of the
      # World.") for a Shape on a Body, as LÖVE does
      # (src/modules/physics/box2d/Physics.cpp, newAttachedShape), and
      # ("Cannot call this method on a destroyed Shape.") for a destroyed
      # one, which has nothing left to copy and which LÖVE reads through a
      # null pointer.
      #
      # === Example
      #
      #   Lota::Physics::Fixture.new(body, Lota::Physics::CircleShape.new(20), 2)
      def self.new(body, shape, density = 1)
        Deprecation.mark("Lota::Physics::Fixture.new", :function, :replaced,
          "Lota::Physics::Circle/Rectangle/Polygon/Edge/ChainShape.new", where: Deprecation.where(caller_locations(1, 1)))
        native = Native::Physics.new_fixture(body.__send__(:native), shape.__send__(:native), density)
        Physics.__send__(:shape, native)
      end
    end
  end
end
