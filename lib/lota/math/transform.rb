# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Math
    # A position, rotation, scale, and shear in one object, matching
    # LÖVE's Transform class (src/modules/math/Transform.h).
    #
    # A Transform holds a 4 by 4 matrix. Lota::Graphics.apply_transform
    # and Lota::Graphics.replace_transform draw through it, and
    # #transform_point moves a point through it, so a game can keep a
    # camera or a sprite's placement in one object and turn screen
    # coordinates back into world coordinates with
    # #inverse_transform_point.
    #
    # #translate, #rotate, #scale, #shear, #reset, #apply, and #inverse_of
    # change the Transform and return it, so they chain as they do in LÖVE.
    #
    # === Example
    #
    #   camera = Lota::Math::Transform.new
    #   camera.translate(400, 300).rotate(0.5).scale(2)
    #   Lota::Graphics.push { Lota::Graphics.apply_transform(camera) }
    class Transform
      include Object

      # The engine's Transform, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Transform the engine made. :nodoc:
      def self.from_native(native)
        transform = allocate
        transform.instance_variable_set(:@native, native)
        transform
      end

      # Makes a Transform, matching love.math.newTransform
      # (src/modules/math/wrap_Math.cpp, w_newTransform).
      #
      # With no arguments it changes nothing. Otherwise it places what it
      # transforms as Lota::Graphics.draw does:
      #
      # [x] Float or Integer position to the right.
      # [y] Float or Integer position down; required with +x+.
      # [angle] Float or Integer rotation in radians, 0 when +nil+.
      # [sx] Float or Integer horizontal scale, 1 when +nil+.
      # [sy] Float or Integer vertical scale, +sx+ when +nil+.
      # [ox] Float or Integer horizontal origin offset, 0 when +nil+.
      # [oy] Float or Integer vertical origin offset, 0 when +nil+.
      # [kx] Float or Integer horizontal shearing factor, 0 when +nil+.
      # [ky] Float or Integer vertical shearing factor, 0 when +nil+.
      #
      # LÖVE ignores the rest when +x+ is +nil+, and so does Lota. Raises
      # ArgumentError when +x+ is given without +y+, TypeError for an
      # argument that is not a number, and RuntimeError when the math
      # module is not open.
      #
      # === Examples
      #
      #   Lota::Math::Transform.new
      #   Lota::Math::Transform.new(100, 50, Math::PI / 2)
      def self.new(x = nil, y = nil, angle = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil, ky = nil)
        from_native(Native::Math.new_transform(x, y, angle || 0, sx || 1, sy, ox || 0, oy || 0, kx || 0, ky || 0))
      end

      # Makes this Transform, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching Transform:clone
      # (src/modules/math/wrap_Transform.cpp, w_Transform_clone): a new
      # Transform with +source+'s matrix, which it then keeps apart from
      # +source+'s (ADR 001, section 7).
      #
      # === Example
      #
      #   moved = transform.clone.translate(10, 0)
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # A new Transform that undoes this one, matching Transform:inverse
      # (src/modules/math/wrap_Transform.cpp, w_Transform_inverse).
      #
      # === Example
      #
      #   world = Lota::Math::Transform.new.translate(100, 0)
      #   world.inverse.transform_point(100, 0) # => [0.0, 0.0]
      def inverse
        Transform.from_native(@native.inverse)
      end

      # Sets this Transform to the inverse of +source+ and returns it,
      # matching Transform:inverseOf (src/modules/math/wrap_Transform.cpp,
      # w_Transform_inverseOf).
      #
      # [source] Lota::Math::Transform to invert; it is left as it was.
      #
      # Raises TypeError for anything but a Transform.
      #
      # === Example
      #
      #   undo = Lota::Math::Transform.new.inverse_of(camera)
      def inverse_of(source)
        @native.inverse_of(Transform.native_of(source))
        self
      end

      # Multiplies this Transform by +other+, so that it does +other+ first
      # and then what it did before, and returns it, matching
      # Transform:apply (src/modules/math/wrap_Transform.cpp,
      # w_Transform_apply).
      #
      # [other] Lota::Math::Transform to apply; it is left as it was.
      #
      # Raises TypeError for anything but a Transform.
      #
      # === Example
      #
      #   sprite.apply(camera)
      def apply(other)
        @native.apply(Transform.native_of(other))
        self
      end

      # Whether it keeps a flat drawing flat: its matrix moves, rotates,
      # scales, and shears in two dimensions alone, matching
      # Transform:isAffine2DTransform (src/modules/math/wrap_Transform.cpp,
      # w_Transform_isAffine2DTransform). One a game builds with
      # #translate, #rotate, #scale, and #shear always is; one set with
      # #matrix= may not be.
      #
      # === Example
      #
      #   Lota::Math::Transform.new.translate(4, 3).affine2d_transform? # => true
      def affine2d_transform?
        @native.affine2d_transform?
      end

      # A new Transform that does +other+ first and then this one, matching
      # Transform's __mul (src/modules/math/wrap_Transform.cpp,
      # w_Transform__mul), which Ruby names by its operator (ADR 001, rule
      # 13). Neither Transform changes.
      #
      # [other] Lota::Math::Transform.
      #
      # Raises TypeError for anything but a Transform.
      #
      # === Example
      #
      #   world = camera * sprite
      def *(other)
        Transform.from_native(@native * Transform.native_of(other))
      end

      # Moves what it transforms by +x+ and +y+ and returns itself,
      # matching Transform:translate (src/modules/math/wrap_Transform.cpp,
      # w_Transform_translate).
      #
      # [x] Float or Integer distance to the right.
      # [y] Float or Integer distance down.
      #
      # === Example
      #
      #   transform.translate(100, 50)
      def translate(x, y)
        @native.translate(x, y)
        self
      end

      # Rotates what it transforms by +angle+ and returns itself, matching
      # Transform:rotate (src/modules/math/wrap_Transform.cpp,
      # w_Transform_rotate).
      #
      # [angle] Float or Integer rotation in radians, clockwise on screen.
      #
      # === Example
      #
      #   transform.rotate(Math::PI / 4)
      def rotate(angle)
        @native.rotate(angle)
        self
      end

      # Scales what it transforms and returns itself, matching
      # Transform:scale (src/modules/math/wrap_Transform.cpp,
      # w_Transform_scale).
      #
      # [sx] Float or Integer horizontal factor.
      # [sy] Float or Integer vertical factor; +sx+ when +nil+ or left out.
      #
      # === Example
      #
      #   transform.scale(2)
      def scale(sx, sy = nil)
        @native.scale(sx, sy)
        self
      end

      # Shears what it transforms and returns itself, matching
      # Transform:shear (src/modules/math/wrap_Transform.cpp,
      # w_Transform_shear).
      #
      # [kx] Float or Integer horizontal shearing factor.
      # [ky] Float or Integer vertical shearing factor.
      #
      # === Example
      #
      #   transform.shear(0.5, 0)
      def shear(kx, ky)
        @native.shear(kx, ky)
        self
      end

      # Makes it change nothing again and returns itself, matching
      # Transform:reset (src/modules/math/wrap_Transform.cpp,
      # w_Transform_reset).
      #
      # === Example
      #
      #   transform.reset.transform_point(3, 4) # => [3.0, 4.0]
      def reset
        @native.reset
        self
      end

      # Replaces what it does with a placement, matching
      # Transform:setTransformation (src/modules/math/wrap_Transform.cpp,
      # w_Transform_setTransformation). LÖVE returns the Transform itself,
      # so it is a writer (ADR 001, section 7).
      #
      # [placement] Up to nine numbers, as one value or an Array, in the
      #   order Transform.new takes them, each taking its default when
      #   +nil+ or left out: the position 0, the angle 0, the scale 1, the
      #   vertical scale the horizontal one, and the origin offsets and
      #   shearing factors 0.
      #
      # Raises TypeError for a value that is not a number.
      #
      # === Example
      #
      #   transform.transformation = 4, 4, Math::PI / 2, 2
      def transformation=(placement)
        x, y, angle, sx, sy, ox, oy, kx, ky = placement.is_a?(Array) ? placement : [placement]
        @native.set_transformation(x || 0, y || 0, angle || 0, sx || 1, sy, ox || 0, oy || 0, kx || 0, ky || 0)
      end

      # Its matrix's sixteen elements, row by row, as an Array of Floats,
      # matching Transform:getMatrix (src/modules/math/wrap_Transform.cpp,
      # w_Transform_getMatrix).
      #
      # === Example
      #
      #   Lota::Math::Transform.new.translate(4, 0).matrix[3] # => 4.0
      def matrix
        @native.matrix
      end

      # Replaces its matrix, matching Transform:setMatrix
      # (src/modules/math/wrap_Transform.cpp, w_Transform_setMatrix). LÖVE
      # returns the Transform itself, so it is a writer (ADR 001, section
      # 7).
      #
      # [matrix] The layout first, optionally: +:row+ (the default) when
      #   the elements go row by row, or +:column+ when they go column by
      #   column (ADR 001, rule 9). Then the sixteen elements, each a Float
      #   or an Integer, given in turn, as one Array, or as four Arrays of
      #   four, one for each row or column.
      #
      # Raises ArgumentError for an unknown layout or a count of elements
      # other than sixteen, and TypeError for an element that is not a
      # number.
      #
      # === Examples
      #
      #   transform.matrix = 1, 0, 0, 4, 0, 1, 0, 4, 0, 0, 1, 0, 0, 0, 0, 1
      #   transform.matrix = :column, [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [4, 4, 0, 1]]
      def matrix=(matrix)
        layout, elements = Transform.layout_and_elements(matrix)
        @native.set_matrix(layout, elements)
      end

      # Moves a point through it, matching Transform:transformPoint
      # (src/modules/math/wrap_Transform.cpp, w_Transform_transformPoint).
      #
      # [x] Float or Integer.
      # [y] Float or Integer.
      #
      # Returns the moved point's x and y, as an Array of Floats (ADR 001,
      # rule 4).
      #
      # === Example
      #
      #   x, y = Lota::Math::Transform.new(10, 20).transform_point(1, 1) # => [11.0, 21.0]
      def transform_point(x, y)
        @native.transform_point(x, y)
      end

      # Moves a point back through it, as its inverse would, matching
      # Transform:inverseTransformPoint
      # (src/modules/math/wrap_Transform.cpp,
      # w_Transform_inverseTransformPoint).
      #
      # [x] Float or Integer.
      # [y] Float or Integer.
      #
      # Returns the point's x and y before the Transform, as an Array of
      # Floats (ADR 001, rule 4).
      #
      # === Example
      #
      #   x, y = Lota::Math::Transform.new(10, 20).inverse_transform_point(11, 21) # => [1.0, 1.0]
      def inverse_transform_point(x, y)
        @native.inverse_transform_point(x, y)
      end

      # The engine's Transform of +transform+, which must be a Transform,
      # as luax_checktransform checks. :nodoc:
      def self.native_of(transform)
        raise TypeError, "wrong argument type #{transform.class} (expected Lota::Math::Transform)" unless transform.is_a?(Transform)

        transform.native
      end

      # The matrix layout's name, or nil for the default, and the sixteen
      # elements of +matrix+, as Transform#matrix= and
      # Lota::Graphics.projection= take them: the layout first, if given,
      # then the elements in turn, in one Array, or in four Arrays of
      # four. A table of tables in LÖVE holds the same elements in the
      # same order (luax_checkmatrix, wrap_Transform.cpp:33-124). :nodoc:
      def self.layout_and_elements(matrix)
        values = matrix.is_a?(Array) ? matrix : [matrix]
        layout = values.first if values.first.is_a?(Symbol) || values.first.is_a?(String)
        elements = values.drop(layout.nil? ? 0 : 1).flatten
        unless elements.size == 16
          raise ArgumentError, "wrong number of matrix elements (given #{elements.size}, expected 16)"
        end

        [layout && EnumName.of(layout), elements]
      end
    end
  end
end
