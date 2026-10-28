# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Physics
    # Everything that moves and collides together, matching LÖVE's World
    # (src/modules/physics/box2d/World.h).
    #
    # Bodies in different Worlds never meet. A World holds its Bodies and
    # their Joints, applies its gravity to them, and moves them all forward
    # by a step of time with #update, resolving each collision on the way.
    #
    # LÖVE's World:setCallbacks, getCallbacks, setContactFilter, and
    # getContactFilter wait for the maintainer to settle the shape of
    # Ruby's contact callbacks (Plan 001, design questions).
    #
    # === Example
    #
    #   world = Lota::Physics::World.new(0, 300)
    #   world.update(1 / 60.0)
    class World
      include Object

      # The engine's World, for Lota's own modules. :nodoc:
      attr_reader :native

      # The World that wraps +native+, one for each engine World while it
      # lives, as LÖVE pushes one Lua value for each. :nodoc:
      def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        world = allocate
        world.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, world)
        world
      end

      # Makes a World, matching love.physics.newWorld
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newWorld).
      #
      # [gx] Float or Integer gravity along x, in pixels a second a second.
      # [gy] Float or Integer gravity along y.
      # [sleep] Whether Bodies at rest may sleep, which saves their
      #   simulation until something wakes them.
      #
      # Raises RuntimeError when the physics module is not open.
      #
      # === Example
      #
      #   Lota::Physics::World.new(0, 9.81 * 30)
      def self.new(gx = 0, gy = 0, sleep = true)
        from_native(Native::Physics.new_world(gx, gy, sleep))
      end

      # Moves every Body forward by +dt+ seconds, matching World:update
      # (src/modules/physics/box2d/wrap_World.cpp, w_World_update).
      #
      # [dt] Float or Integer seconds.
      # [velocity_iterations] Integer passes of the velocity solver, 8 by
      #   default; given only with +position_iterations+.
      # [position_iterations] Integer passes of the position solver, 3 by
      #   default.
      #
      # Raises RuntimeError for a destroyed World.
      #
      # === Example
      #
      #   world.update(dt)
      def update(dt, velocity_iterations = nil, position_iterations = nil)
        @native.update(dt, velocity_iterations, position_iterations)
      end

      # The Bodies in the World, as an Array of Lota::Physics::Body,
      # matching World:getBodies.
      #
      # === Example
      #
      #   world.bodies.size # => 2
      def bodies
        @native.bodies.map { |body| Body.from_native(body) }
      end

      # How many Bodies are in the World, as an Integer, matching
      # World:getBodyCount.
      #
      # === Example
      #
      #   world.body_count # => 2
      def body_count
        @native.body_count
      end

      # The Joints in the World, as an Array of Lota::Physics::Joint,
      # matching World:getJoints.
      #
      # === Example
      #
      #   world.joints # => []
      def joints
        @native.joints.map { |joint| Physics.joint(joint) }
      end

      # How many Joints are in the World, as an Integer, matching
      # World:getJointCount.
      #
      # === Example
      #
      #   world.joint_count # => 0
      def joint_count
        @native.joint_count
      end

      # The Contacts between Shapes whose bounding boxes overlap, as an
      # Array of Lota::Physics::Contact, matching World:getContacts.
      #
      # === Example
      #
      #   world.contacts # => []
      def contacts
        @native.contacts.map { |contact| Contact.from_native(contact) }
      end

      # How many Contacts the World has, as an Integer, matching
      # World:getContactCount.
      #
      # === Example
      #
      #   world.contact_count # => 0
      def contact_count
        @native.contact_count
      end

      # The gravity, as an Array of its x and y Floats, matching
      # World:getGravity.
      #
      # === Example
      #
      #   gx, gy = world.gravity
      def gravity
        @native.gravity
      end

      # Sets the gravity, matching World:setGravity, whose two values rule
      # 6 of ADR 001 makes one Array.
      #
      # [gravity] An Array of the x and y Floats or Integers.
      #
      # === Example
      #
      #   world.gravity = 0, 300
      def gravity=(gravity)
        x, y = gravity
        @native.set_gravity(x, y)
      end

      # Moves the World's origin, and so every Body, by +x+, +y+ the other
      # way, matching World:translateOrigin.
      #
      # === Example
      #
      #   world.translate_origin(-10, -10)
      def translate_origin(x, y)
        @native.translate_origin(x, y)
      end

      # Whether Bodies at rest may sleep, matching World:isSleepingAllowed.
      #
      # === Example
      #
      #   world.sleeping_allowed? # => true
      def sleeping_allowed?
        @native.sleeping_allowed?
      end

      # Sets whether Bodies at rest may sleep, matching
      # World:setSleepingAllowed.
      #
      # === Example
      #
      #   world.sleeping_allowed = false
      def sleeping_allowed=(allowed)
        @native.set_sleeping_allowed(allowed)
      end

      # Whether the World is in the middle of #update, matching
      # World:isLocked.
      #
      # === Example
      #
      #   world.locked? # => false
      def locked?
        @native.locked?
      end

      # The Shapes whose bounding boxes overlap the area from +x1+, +y1+ to
      # +x2+, +y2+, as an Array, matching World:getShapesInArea.
      #
      # [mask] Integer bits of the categories to look for; every category
      #   by default.
      #
      # === Example
      #
      #   world.shapes_in_area(0, 0, 10, 10).size # => 1
      def shapes_in_area(x1, y1, x2, y2, mask = nil)
        @native.shapes_in_area(x1, y1, x2, y2, mask).map { |shape| Physics.shape(shape) }
      end

      # Calls the block with each Shape whose bounding box overlaps the area
      # from +x1+, +y1+ to +x2+, +y2+, matching World:queryShapesInArea,
      # whose function becomes the block (ADR 001, rule 12).
      #
      # [arguments] Anything, passed to the block after the Shape, as LÖVE
      #   passes the arguments after its function.
      #
      # The query goes on while the block returns a true value, and stops
      # at the first +nil+ or +false+, as Lua's truth decides it in LÖVE, so
      # a block that would go on must end with a true value.
      #
      # === Example
      #
      #   world.query_shapes_in_area(0, 0, 100, 100) { |shape| found << shape }
      def query_shapes_in_area(x1, y1, x2, y2, *arguments)
        call = proc { |shape, *rest| yield Physics.shape(shape), *rest } if block_given?
        @native.query_shapes_in_area(x1, y1, x2, y2, [call, *arguments])
      end

      # Calls the block with each Shape the ray from +x1+, +y1+ to +x2+,
      # +y2+ hits, matching World:rayCast, whose function becomes the block
      # (ADR 001, rule 12).
      #
      # [arguments] Anything, passed to the block after the hit, as LÖVE
      #   passes the arguments after its function.
      #
      # The block receives the Shape, the point it was hit at, the normal
      # there, and the fraction of the ray to the point, and returns a
      # number: -1 to leave the Shape out, 0 to stop, the fraction to clip
      # the ray to the hit, or 1 to go on. Raises RuntimeError ("Raycast
      # callback didn't return a number!") for a block that returns
      # anything else.
      #
      # === Example
      #
      #   world.ray_cast(0, 0, 200, 200) { |shape, x, y, xn, yn, fraction| 1 }
      def ray_cast(x1, y1, x2, y2, *arguments)
        call = proc { |shape, *rest| yield Physics.shape(shape), *rest } if block_given?
        @native.ray_cast(x1, y1, x2, y2, [call, *arguments])
      end

      # The first Shape the ray from +x1+, +y1+ to +x2+, +y2+ is found to
      # hit, matching World:rayCastAny: an Array of the Shape, the point,
      # the normal, and the fraction, or an empty Array when it hits none
      # (ADR 001, rule 4).
      #
      # [mask] Integer bits of the categories to look for; every category
      #   by default.
      #
      # === Example
      #
      #   shape, x, y = world.ray_cast_any(0, 0, 200, 200)
      def ray_cast_any(x1, y1, x2, y2, mask = nil)
        hit(@native.ray_cast_any(x1, y1, x2, y2, mask))
      end

      # The Shape nearest the ray's start that the ray from +x1+, +y1+ to
      # +x2+, +y2+ hits, matching World:rayCastClosest, as #ray_cast_any
      # returns it.
      #
      # === Example
      #
      #   world.ray_cast_closest(0, 0, 200, 200).first
      def ray_cast_closest(x1, y1, x2, y2, mask = nil)
        hit(@native.ray_cast_closest(x1, y1, x2, y2, mask))
      end

      # Whether the World was destroyed, matching World:isDestroyed.
      #
      # === Example
      #
      #   world.destroyed? # => false
      def destroyed?
        @native.destroyed?
      end

      # Destroys the World and every Body in it, matching World:destroy,
      # after the step when the World is updating.
      #
      # === Example
      #
      #   world.destroy
      def destroy
        @native.destroy
      end

      # A ray's hit, with its Shape wrapped.
      private def hit(results)
        results.map { |value| value.is_a?(Native::Shape) ? Physics.shape(value) : value }
      end
    end
  end
end
