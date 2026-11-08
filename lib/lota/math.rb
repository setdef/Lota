# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "deprecation"
require_relative "math/bezier_curve"
require_relative "math/random_generator"
require_relative "math/transform"

module Lota
  # Math for games, translated from love.math.
  #
  # A game that rolls dice, scatters stars, or places enemies at random
  # needs random numbers, and a game that is to behave the same on every
  # machine, or replay a level from a seed, needs the same random numbers
  # from the same seed everywhere.
  #
  # Lota::Math draws them from LÖVE's own generator, the one
  # love.math.random draws from, so a seed gives the same sequence in Lota
  # as in LÖVE on every platform. Ruby's own +rand+ uses a different
  # generator, and so does Lua's +math.random+. A
  # Lota::Math::RandomGenerator draws from a generator of its own.
  #
  # It also has the rest of love.math: noise for terrain and clouds,
  # polygons cut into triangles, colors converted between bytes and
  # fractions and between gamma and linear space, Lota::Math::BezierCurve,
  # and Lota::Math::Transform.
  #
  # === Example
  #
  #   Lota::Math.random_seed = 42
  #   Lota::Math.random        # => a Float from 0 up to 1
  #   Lota::Math.random(6)     # => an Integer from 1 to 6
  #   Lota::Math.random(10, 20) # => an Integer from 10 to 20
  module Math
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # A random number from LÖVE's generator, matching love.math.random
    # (src/modules/math/wrap_Math.lua:37-39), which draws as
    # Lota::Math::RandomGenerator#random draws.
    #
    # [min] Float or Integer: with +max+, the smallest number it returns;
    #   alone, the largest, counting from 1.
    # [max] Float or Integer largest number it returns.
    #
    # Raises TypeError for a bound that is not a number, and RuntimeError
    # when the math module is not open, as when
    # <tt>t.modules.math = false</tt>.
    #
    # === Examples
    #
    #   Lota::Math.random         # => 0.37068322251463
    #   Lota::Math.random(10)     # => 4
    #   Lota::Math.random(15, 100) # => 92
    def self.random(min = nil, max = nil)
      generator.random(min, max)
    end

    # A random number from a normal distribution, from LÖVE's generator,
    # matching love.math.randomNormal (src/modules/math/wrap_Math.lua:
    # 41-43), which draws as Lota::Math::RandomGenerator#random_normal
    # draws.
    #
    # [stddev] Float or Integer standard deviation, 1 when +nil+.
    # [mean] Float or Integer mean, 0 when +nil+.
    #
    # Raises TypeError for an argument that is not a number, and
    # RuntimeError when the math module is not open.
    #
    # === Example
    #
    #   Lota::Math.random_seed = 1234
    #   Lota::Math.random_normal(1, 2) # => 1.0813614997254
    def self.random_normal(stddev = nil, mean = nil)
      generator.random_normal(stddev, mean)
    end

    # Seeds LÖVE's generator, matching love.math.setRandomSeed
    # (src/modules/math/wrap_Math.lua:45-47), which seeds it as
    # Lota::Math::RandomGenerator#seed= does.
    #
    # [seed] Integer or Float seed, or an Array of two: the low and high
    #   32 bits of a 64-bit seed.
    #
    # The same seed starts the same sequence. LÖVE truncates a seed to a
    # whole number, as it casts it to an integer, and so does Lota.
    #
    # Raises ArgumentError ("invalid random seed") for an infinite or NaN
    # seed, TypeError for one that is not a number, and RuntimeError when
    # the math module is not open.
    #
    # === Examples
    #
    #   Lota::Math.random_seed = 123
    #   Lota::Math.random_seed = 0xCBBF7A44, 0x0139408D
    def self.random_seed=(seed)
      generator.seed = seed
    end

    # The seed of LÖVE's generator, its low and high 32 bits as an Array
    # of two Integers, matching love.math.getRandomSeed
    # (src/modules/math/wrap_Math.lua:49-51).
    #
    # Raises RuntimeError when the math module is not open.
    #
    # === Example
    #
    #   Lota::Math.random_seed = 9001
    #   low, high = Lota::Math.random_seed # => [9001, 0]
    def self.random_seed
      generator.seed
    end

    # Where LÖVE's generator is in its sequence, as a String, matching
    # love.math.getRandomState (src/modules/math/wrap_Math.lua:57-59),
    # which Lota::Math.random_state= takes back.
    #
    # Raises RuntimeError when the math module is not open.
    #
    # === Example
    #
    #   saved = Lota::Math.random_state
    def self.random_state
      generator.state
    end

    # Returns LÖVE's generator to a place in its sequence, matching
    # love.math.setRandomState (src/modules/math/wrap_Math.lua:53-55).
    #
    # [state] String Lota::Math.random_state returned.
    #
    # Raises RuntimeError ("Invalid random state: ...") for a String that
    # is not a hexadecimal number beginning <tt>0x</tt>, and when the math
    # module is not open.
    #
    # === Example
    #
    #   Lota::Math.random_state = saved
    def self.random_state=(state)
      generator.state = state
    end

    # A color's components as whole numbers from 0 to 255, matching
    # love.math.colorToBytes (src/modules/math/wrap_Math.lua:61-70).
    #
    # [r] Float red from 0 to 1, or an Array of the components.
    # [g] Float green.
    # [b] Float blue.
    # [a] Float alpha, or +nil+.
    #
    # Each is clamped to 0 to 1 first, then rounded to the nearest byte, as
    # an Integer. The Array holds red, green, and blue, and alpha when it is
    # given, as Lua returns a nil alpha that Ruby has no use for. Raises
    # TypeError for a component that is not a number.
    #
    # === Examples
    #
    #   Lota::Math.color_to_bytes(0.2, 0.2, 0.2, 0.2) # => [51, 51, 51, 51]
    #   Lota::Math.color_to_bytes([1, 0.5, 0])        # => [255, 128, 0]
    def self.color_to_bytes(r, g = nil, b = nil, a = nil)
      r, g, b, a = r if r.is_a?(Array)
      bytes = [r, g, b].map { |c| ((clamp01(c) * 255) + 0.5).floor }
      a.nil? ? bytes : [*bytes, ((clamp01(a) * 255) + 0.5).floor]
    end

    # A color's components as fractions from 0 to 1, from whole numbers
    # from 0 to 255, matching love.math.colorFromBytes
    # (src/modules/math/wrap_Math.lua:72-81).
    #
    # [r] Integer or Float red, or an Array of the components.
    # [g] Integer or Float green.
    # [b] Integer or Float blue.
    # [a] Integer or Float alpha, or +nil+.
    #
    # Each is rounded to a whole number first, then divided by 255 and
    # clamped to 0 to 1, as a Float. The Array holds alpha only when it is
    # given, as Lota::Math.color_to_bytes does. Raises TypeError for a
    # component that is not a number.
    #
    # === Example
    #
    #   Lota::Math.color_from_bytes(51, 51, 51, 51) # => [0.2, 0.2, 0.2, 0.2]
    def self.color_from_bytes(r, g = nil, b = nil, a = nil)
      r, g, b, a = r if r.is_a?(Array)
      fractions = [r, g, b].map { |c| clamp01((number(c) + 0.5).floor / 255.0).to_f }
      a.nil? ? fractions : [*fractions, clamp01((number(a) + 0.5).floor / 255.0).to_f]
    end

    # A color from gamma space to linear space, matching
    # love.math.gammaToLinear, in the FFI code LÖVE runs under LuaJIT
    # (src/modules/math/wrap_Math.lua:153-166).
    #
    # [r] Float red from 0 to 1, or an Array of the components.
    # [g] Float green, or +nil+.
    # [b] Float blue, or +nil+.
    # [a] Float alpha, or +nil+.
    #
    # Red, green, and blue are clamped to 0 to 1 and converted; alpha is
    # linear already, so it comes back as it was given. Lua returns a
    # +nil+ for each component not given; Lota leaves those off the end of
    # the Array. Raises TypeError for a component that is not a number.
    #
    # === Example
    #
    #   Lota::Math.gamma_to_linear(1, 1, 1, 0.5) # => [1.0, 1.0, 1.0, 0.5]
    #   linear = Lota::Math.gamma_to_linear(Lota::Graphics.color)
    def self.gamma_to_linear(r, g = nil, b = nil, a = nil)
      convert_color(r, g, b, a) { |c| Native::Math.gamma_to_linear(c) }
    end

    # A color from linear space to gamma space, matching
    # love.math.linearToGamma, in the FFI code LÖVE runs under LuaJIT
    # (src/modules/math/wrap_Math.lua:168-181), as
    # Lota::Math.gamma_to_linear takes and returns it.
    #
    # === Example
    #
    #   Lota::Math.linear_to_gamma(0, 0, 0, 0.5) # => [0.0, 0.0, 0.0, 0.5]
    def self.linear_to_gamma(r, g = nil, b = nil, a = nil)
      convert_color(r, g, b, a) { |c| Native::Math.linear_to_gamma(c) }
    end

    # Whether the polygon is convex, matching love.math.isConvex
    # (src/modules/math/wrap_Math.cpp:218-253).
    #
    # [coordinates] An x and a y Float or Integer for each vertex, or an
    #   Array of them, as LÖVE takes a table.
    #
    # Raises TypeError for a coordinate that is not a number, and for an x
    # without its y.
    #
    # === Example
    #
    #   Lota::Math.convex?([0, 0, 1, 0, 1, 1, 0, 1]) # => true
    def self.convex?(*coordinates)
      Native::Math.convex?(coordinates_of(coordinates))
    end

    # The triangles that fill the polygon, matching love.math.triangulate
    # (src/modules/math/wrap_Math.cpp:148-216): an Array with an Array for
    # each triangle, of its three corners' x and y Floats.
    #
    # [coordinates] An x and a y Float or Integer for each vertex, or an
    #   Array of them, as LÖVE takes a table.
    #
    # Raises RuntimeError, with LÖVE's message, for fewer than three
    # vertices and for a polygon it cannot cut, and TypeError for a
    # coordinate that is not a number.
    #
    # === Example
    #
    #   Lota::Math.triangulate(0, 0, 1, 0, 1, 1, 0, 1).size # => 2
    def self.triangulate(*coordinates)
      Native::Math.triangulate(coordinates_of(coordinates))
    end

    # Perlin noise at a point of one to four dimensions, from 0 to 1,
    # matching love.math.perlinNoise, in the FFI code LÖVE runs under
    # LuaJIT (src/modules/math/wrap_Math.lua:129-139).
    #
    # [x] Float or Integer.
    # [y] Float or Integer, or +nil+ for one dimension.
    # [z] Float or Integer, or +nil+ for two or fewer.
    # [w] Float or Integer, or +nil+ for three or fewer.
    #
    # The same point always gives the same noise, and nearby points give
    # nearby noise, which makes it fit for terrain, clouds, and wandering
    # motion. As in LÖVE, the last coordinate given decides how many
    # dimensions it has, and every coordinate before it must be a number;
    # Raises TypeError otherwise.
    #
    # === Example
    #
    #   height = Lota::Math.perlin_noise(x / 64.0, y / 64.0)
    def self.perlin_noise(x, y = nil, z = nil, w = nil)
      if !w.nil? then Native::Math.perlin_noise4(x, number(y), number(z), w)
      elsif !z.nil? then Native::Math.perlin_noise3(x, number(y), z)
      elsif !y.nil? then Native::Math.perlin_noise2(x, y)
      else Native::Math.perlin_noise1(x)
      end
    end

    # Simplex noise at a point of one to four dimensions, from 0 to 1,
    # matching love.math.simplexNoise, in the FFI code LÖVE runs under
    # LuaJIT (src/modules/math/wrap_Math.lua:141-151), as
    # Lota::Math.perlin_noise takes it.
    #
    # === Example
    #
    #   drift = Lota::Math.simplex_noise(Lota::Timer.time)
    def self.simplex_noise(x, y = nil, z = nil, w = nil)
      if !w.nil? then Native::Math.simplex_noise4(x, number(y), number(z), w)
      elsif !z.nil? then Native::Math.simplex_noise3(x, number(y), z)
      elsif !y.nil? then Native::Math.simplex_noise2(x, y)
      else Native::Math.simplex_noise1(x)
      end
    end

    # Noise at a point of one to four dimensions, matching the deprecated
    # love.math.noise, in the FFI code LÖVE runs under LuaJIT
    # (src/modules/math/wrap_Math.lua:115-127): simplex noise in one or
    # two dimensions, and Perlin noise in three or four.
    #
    # Prints LÖVE's notice that Lota::Math.perlin_noise or
    # Lota::Math.simplex_noise replaces it, once per line of the game that
    # calls it.
    #
    # === Example
    #
    #   Lota::Math.noise(1, 10)
    def self.noise(x, y = nil, z = nil, w = nil)
      Deprecation.mark("Lota::Math.noise", :function, :replaced, "Lota::Math.perlin_noise or Lota::Math.simplex_noise",
        where: Deprecation.where(caller_locations(1, 1)))
      if !w.nil? then Native::Math.perlin_noise4(x, number(y), number(z), w)
      elsif !z.nil? then Native::Math.perlin_noise3(x, number(y), z)
      elsif !y.nil? then Native::Math.simplex_noise2(x, y)
      else Native::Math.simplex_noise1(x)
      end
    end

    # The coordinates a function given +arguments+ reads, as LÖVE reads a
    # table in the first argument's place, or else every argument.
    # :nodoc:
    private_class_method def self.coordinates_of(arguments)
      first = arguments.first
      first.is_a?(Array) ? first : arguments #: Array[number]
    end

    # LÖVE's own generator, the one wrap_Math.lua draws from
    # (src/modules/math/wrap_Math.lua:35), which raises RuntimeError when
    # the math module is not open.
    private_class_method def self.generator
      RandomGenerator.__send__(:from_native, Native::Math.random_generator)
    end

    # clamp01 (src/modules/math/wrap_Math.lua:31-33): +c+ no lower than 0
    # and no higher than 1, as math.min and math.max keep it, a Float
    # where it is one.
    private_class_method def self.clamp01(c)
      number(c).clamp(0.0, 1.0)
    end

    # The red, green, and blue of the color, each through the block when
    # it is given, and its alpha, as the FFI code's gammaToLinear and
    # linearToGamma make them (src/modules/math/wrap_Math.lua:153-181),
    # without the nils Lua returns for the components not given.
    private_class_method def self.convert_color(r, g, b, a)
      r, g, b, a = r if r.is_a?(Array)
      converted = [r, g, b].map { |c| c.nil? ? nil : yield(clamp01(c)) }
      [*converted, a].reverse.drop_while(&:nil?).reverse
    end

    # A number, which each of these functions needs, as LuaJIT's math
    # library and FFI check.
    private_class_method def self.number(value)
      RandomGenerator.__send__(:number, value)
    end

    # SPDX-SnippetEnd
  end
end
