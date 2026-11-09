# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Physics
    # Something with a position, an angle, and mass that moves in a World,
    # matching LÖVE's Body (src/modules/physics/box2d/Body.h).
    #
    # A Body has no shape of its own: Shapes attached to it give it one,
    # and its mass. A static Body never moves, a kinematic one moves only
    # at the velocity it is given, and a dynamic one moves by the forces on
    # it and collides.
    #
    # Each method raises RuntimeError ("Attempt to use destroyed body.")
    # once the Body is destroyed, but #destroyed? and #destroy. LÖVE's
    # Body:getType and setType are #get_type and #set_type, and a Body has
    # no +type+ (rules 34 and 41 of doc/contributors/design/translation.md).
    #
    # === Example
    #
    #   ball = Lota::Physics::Body.new(world, 400, 0, :dynamic)
    #   Lota::Physics::CircleShape.new(ball, 20)
    class Body < Object
      # The Body that wraps +native+, one for each engine Body while it
      # lives. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        body = allocate
        body.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, body)
        body
      end

      # Makes a Body in +world+ at +x+, +y+, matching love.physics.newBody
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newBody).
      #
      # [world] Lota::Physics::World.
      # [x] Float or Integer position along x, in pixels.
      # [y] Float or Integer position along y.
      # [type] Symbol <tt>:static</tt>, <tt>:dynamic</tt>, or
      #   <tt>:kinematic</tt> (rule 9 of
      #   doc/contributors/design/translation.md).
      #
      # Raises ArgumentError for a type LÖVE does not know, and
      # RuntimeError for a destroyed World.
      #
      # === Example
      #
      #   Lota::Physics::Body.new(world, 10, 10, :dynamic)
      def self.new(world, x = 0, y = 0, type = nil)
        from_native(Native::Physics.new_body(world.__send__(:native), x, y, type && EnumName.of(type)))
      end

      # The position along x, in pixels, as a Float, matching Body:getX.
      #
      # === Example
      #
      #   body.x # => 10.0
      def x
        @native.x
      end

      # The position along y, in pixels, as a Float, matching Body:getY.
      #
      # === Example
      #
      #   body.y # => 10.0
      def y
        @native.y
      end

      # Moves the Body along x, matching Body:setX.
      #
      # === Example
      #
      #   body.x = 0
      def x=(x)
        @native.set_x(x)
      end

      # Moves the Body along y, matching Body:setY.
      #
      # === Example
      #
      #   body.y = 0
      def y=(y)
        @native.set_y(y)
      end

      # The position, as an Array of its x and y Floats, matching
      # Body:getPosition.
      #
      # === Example
      #
      #   x, y = body.position
      def position
        @native.position
      end

      # Moves the Body, matching Body:setPosition, whose two values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   body.position = 5, 5
      def position=(position)
        x, y = position
        @native.set_position(x, y)
      end

      # The angle, in radians, as a Float, matching Body:getAngle.
      #
      # === Example
      #
      #   body.angle # => 0.0
      def angle
        @native.angle
      end

      # Turns the Body to +angle+ radians, matching Body:setAngle.
      #
      # === Example
      #
      #   body.angle = Math::PI / 2
      def angle=(angle)
        @native.set_angle(angle)
      end

      # The position and the angle, as an Array of the x, the y, and the
      # angle in radians, matching Body:getTransform.
      #
      # === Example
      #
      #   x, y, angle = body.transform
      def transform
        @native.transform
      end

      # Moves and turns the Body, matching Body:setTransform, whose three
      # values rule 6 of doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   body.transform = 5, 5, Math::PI / 2
      def transform=(transform)
        x, y, angle = transform
        @native.set_transform([x, y, angle])
      end

      # The position, the angle, the linear velocity, and the angular
      # velocity, as an Array of six Floats, matching Body:getKinematicState.
      #
      # === Example
      #
      #   x, y, angle, vx, vy, spin = body.kinematic_state
      def kinematic_state
        @native.kinematic_state
      end

      # Sets the position, the angle, the linear velocity, and the angular
      # velocity at once, matching Body:setKinematicState, whose six values
      # rule 6 of doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   body.kinematic_state = 0, 0, 0, 10, 0, 1
      def kinematic_state=(state)
        x, y, angle, dx, dy, da = state
        @native.set_kinematic_state(x, y, angle, dx, dy, da)
      end

      # Whether the Body is static, dynamic, or kinematic, as a Symbol,
      # matching Body:getType (rules 9 and 34 of
      # doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   body.get_type # => :dynamic
      def get_type
        @native.get_type.to_sym
      end

      # Sets whether the Body is static, dynamic, or kinematic, matching
      # Body:setType, with a Symbol (rules 9 and 34 of
      # doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   body.set_type(:dynamic)
      def set_type(type)
        @native.set_type(EnumName.of(type))
      end

      # Whether the Body takes part in the simulation, matching
      # Body:isActive.
      #
      # === Example
      #
      #   body.active? # => true
      def active?
        @native.active?
      end

      # Whether the Body is awake, matching Body:isAwake.
      #
      # === Example
      #
      #   body.awake? # => true
      def awake?
        @native.awake?
      end

      # Sets whether the Body takes part in the World, matching
      # Body:setActive, which calls the engine's Body::setEnabled. An
      # inactive Body neither moves nor collides.
      #
      # === Example
      #
      #   body.active = false
      def active=(active)
        @native.set_active(active)
      end

      # Wakes the Body, or puts it to sleep, matching Body:setAwake.
      #
      # === Example
      #
      #   body.awake = true
      def awake=(awake)
        @native.set_awake(awake)
      end

      # Whether the Body is a bullet, checked for collisions between steps,
      # matching Body:isBullet.
      #
      # === Example
      #
      #   body.bullet? # => false
      def bullet?
        @native.bullet?
      end

      # Sets whether the Body is a bullet, matching Body:setBullet.
      #
      # === Example
      #
      #   body.bullet = true
      def bullet=(bullet)
        @native.set_bullet(bullet)
      end

      # Whether the Body never turns, matching Body:isFixedRotation.
      #
      # === Example
      #
      #   body.fixed_rotation? # => false
      def fixed_rotation?
        @native.fixed_rotation?
      end

      # Sets whether the Body never turns, matching Body:setFixedRotation.
      #
      # === Example
      #
      #   body.fixed_rotation = true
      def fixed_rotation=(fixed)
        @native.set_fixed_rotation(fixed)
      end

      # Whether the Body may sleep, matching Body:isSleepingAllowed.
      #
      # === Example
      #
      #   body.sleeping_allowed? # => true
      def sleeping_allowed?
        @native.sleeping_allowed?
      end

      # Sets whether the Body may sleep, matching Body:setSleepingAllowed.
      #
      # === Example
      #
      #   body.sleeping_allowed = false
      def sleeping_allowed=(allowed)
        @native.set_sleeping_allowed(allowed)
      end

      # Whether one of the Body's Shapes touches one of +other+'s, matching
      # Body:isTouching.
      #
      # === Example
      #
      #   body.touching?(other) # => true
      def touching?(other)
        @native.touching?(other.native)
      end

      # The World the Body is in, matching Body:getWorld.
      #
      # === Example
      #
      #   body.world.body_count # => 2
      def world
        World.__send__(:from_native, @native.world)
      end

      # The Body's first Shape, or +nil+ when it has none, matching
      # Body:getShape.
      #
      # === Example
      #
      #   body.shape.radius # => 20.0
      def shape
        Physics.__send__(:shape, @native.shape)
      end

      # The Body's Shapes, as an Array, matching Body:getShapes.
      #
      # === Example
      #
      #   body.shapes.size # => 1
      def shapes
        @native.shapes.map { |shape| Physics.__send__(:shape, shape) }
      end

      # The Body's Shapes, as #shapes gives them, matching
      # Body:getFixtures, which LÖVE 12 deprecates for Body:getShapes and
      # whose first use prints LÖVE's notice, with Lota's names.
      #
      # === Example
      #
      #   body.fixtures.size # => 1
      def fixtures
        Deprecation.mark("Lota::Physics::Body#fixtures", :method, :replaced, "Lota::Physics::Body#shapes",
          where: Deprecation.where(caller_locations(1, 1)))
        shapes
      end

      # The Joints attached to the Body, as an Array, matching
      # Body:getJoints.
      #
      # === Example
      #
      #   body.joints.size # => 1
      def joints
        @native.joints.map { |joint| Physics.__send__(:joint, joint) }
      end

      # The Contacts of the Body's Shapes, as an Array, matching
      # Body:getContacts.
      #
      # === Example
      #
      #   body.contacts.size # => 1
      def contacts
        @native.contacts.map { |contact| Contact.__send__(:from_native, contact) }
      end

      # The center of mass in the Body's own coordinates, as an Array of
      # Floats, matching Body:getLocalCenter.
      #
      # === Example
      #
      #   x, y = body.local_center
      def local_center
        @native.local_center
      end

      # The center of mass in the World's coordinates, as an Array of
      # Floats, matching Body:getWorldCenter.
      #
      # === Example
      #
      #   x, y = body.world_center
      def world_center
        @native.world_center
      end

      # The point +x+, +y+ of the World in the Body's coordinates, as an
      # Array of Floats, matching Body:getLocalPoint.
      #
      # === Example
      #
      #   lx, ly = body.local_point(10, 10)
      def local_point(x, y)
        @native.local_point(x, y)
      end

      # The point +x+, +y+ of the Body in the World's coordinates, as an
      # Array of Floats, matching Body:getWorldPoint.
      #
      # === Example
      #
      #   wx, wy = body.world_point(10, 10)
      def world_point(x, y)
        @native.world_point(x, y)
      end

      # Points of the World in the Body's coordinates, as an Array of
      # Floats, matching Body:getLocalPoints.
      #
      # [coordinates] Floats or Integers, an x and a y for each point, at
      #   least two.
      #
      # Each pair comes back transformed; an odd number left over comes back
      # as it was, as LÖVE returns as many values as it was given.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = body.local_points(0, 5, 5, 10)
      def local_points(*coordinates)
        @native.local_points(coordinates)
      end

      # Points of the Body in the World's coordinates, as an Array of
      # Floats, matching Body:getWorldPoints, as #local_points reads them.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = body.world_points(0, 5, 5, 10)
      def world_points(*coordinates)
        @native.world_points(coordinates)
      end

      # The vector +x+, +y+ of the Body in the World's coordinates, as an
      # Array of Floats, matching Body:getWorldVector.
      #
      # === Example
      #
      #   vx, vy = body.world_vector(5, 10)
      def world_vector(x, y)
        @native.world_vector(x, y)
      end

      # The world vector +x+, +y+ in the Body's own frame, as an Array of
      # its x and y, matching Body:getLocalVector.
      #
      # === Example
      #
      #   vx, vy = body.local_vector(1, 0)
      def local_vector(x, y)
        @native.local_vector(x, y)
      end

      # The velocity of the Body's point at the world point +x+, +y+, as
      # an Array of its x and y, matching
      # Body:getLinearVelocityFromWorldPoint.
      #
      # === Example
      #
      #   vx, vy = body.linear_velocity_from_world_point(10, 0)
      def linear_velocity_from_world_point(x, y)
        @native.linear_velocity_from_world_point(x, y)
      end

      # The velocity of the Body's point at +x+, +y+ in its own frame, as an
      # Array of its x and y, matching Body:getLinearVelocityFromLocalPoint.
      #
      # === Example
      #
      #   vx, vy = body.linear_velocity_from_local_point(10, 0)
      def linear_velocity_from_local_point(x, y)
        @native.linear_velocity_from_local_point(x, y)
      end

      # The mass, as a Float, matching Body:getMass.
      #
      # === Example
      #
      #   body.mass # => 1.0
      def mass
        @native.mass
      end

      # Sets the mass, matching Body:setMass.
      #
      # === Example
      #
      #   body.mass = 10
      def mass=(mass)
        @native.set_mass(mass)
      end

      # The rotational inertia, as a Float, matching Body:getInertia.
      #
      # === Example
      #
      #   body.inertia # => 5.3
      def inertia
        @native.inertia
      end

      # Sets the rotational inertia, matching Body:setInertia, which keeps
      # the mass and the center of mass and marks the mass data as the
      # game's own.
      #
      # === Example
      #
      #   body.inertia = 50
      def inertia=(inertia)
        @native.set_inertia(inertia)
      end

      # The center of mass, the mass, and the inertia, as an Array of four
      # Floats, matching Body:getMassData.
      #
      # === Example
      #
      #   x, y, mass, inertia = body.mass_data
      def mass_data
        @native.mass_data
      end

      # Sets the center of mass, the mass, and the inertia, matching
      # Body:setMassData, whose four values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   body.mass_data = 3, 5, 10, 1
      def mass_data=(mass_data)
        x, y, mass, inertia = mass_data
        @native.set_mass_data(x, y, mass, inertia)
      end

      # Puts back the mass the Body's Shapes give it, matching
      # Body:resetMassData.
      #
      # === Example
      #
      #   body.reset_mass_data
      def reset_mass_data
        @native.reset_mass_data
      end

      # Whether the Body's mass was set rather than given by its Shapes,
      # matching Body:hasCustomMassData.
      #
      # === Example
      #
      #   body.custom_mass_data? # => false
      def custom_mass_data?
        @native.custom_mass_data?
      end

      # How much the Body's turning slows by itself, as a Float, matching
      # Body:getAngularDamping.
      #
      # === Example
      #
      #   body.angular_damping # => 0.0
      def angular_damping
        @native.angular_damping
      end

      # Sets how fast the Body's spin slows, matching
      # Body:setAngularDamping.
      #
      # === Example
      #
      #   body.angular_damping = 0.5
      def angular_damping=(damping)
        @native.set_angular_damping(damping)
      end

      # How fast the Body turns, in radians a second, as a Float, matching
      # Body:getAngularVelocity.
      #
      # === Example
      #
      #   body.angular_velocity # => 0.0
      def angular_velocity
        @native.angular_velocity
      end

      # Sets how fast the Body spins, in radians a second, matching
      # Body:setAngularVelocity.
      #
      # === Example
      #
      #   body.angular_velocity = Math::PI
      def angular_velocity=(velocity)
        @native.set_angular_velocity(velocity)
      end

      # How much gravity the Body feels, as a Float, matching
      # Body:getGravityScale.
      #
      # === Example
      #
      #   body.gravity_scale # => 1.0
      def gravity_scale
        @native.gravity_scale
      end

      # Sets how much gravity the Body feels, matching Body:setGravityScale.
      #
      # === Example
      #
      #   body.gravity_scale = 2
      def gravity_scale=(scale)
        @native.set_gravity_scale(scale)
      end

      # How much the Body's movement slows by itself, as a Float, matching
      # Body:getLinearDamping.
      #
      # === Example
      #
      #   body.linear_damping # => 0.0
      def linear_damping
        @native.linear_damping
      end

      # Sets how much the Body's movement slows by itself, matching
      # Body:setLinearDamping.
      #
      # === Example
      #
      #   body.linear_damping = 0.1
      def linear_damping=(damping)
        @native.set_linear_damping(damping)
      end

      # The velocity, in pixels a second, as an Array of its x and y Floats,
      # matching Body:getLinearVelocity.
      #
      # === Example
      #
      #   vx, vy = body.linear_velocity
      def linear_velocity
        @native.linear_velocity
      end

      # Sets the velocity, matching Body:setLinearVelocity, whose two values
      # rule 6 of doc/contributors/design/translation.md makes one Array.
      #
      # === Example
      #
      #   body.linear_velocity = 4, 5
      def linear_velocity=(velocity)
        x, y = velocity
        @native.set_linear_velocity(x, y)
      end

      # Pushes the Body with the force +fx+, +fy+, matching Body:applyForce:
      # at its center of mass, or at the point +x+, +y+ when given.
      #
      # [arguments] Nothing, or the Boolean whether to wake the Body, or
      #   the point's x and y and then that Boolean; it wakes the Body when
      #   left out.
      #
      # Raises RuntimeError ("Wrong number of parameters.") for one number
      # after the force.
      #
      # === Examples
      #
      #   body.apply_force(2, 3)
      #   body.apply_force(2, 3, 10, 10, false)
      def apply_force(fx, fy, *arguments)
        @native.apply_force(fx, fy, arguments)
      end

      # Kicks the Body with the impulse +jx+, +jy+, matching
      # Body:applyLinearImpulse, as #apply_force reads its +arguments+.
      #
      # === Example
      #
      #   body.apply_linear_impulse(-4, -59)
      def apply_linear_impulse(jx, jy, *arguments)
        @native.apply_linear_impulse(jx, jy, arguments)
      end

      # Spins the Body with the angular impulse +impulse+, matching
      # Body:applyAngularImpulse.
      #
      # === Example
      #
      #   body.apply_angular_impulse(10)
      def apply_angular_impulse(impulse)
        @native.apply_angular_impulse(impulse)
      end

      # Twists the Body with the torque +torque+, matching
      # Body:applyTorque.
      #
      # === Example
      #
      #   body.apply_torque(4)
      def apply_torque(torque)
        @native.apply_torque(torque)
      end

      # The value the game attached to the Body, or +nil+, matching
      # Body:getUserData.
      #
      # === Example
      #
      #   body.user_data[:love] # => "cool"
      def user_data
        @native.user_data
      end

      # Attaches any value to the Body, matching Body:setUserData. The
      # Body keeps it until it is destroyed.
      #
      # === Example
      #
      #   body.user_data = { love: "cool" }
      def user_data=(value)
        @native.set_user_data(value)
      end

      # Whether the Body was destroyed, matching Body:isDestroyed.
      #
      # === Example
      #
      #   body.destroyed? # => false
      def destroyed?
        @native.destroyed?
      end

      # Destroys the Body, its Shapes, and its Joints, matching
      # Body:destroy, after the step when its World is updating.
      #
      # === Example
      #
      #   body.destroy
      def destroy
        @native.destroy
      end
    end
  end
end
