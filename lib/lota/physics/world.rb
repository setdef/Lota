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
    # Its contact callbacks tell the game when two Shapes begin and end
    # touching, and around each step's solving of their contact (#callbacks=),
    # and its contact filter decides which Shapes collide at all
    # (#contact_filter=). Each is anything that answers +call+, as LÖVE's
    # are Lua functions, and receives only as many arguments as it declares
    # (ADR 001, after the table; ADR 003, section 3).
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
      # The contact callbacks and the contact filter run during the step
      # (#callbacks=). While it runs, the World is #locked?, and a Body,
      # Shape, Joint, or the World destroyed is destroyed once the step
      # ends, as in LÖVE. An error a callback raises leaves the step where
      # it was raised and comes out of #update, as a Lua error comes out of
      # World:update, and the World stays #locked?, as LÖVE's does. One
      # raised from post_solve, which Box2D calls inside its solver, ends
      # the program instead, as it ends LÖVE's: on its way out of the
      # solver, Box2D's check of its own memory fails, and LÖVE makes that
      # check raise an error inside a destructor, which C++ cannot pass on.
      #
      # Raises RuntimeError for a destroyed World.
      #
      # === Example
      #
      #   world.update(dt)
      def update(dt, velocity_iterations = nil, position_iterations = nil)
        @native.update(dt, velocity_iterations, position_iterations)
      end

      # The World's four contact callbacks, as an Array of each callable
      # or +nil+: begin_contact, end_contact, pre_solve, and post_solve,
      # matching World:getCallbacks
      # (src/modules/physics/box2d/wrap_World.cpp, w_World_getCallbacks),
      # each exactly what #callbacks= set.
      #
      # === Example
      #
      #   begin_contact, end_contact, pre_solve, post_solve = world.callbacks
      def callbacks
        @native.callbacks
      end

      # Sets the World's four contact callbacks, matching
      # World:setCallbacks (src/modules/physics/box2d/wrap_World.cpp,
      # w_World_setCallbacks; World.cpp, World::ContactCallback), whose
      # four functions rule 6 of ADR 001 makes one Array.
      #
      # [callbacks] An Array of up to four, each anything that answers
      #   +call+, or +nil+ for none:
      #   begin_contact:: called when two Shapes begin to touch.
      #   end_contact:: called when they stop touching. The Contact is
      #     destroyed once it returns.
      #   pre_solve:: called before each step solves a touching Contact.
      #   post_solve:: called after each step solves it, with each contact
      #     point's normal and tangent impulse.
      #
      # Each receives the two Shapes, the Contact, and for post_solve the
      # impulses, as Floats: the first point's normal impulse, its tangent
      # impulse, then the second point's. It receives only as many of them
      # as it declares (ADR 003, section 3), so <tt>-> {}</tt> receives
      # none and <tt>proc { |a, b| }</tt> the two Shapes, and a required
      # parameter beyond them receives +nil+, as in Lua. Each replaces what
      # was set before, and the World holds it until another replaces it or
      # the World is destroyed.
      #
      # Raises TypeError, and changes nothing, for one that is neither
      # +nil+ nor answers +call+, as LÖVE raises for one that is not a
      # function.
      #
      # === Example
      #
      #   world.callbacks = ->(a, b, contact) { hits << contact }, nil, nil,
      #     ->(a, b, contact, normal_impulse) { thuds << normal_impulse }
      def callbacks=(callbacks)
        given = (callbacks.is_a?(Array) ? callbacks : [callbacks]).first(4)
        given.each { |callable| check_callable(callable) }
        @native.set_callbacks(Array.new(4) { |index| contact_function(given[index]) })
      end

      # The World's contact filter, or +nil+, matching World:getContactFilter
      # (src/modules/physics/box2d/wrap_World.cpp,
      # w_World_getContactFilter), exactly what #contact_filter= set.
      #
      # === Example
      #
      #   world.contact_filter # => nil
      def contact_filter
        @native.contact_filter
      end

      # Sets the World's contact filter, matching World:setContactFilter
      # (src/modules/physics/box2d/wrap_World.cpp,
      # w_World_setContactFilter; World.cpp, World::ShouldCollide).
      #
      # [filter] Anything that answers +call+, or +nil+ for none: called
      #   with two Shapes that LÖVE's group, category, and mask rules let
      #   collide, as many as it declares, and they collide only when it
      #   returns a true value.
      #
      # Raises TypeError, and changes nothing, for a +filter+ that is
      # neither +nil+ nor answers +call+.
      #
      # === Example
      #
      #   world.contact_filter = ->(a, b) { a.body != b.body }
      def contact_filter=(filter)
        check_callable(filter)
        @native.set_contact_filter(filter && contact_filter_function(filter))
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

      # Raises TypeError for a callback that is neither nil nor answers
      # call, where LÖVE's luaL_checktype raises for one that is not a
      # function.
      private def check_callable(callable)
        return if callable.nil? || callable.respond_to?(:call)

        raise TypeError, "wrong argument type #{callable.class} (expected an object that answers call)"
      end

      # The callable and the lambda the engine calls for it, or +nil+ for
      # none. The lambda wraps the engine's Shapes and Contact in Lota's
      # classes, and passes +callable+ as many of them, and of the
      # impulses, as it declares (ADR 003, section 3), which it reads once.
      private def contact_function(callable)
        return unless callable

        parameters = Callbacks.parameters(callable)
        call = lambda do |a, b, contact, *impulses|
          arguments = [Physics.shape(a), Physics.shape(b), Contact.from_native(contact), *impulses]
          callable.call(*Callbacks.declared(parameters, arguments))
        end
        [callable, call]
      end

      # The filter and the lambda the engine calls for it, as
      # #contact_function makes them, with the two Shapes.
      private def contact_filter_function(filter)
        parameters = Callbacks.parameters(filter)
        [filter, -> (a, b) { filter.call(*Callbacks.declared(parameters, [Physics.shape(a), Physics.shape(b)])) }]
      end

      # A ray's hit, with its Shape wrapped.
      private def hit(results)
        results.map { |value| value.is_a?(Native::Shape) ? Physics.shape(value) : value }
      end
    end
  end
end
