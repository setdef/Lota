# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Math
    # A smooth curve shaped by control points, matching LÖVE's BezierCurve
    # class (src/modules/math/BezierCurve.h).
    #
    # A path a ship flies along, a rope that sags, or the edge of a hill
    # is a curve, but a game draws and moves things in straight steps. A
    # Bézier curve starts at its first control point, ends at its last,
    # and bends toward the ones between. #evaluate gives the point a
    # fraction of the way along it, and #render the points to draw it
    # through with Lota::Graphics.line.
    #
    # Control points are counted from 1, as in LÖVE, and back from the
    # last when negative: -1 is the last. LÖVE's C++ takes 0 as the first,
    # as it does 1, and wraps an index past the last around to the first.
    #
    # === Example
    #
    #   curve = Lota::Math::BezierCurve.new(0, 0, 100, 200, 200, 0)
    #   x, y = curve.evaluate(0.5) # => [100.0, 100.0]
    #   Lota::Graphics.line(*curve.render)
    class BezierCurve < Object
      # Wraps a BezierCurve the engine made. :nodoc:
      private_class_method def self.from_native(native)
        curve = allocate
        curve.instance_variable_set(:@native, native)
        curve
      end

      # Makes a curve through +coordinates+, matching
      # love.math.newBezierCurve (src/modules/math/wrap_Math.cpp:84-121).
      #
      # [coordinates] An x and a y Float or Integer for each control
      #   point, or an Array of them, as LÖVE takes a table.
      #
      # Raises TypeError for a coordinate that is not a number, and for
      # an x without its y, and RuntimeError when the math module is not
      # open.
      #
      # === Examples
      #
      #   Lota::Math::BezierCurve.new(1, 1, 2, 2, 3, 1)
      #   Lota::Math::BezierCurve.new([0, 0, 0, 1, 1, 1, 2, 1])
      def self.new(*coordinates)
        from_native(Native::Math.new_bezier_curve(Math.__send__(:coordinates_of, coordinates)))
      end

      # The curve's degree, one less than its number of control points, as
      # an Integer, matching BezierCurve:getDegree
      # (src/modules/math/wrap_BezierCurve.cpp:36-41).
      #
      # === Example
      #
      #   Lota::Math::BezierCurve.new(1, 1, 2, 2, 3, 1).degree # => 2
      def degree
        @native.degree
      end

      # A new curve, the derivative of this one, matching
      # BezierCurve:getDerivative
      # (src/modules/math/wrap_BezierCurve.cpp:43-50): the velocity along
      # this curve, as a curve of one degree less.
      #
      # Raises RuntimeError, with LÖVE's message, for a curve of degree 0.
      #
      # === Example
      #
      #   velocity = curve.derivative
      def derivative
        BezierCurve.__send__(:from_native, @native.derivative)
      end

      # The control point at +index+, counted from 1, as an Array of its x
      # and y Floats, matching BezierCurve:getControlPoint
      # (src/modules/math/wrap_BezierCurve.cpp:52-67), which returns both
      # (ADR 001, rule 4).
      #
      # [index] Integer, counted from 1, or back from the last when
      #   negative.
      #
      # Raises RuntimeError, with LÖVE's message, for a curve with no
      # control points.
      #
      # === Example
      #
      #   x, y = curve.control_point(2)
      def control_point(index)
        @native.control_point(index)
      end

      # Moves the control point at +index+ to +x+ and +y+, matching
      # BezierCurve:setControlPoint
      # (src/modules/math/wrap_BezierCurve.cpp:69-81), which takes the
      # three as one Array (ADR 001, rule 6).
      #
      # [point] Array of the Integer index, counted from 1 as
      #   #control_point counts it, and the Float or Integer x and y.
      #
      # === Example
      #
      #   curve.control_point = 2, 3, 2
      def control_point=(point)
        index, x, y = point
        @native.set_control_point(index, x, y)
      end

      # Adds a control point at +x+ and +y+, at +index+, matching
      # BezierCurve:insertControlPoint
      # (src/modules/math/wrap_BezierCurve.cpp:83-95).
      #
      # [x] Float or Integer.
      # [y] Float or Integer.
      # [index] Integer place it takes, counted from 1, or back from the
      #   last when negative: -1, the default, puts it before the last
      #   control point, which stays the last, as LÖVE's C++ counts it.
      #
      # === Example
      #
      #   curve.insert_control_point(4, 1)
      def insert_control_point(x, y, index = -1)
        @native.insert_control_point(x, y, index)
      end

      # Removes the control point at +index+, counted from 1, matching
      # BezierCurve:removeControlPoint
      # (src/modules/math/wrap_BezierCurve.cpp:97-107).
      #
      # Raises RuntimeError, with LÖVE's message, for a curve with no
      # control points.
      #
      # === Example
      #
      #   curve.remove_control_point(2)
      def remove_control_point(index)
        @native.remove_control_point(index)
      end

      # How many control points it has, as an Integer, matching
      # BezierCurve:getControlPointCount
      # (src/modules/math/wrap_BezierCurve.cpp:109-114).
      #
      # === Example
      #
      #   curve.control_point_count # => 3
      def control_point_count
        @native.control_point_count
      end

      # Moves every control point by +dx+ and +dy+, matching
      # BezierCurve:translate (src/modules/math/wrap_BezierCurve.cpp:
      # 116-123).
      #
      # === Example
      #
      #   curve.translate(5, -5)
      def translate(dx, dy)
        @native.translate(dx, dy)
      end

      # Rotates every control point by +angle+ radians around +ox+ and
      # +oy+, matching BezierCurve:rotate
      # (src/modules/math/wrap_BezierCurve.cpp:125-133).
      #
      # === Example
      #
      #   curve.rotate(Math::PI / 2)
      def rotate(angle, ox = 0, oy = 0)
        @native.rotate(angle, ox, oy)
      end

      # Scales every control point's distance from +ox+ and +oy+ by +s+,
      # matching BezierCurve:scale
      # (src/modules/math/wrap_BezierCurve.cpp:135-143).
      #
      # === Example
      #
      #   curve.scale(2)
      def scale(s, ox = 0, oy = 0)
        @native.scale(s, ox, oy)
      end

      # The point +t+ of the way along the curve, from 0 at its start to 1
      # at its end, as an Array of its x and y Floats, matching
      # BezierCurve:evaluate (src/modules/math/wrap_BezierCurve.cpp:
      # 145-158), which returns both (ADR 001, rule 4).
      #
      # Raises RuntimeError, with LÖVE's message, for a +t+ outside 0 to 1
      # and for a curve of fewer than two control points.
      #
      # === Example
      #
      #   x, y = curve.evaluate(0.5)
      def evaluate(t)
        @native.evaluate(t)
      end

      # A new curve, the part of this one from +t1+ to +t2+ of the way
      # along it, matching BezierCurve:getSegment
      # (src/modules/math/wrap_BezierCurve.cpp:160-172).
      #
      # Raises RuntimeError, with LÖVE's message, for a +t1+ or +t2+
      # outside 0 to 1, or a +t2+ before +t1+.
      #
      # === Example
      #
      #   first_half = curve.segment(0, 0.5)
      def segment(t1, t2)
        BezierCurve.__send__(:from_native, @native.segment(t1, t2))
      end

      # The points to draw the curve through, as one Array of their x and
      # y Floats, matching BezierCurve:render
      # (src/modules/math/wrap_BezierCurve.cpp:174-192).
      #
      # [accuracy] Integer: the curve is cut into 2 to this power steps.
      #
      # Raises RuntimeError, with LÖVE's message, for a curve of fewer than
      # two control points.
      #
      # === Example
      #
      #   Lota::Graphics.line(*curve.render)
      def render(accuracy = 5)
        @native.render(accuracy)
      end

      # The points to draw the part of the curve from +start+ to +stop+
      # through, as #render gives them, matching BezierCurve:renderSegment
      # (src/modules/math/wrap_BezierCurve.cpp:194-214).
      #
      # === Example
      #
      #   Lota::Graphics.line(*curve.render_segment(0, 0.5))
      def render_segment(start, stop, accuracy = 5)
        @native.render_segment(start, stop, accuracy)
      end
    end
  end
end
