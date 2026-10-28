# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Physics
    # A constraint between two Bodies, matching LÖVE's Joint
    # (src/modules/physics/box2d/Joint.h).
    #
    # Each Joint is of one of its subclasses, made by that class's +new+.
    # Each method raises RuntimeError ("Attempt to use destroyed joint.")
    # once the Joint is destroyed, but #destroyed? and #destroy. LÖVE's
    # Joint:getType, whose name rule 16 gives Lota::Object#type, waits for
    # the maintainer.
    #
    # === Example
    #
    #   joint = Lota::Physics::DistanceJoint.new(a, b, 10, 10, 20, 20)
    #   joint.anchors # => [10.0, 10.0, 20.0, 20.0]
    class Joint
      include Object

      # The engine's Joint, for Lota's own modules. :nodoc:
      attr_reader :native

      # The Joint that wraps +native+, one for each engine Joint while it
      # lives. :nodoc:
      def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        joint = allocate
        joint.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, joint)
        joint
      end

      # The two Bodies the Joint joins, as an Array, matching
      # Joint:getBodies.
      #
      # === Example
      #
      #   a, b = joint.bodies
      def bodies
        @native.bodies.map { |body| Body.from_native(body) }
      end

      # Where the Joint holds each Body, in the World's coordinates, as an
      # Array of the first anchor's x and y and the second's, matching
      # Joint:getAnchors.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = joint.anchors
      def anchors
        @native.anchors
      end

      # The force on the second Body at its anchor for a step of +dt+
      # seconds, as an Array of its x and y, matching Joint:getReactionForce.
      #
      # === Example
      #
      #   fx, fy = joint.reaction_force(1 / 60.0)
      def reaction_force(dt)
        @native.reaction_force(dt)
      end

      # The torque on the second Body for a step of +dt+ seconds, as a
      # Float, matching Joint:getReactionTorque.
      #
      # === Example
      #
      #   joint.reaction_torque(1 / 60.0) # => 0.0
      def reaction_torque(dt)
        @native.reaction_torque(dt)
      end

      # Whether the two Bodies collide with each other, matching
      # Joint:getCollideConnected.
      #
      # === Example
      #
      #   joint.collide_connected # => true
      def collide_connected
        @native.collide_connected
      end

      # The value the game attached to the Joint, or +nil+, matching
      # Joint:getUserData.
      #
      # === Example
      #
      #   joint.user_data # => "hello"
      def user_data
        @native.user_data
      end

      # Attaches any value to the Joint, matching Joint:setUserData.
      #
      # === Example
      #
      #   joint.user_data = "hello"
      def user_data=(value)
        @native.set_user_data(value)
      end

      # Whether the Joint was destroyed, matching Joint:isDestroyed.
      #
      # === Example
      #
      #   joint.destroyed? # => false
      def destroyed?
        @native.destroyed?
      end

      # Destroys the Joint, matching Joint:destroy.
      #
      # === Example
      #
      #   joint.destroy
      def destroy
        @native.destroy
      end

      # LÖVE's luax_optboolean (src/common/runtime.cpp:270-275): +value+
      # when it is true or false, and +default+ for anything else.
      private_class_method def self.flag(value, default)
        case value
        when true then true
        when false then false
        else default
        end
      end
    end

    # Keeps two Bodies a distance apart, matching LÖVE's DistanceJoint.
    class DistanceJoint < Joint
      # Joins +body1+ at +x1+, +y1+ to +body2+ at +x2+, +y2+, matching
      # love.physics.newDistanceJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newDistanceJoint).
      #
      # === Example
      #
      #   Lota::Physics::DistanceJoint.new(a, b, 10, 10, 20, 20, true)
      def self.new(body1, body2, x1, y1, x2, y2, collide_connected = nil)
        from_native(Native::Physics.new_distance_joint(body1.native, body2.native, [x1, y1, x2, y2],
          flag(collide_connected, false)))
      end
    end

    # Drags a Body toward a target, matching LÖVE's MouseJoint.
    class MouseJoint < Joint
      # Holds +body+ at the world point +x+, +y+, matching
      # love.physics.newMouseJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newMouseJoint).
      #
      # === Example
      #
      #   Lota::Physics::MouseJoint.new(body, 10, 10)
      def self.new(body, x, y)
        from_native(Native::Physics.new_mouse_joint(body.native, x, y))
      end
    end

    # Lets two Bodies turn about a shared point, matching LÖVE's
    # RevoluteJoint.
    class RevoluteJoint < Joint
      # Joins +body1+ and +body2+ at a point, matching
      # love.physics.newRevoluteJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newRevoluteJoint), with LÖVE's forms chosen by
      # how many +arguments+ there are: <tt>x, y, collide_connected =
      # false</tt>, both anchors at one point, or <tt>x1, y1, x2, y2,
      # collide_connected = false, reference_angle</tt>.
      #
      # === Example
      #
      #   Lota::Physics::RevoluteJoint.new(a, b, 10, 10, true)
      def self.new(body1, body2, *arguments)
        anchors, collide, angle = Joint.anchored(arguments, 2)
        from_native(Native::Physics.new_revolute_joint(body1.native, body2.native, anchors, flag(collide, false),
          angle))
      end
    end

    # Slows two Bodies' movement against each other, matching LÖVE's
    # FrictionJoint.
    class FrictionJoint < Joint
      # Joins +body1+ and +body2+, matching love.physics.newFrictionJoint
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newFrictionJoint),
      # with RevoluteJoint.new's forms, but for a reference angle.
      #
      # === Example
      #
      #   Lota::Physics::FrictionJoint.new(a, b, 15, 15, true)
      def self.new(body1, body2, *arguments)
        anchors, collide = Joint.anchored(arguments, 2)
        from_native(Native::Physics.new_friction_joint(body1.native, body2.native, anchors, flag(collide, false)))
      end
    end

    # Holds two Bodies together, matching LÖVE's WeldJoint.
    class WeldJoint < Joint
      # Joins +body1+ and +body2+, matching love.physics.newWeldJoint
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newWeldJoint), with
      # RevoluteJoint.new's forms.
      #
      # === Example
      #
      #   Lota::Physics::WeldJoint.new(a, b, 10, 10, true)
      def self.new(body1, body2, *arguments)
        anchors, collide, angle = Joint.anchored(arguments, 2)
        from_native(Native::Physics.new_weld_joint(body1.native, body2.native, anchors, flag(collide, false), angle))
      end
    end

    # Lets two Bodies slide along an axis, matching LÖVE's PrismaticJoint.
    class PrismaticJoint < Joint
      # Joins +body1+ and +body2+ along an axis, matching
      # love.physics.newPrismaticJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newPrismaticJoint), with LÖVE's forms chosen by
      # how many +arguments+ there are: <tt>x, y, ax, ay, collide_connected
      # = false</tt>, both anchors at one point, or <tt>x1, y1, x2, y2, ax,
      # ay, collide_connected = false, reference_angle</tt>.
      #
      # === Example
      #
      #   Lota::Physics::PrismaticJoint.new(a, b, 10, 10, 20, 20, true)
      def self.new(body1, body2, *arguments)
        anchors, collide, angle = Joint.anchored(arguments, 4)
        from_native(Native::Physics.new_prismatic_joint(body1.native, body2.native, anchors, flag(collide, false),
          angle))
      end
    end

    # Lets a Body roll on another, as a wheel on a car, matching LÖVE's
    # WheelJoint.
    class WheelJoint < Joint
      # Joins +body1+ and +body2+ along an axis, matching
      # love.physics.newWheelJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newWheelJoint), with PrismaticJoint.new's
      # forms, but for a reference angle.
      #
      # === Example
      #
      #   Lota::Physics::WheelJoint.new(a, b, 10, 10, 5, 5, true)
      def self.new(body1, body2, *arguments)
        anchors, collide = Joint.anchored(arguments, 4)
        from_native(Native::Physics.new_wheel_joint(body1.native, body2.native, anchors, flag(collide, false)))
      end
    end

    # Hangs two Bodies from fixed points on a rope over a pulley, matching
    # LÖVE's PulleyJoint.
    class PulleyJoint < Joint
      # Joins +body1+ and +body2+ over a pulley, matching
      # love.physics.newPulleyJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newPulleyJoint): the two ground anchors, then
      # the two Bodies' anchors, then the ratio, 1 by default, and whether
      # the Bodies collide, as Box2D's pulley defaults to, true.
      #
      # === Example
      #
      #   Lota::Physics::PulleyJoint.new(a, b, 10, 10, 20, 20, 15, 15, 25, 25)
      def self.new(body1, body2, gx1, gy1, gx2, gy2, x1, y1, x2, y2, ratio = 1, collide_connected = nil)
        from_native(Native::Physics.new_pulley_joint(body1.native, body2.native,
          [gx1, gy1, gx2, gy2, x1, y1, x2, y2], ratio, flag(collide_connected, true)))
      end
    end

    # Links two Joints, so one drives the other, matching LÖVE's GearJoint.
    class GearJoint < Joint
      # Links +joint1+ and +joint2+, each a RevoluteJoint or a
      # PrismaticJoint, matching love.physics.newGearJoint
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newGearJoint).
      #
      # === Example
      #
      #   Lota::Physics::GearJoint.new(slider1, slider2, 1, true)
      def self.new(joint1, joint2, ratio = 1, collide_connected = nil)
        from_native(Native::Physics.new_gear_joint(joint1.native, joint2.native, ratio,
          flag(collide_connected, false)))
      end
    end

    # Keeps two Bodies at most a length apart, matching LÖVE's RopeJoint.
    class RopeJoint < Joint
      # Joins +body1+ at +x1+, +y1+ to +body2+ at +x2+, +y2+, matching
      # love.physics.newRopeJoint (src/modules/physics/box2d/
      # wrap_Physics.cpp, w_newRopeJoint).
      #
      # === Example
      #
      #   Lota::Physics::RopeJoint.new(a, b, 10, 10, 20, 20, 50, true)
      def self.new(body1, body2, x1, y1, x2, y2, max_length, collide_connected = nil)
        from_native(Native::Physics.new_rope_joint(body1.native, body2.native, [x1, y1, x2, y2], max_length,
          flag(collide_connected, false)))
      end
    end

    # Moves one Body relative to another, matching LÖVE's MotorJoint.
    class MotorJoint < Joint
      # Joins +body1+ and +body2+, matching love.physics.newMotorJoint
      # (src/modules/physics/box2d/wrap_Physics.cpp, w_newMotorJoint), with
      # Box2D's defaults unless a +correction_factor+ is given.
      #
      # === Example
      #
      #   Lota::Physics::MotorJoint.new(a, b, 1)
      def self.new(body1, body2, correction_factor = nil, collide_connected = nil)
        from_native(Native::Physics.new_motor_joint(body1.native, body2.native, correction_factor,
          flag(collide_connected, false)))
      end
    end

    class Joint
      # LÖVE's choice of a joint factory's form by lua_gettop: the anchors,
      # as +short+ numbers, or two more when given, whether the Bodies
      # collide, and a reference angle, which comes only after both
      # anchors. :nodoc:
      def self.anchored(arguments, short)
        long = short + 2
        count = (arguments.size >= long) ? long : short
        angle = (count == long) ? arguments[count + 1] : nil
        [arguments.first(count).map { |value| number(value) }, arguments[count], angle.nil? ? nil : number(angle)]
      end

      # A number a joint factory reads with luaL_checknumber. :nodoc:
      def self.number(value)
        case value
        when Float, Integer then value
        else raise TypeError, "wrong argument type #{value.class} (expected Float or Integer)"
        end
      end
    end
  end
end
