# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Physics
    # Two Shapes whose bounding boxes overlap, and whether and where they
    # touch, matching LÖVE's Contact (src/modules/physics/box2d/Contact.h).
    #
    # World#contacts and Body#contacts give them. A Contact lasts while
    # its Shapes overlap; each method raises RuntimeError ("Attempt to use
    # destroyed contact.") once they part.
    #
    # === Example
    #
    #   world.contacts.select(&:touching?)
    class Contact
      include Object

      # The engine's Contact, for Lota's own modules. :nodoc:
      attr_reader :native

      # The Contact that wraps +native+, one for each engine Contact while
      # it lives. :nodoc:
      def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        contact = allocate
        contact.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, contact)
        contact
      end

      # The two Shapes, as an Array, matching Contact:getShapes.
      #
      # === Example
      #
      #   a, b = contact.shapes
      def shapes
        @native.shapes.map { |shape| Physics.shape(shape) }
      end

      # The two Shapes' children that touch, counting from 1, as an Array of
      # Integers, matching Contact:getChildren.
      #
      # === Example
      #
      #   contact.children # => [1, 1]
      def children
        @native.children
      end

      # The direction from the first Shape to the second, as an Array of its
      # x and y, matching Contact:getNormal.
      #
      # === Example
      #
      #   nx, ny = contact.normal
      def normal
        @native.normal
      end

      # Where the Shapes touch, as an Array of each point's x and y, none,
      # one, or two of them, matching Contact:getPositions.
      #
      # === Example
      #
      #   x1, y1, x2, y2 = contact.positions
      def positions
        @native.positions
      end

      # Whether the Shapes touch, matching Contact:isTouching.
      #
      # === Example
      #
      #   contact.touching? # => true
      def touching?
        @native.touching?
      end

      # Whether the Contact takes part in the step, matching
      # Contact:isEnabled.
      #
      # === Example
      #
      #   contact.enabled? # => true
      def enabled?
        @native.enabled?
      end

      # Sets whether the Contact takes part in the step, matching
      # Contact:setEnabled.
      #
      # === Example
      #
      #   contact.enabled = false
      def enabled=(enabled)
        @native.set_enabled(enabled)
      end

      # The friction between the Shapes, as a Float, matching
      # Contact:getFriction.
      #
      # === Example
      #
      #   contact.friction # => 0.2
      def friction
        @native.friction
      end

      # Sets the friction between the Shapes, matching Contact:setFriction.
      #
      # === Example
      #
      #   contact.friction = 0.1
      def friction=(friction)
        @native.set_friction(friction)
      end

      # Puts back the friction the Shapes give, matching
      # Contact:resetFriction.
      #
      # === Example
      #
      #   contact.reset_friction
      def reset_friction
        @native.reset_friction
      end

      # The restitution between the Shapes, as a Float, matching
      # Contact:getRestitution.
      #
      # === Example
      #
      #   contact.restitution # => 0.0
      def restitution
        @native.restitution
      end

      # Sets the restitution between the Shapes, matching
      # Contact:setRestitution.
      #
      # === Example
      #
      #   contact.restitution = 1
      def restitution=(restitution)
        @native.set_restitution(restitution)
      end

      # Puts back the restitution the Shapes give, matching
      # Contact:resetRestitution.
      #
      # === Example
      #
      #   contact.reset_restitution
      def reset_restitution
        @native.reset_restitution
      end
    end
  end
end
