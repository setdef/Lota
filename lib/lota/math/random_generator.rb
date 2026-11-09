# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Math
    # A source of random numbers of its own, matching LÖVE's
    # RandomGenerator class (src/modules/math/RandomGenerator.h).
    #
    # Lota::Math.random draws from one generator the whole game shares, so
    # anything that draws from it between two rolls changes what the
    # second roll gives. A level built from a seed has to draw from a
    # generator nothing else touches to come out the same every time.
    #
    # A RandomGenerator is that generator: it has its own seed and its own
    # state, and a seed starts the same sequence in Lota as in LÖVE, on
    # every platform. #state saves where it is in its sequence, and
    # #state= returns to it.
    #
    # === Example
    #
    #   dungeon = Lota::Math::RandomGenerator.new(1234)
    #   width = dungeon.random(20, 40)
    #   saved = dungeon.state
    #   dungeon.random      # => a Float from 0 up to 1
    #   dungeon.state = saved
    class RandomGenerator < Object
      # Wraps a RandomGenerator the engine made, such as the one
      # Lota::Math draws from. :nodoc:
      private_class_method def self.from_native(native)
        generator = allocate
        generator.instance_variable_set(:@native, native)
        generator
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # Makes a generator, matching love.math.newRandomGenerator
      # (src/modules/math/wrap_Math.cpp:52-82).
      #
      # [low] Integer or Float seed, or with +high+ its low 32 bits; the
      #   seed every new generator starts from when +nil+.
      # [high] Integer or Float high 32 bits of a 64-bit seed.
      #
      # LÖVE truncates a seed to a whole number, and so does Lota. Raises
      # ArgumentError ("invalid random seed") for an infinite or NaN seed,
      # TypeError for one that is not a number, and RuntimeError when the
      # math module is not open.
      #
      # === Examples
      #
      #   Lota::Math::RandomGenerator.new
      #   Lota::Math::RandomGenerator.new(42)
      #   Lota::Math::RandomGenerator.new(3418323524, 20529293)
      def self.new(low = nil, high = nil)
        raise "Lota::Math is not open." unless Native::Math.open?

        generator = from_native(Native::RandomGenerator.new)
        generator.seed = [low, high] unless low.nil? && high.nil?
        generator
      end

      # A random number, matching RandomGenerator:random
      # (src/modules/math/wrap_RandomGenerator.lua:33-49).
      #
      # [min] Float or Integer: with +max+, the smallest number it returns;
      #   alone, the largest, counting from 1.
      # [max] Float or Integer largest number it returns.
      #
      # With no arguments it returns a Float from 0 up to, but not
      # including, 1. With one, a whole number from 1 to +min+; with two, a
      # whole number from +min+ to +max+, as LÖVE computes them from the
      # Float: <tt>floor(r * min) + 1</tt> and
      # <tt>floor(r * (max - min + 1)) + min</tt>. Ruby's floor is an
      # Integer, so whole bounds give an Integer, and a bound that is a
      # Float gives a Float: <tt>random(1, 6)</tt> returns 4, and
      # <tt>random(1.5, 3.5)</tt> 2.5.
      #
      # Raises TypeError for a bound that is not a number.
      #
      # === Examples
      #
      #   generator = Lota::Math::RandomGenerator.new(123)
      #   generator.random         # => 0.37068322251463
      #   generator.random(10)     # => 4
      #   generator.random(15, 100) # => 92
      def random(min = nil, max = nil)
        r = @native.random
        if !max.nil?
          low = RandomGenerator.__send__(:number, min) #: Float | Integer
          high = RandomGenerator.__send__(:number, max) #: Float | Integer
          whole = (r * (high.to_f - low + 1)).floor
          # The same sum either way, which Steep types for each kind of bound.
          case low
          when Integer then whole + low
          else whole + low
          end
        elsif !min.nil?
          bound = RandomGenerator.__send__(:number, min) #: Float | Integer
          (r * bound).floor + 1
        else
          r
        end
      end

      # A random number from a normal distribution, matching
      # RandomGenerator:randomNormal, in the FFI code LÖVE runs under
      # LuaJIT (src/modules/math/wrap_RandomGenerator.lua:82-93).
      #
      # [stddev] Float or Integer standard deviation, 1 when +nil+.
      # [mean] Float or Integer mean, 0 when +nil+.
      #
      # Raises TypeError for an argument that is not a number.
      #
      # === Example
      #
      #   generator.random_normal       # => a Float, most often near 0
      #   generator.random_normal(15, 100)
      def random_normal(stddev = nil, mean = nil)
        @native.random_normal(stddev && RandomGenerator.__send__(:number, stddev), mean && RandomGenerator.__send__(:number, mean))
      end

      # Seeds the generator, matching RandomGenerator:setSeed
      # (src/modules/math/wrap_RandomGenerator.cpp:49-62 and 88-93).
      #
      # [seed] Integer or Float seed, or an Array of two: the low and high
      #   32 bits of a 64-bit seed.
      #
      # The same seed starts the same sequence. Raises ArgumentError
      # ("invalid random seed") for an infinite or NaN seed, and TypeError
      # for one that is not a number.
      #
      # === Examples
      #
      #   generator.seed = 123
      #   generator.seed = 0xCBBF7A44, 0x0139408D
      def seed=(seed)
        low, high = seed.is_a?(Array) ? seed : [seed]
        @native.set_seed(RandomGenerator.__send__(:number, low), high && RandomGenerator.__send__(:number, high))
      end

      # The seed's low and high 32 bits, as an Array of two Integers,
      # matching RandomGenerator:getSeed
      # (src/modules/math/wrap_RandomGenerator.cpp:95-102), which returns
      # both (rule 4 of doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   low, high = Lota::Math::RandomGenerator.new(9001).seed # => [9001, 0]
      def seed
        @native.seed
      end

      # Where the generator is in its sequence, as a String, matching
      # RandomGenerator:getState
      # (src/modules/math/wrap_RandomGenerator.cpp:111-116).
      #
      # It is a hexadecimal number, such as
      # <tt>"0x2a5dbb4b7e0c3fe2"</tt>, which #state= takes back.
      #
      # === Example
      #
      #   saved = generator.state
      def state
        @native.state
      end

      # Returns the generator to a place in its sequence, matching
      # RandomGenerator:setState
      # (src/modules/math/wrap_RandomGenerator.cpp:104-109).
      #
      # [state] String a #state returned.
      #
      # Raises RuntimeError ("Invalid random state: ...") for a String that
      # is not a hexadecimal number beginning <tt>0x</tt>, and TypeError
      # for anything but a String.
      #
      # === Example
      #
      #   generator.state = saved
      def state=(state)
        @native.state = state
      end

      # A bound or a seed, which must be a number, as getrandom and
      # randomNormal check. :nodoc:
      private_class_method def self.number(value)
        case value
        when Integer, Float then value
        else raise TypeError, "wrong argument type #{value.class} (expected Float or Integer)"
        end
      end

      # SPDX-SnippetEnd
    end
  end
end
