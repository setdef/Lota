# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

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
  # generator, and so does Lua's +math.random+.
  #
  # Use it for randomness that should repeat from a seed.
  #
  # === Example
  #
  #   Lota::Math.random_seed = 42
  #   Lota::Math.random        # => a Float from 0 up to 1
  #   Lota::Math.random(6)     # => a whole number from 1 to 6
  #   Lota::Math.random(10, 20) # => a whole number from 10 to 20
  module Math
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # A random number from LÖVE's generator, matching love.math.random
    # (src/modules/math/wrap_Math.lua:37-39, and getrandom in
    # wrap_RandomGenerator.lua:33-44).
    #
    # [min] Float or Integer: with +max+, the smallest number it returns;
    #   alone, the largest, counting from 1.
    # [max] Float or Integer largest number it returns.
    #
    # With no arguments it returns a Float from 0 up to, but not
    # including, 1. With one, a whole number from 1 to +min+; with two, a
    # whole number from +min+ to +max+. LÖVE computes the whole number
    # from the Float as <tt>floor(r * (max - min + 1)) + min</tt>, in Lua,
    # which holds every number as a double, so Lota returns it as a Float
    # too (ADR 001, rule 14): <tt>random(6)</tt> returns 4.0, not 4.
    #
    # Raises TypeError for a bound that is not a number, and RuntimeError
    # when the math module is not open, as when
    # <tt>t.modules.math = false</tt>.
    #
    # === Examples
    #
    #   Lota::Math.random         # => 0.37068322251463
    #   Lota::Math.random(10)     # => 4.0
    #   Lota::Math.random(15, 100) # => 92.0
    def self.random(min = nil, max = nil)
      r = Native::Math.random_generator.random
      if !max.nil?
        low = number(min)
        (r * (number(max).to_f - low + 1)).floor.to_f + low
      elsif !min.nil?
        (r * number(min)).floor.to_f + 1
      else
        r
      end
    end

    # Seeds LÖVE's generator, matching love.math.setRandomSeed
    # (src/modules/math/wrap_Math.lua:45-47, which calls
    # RandomGenerator:setSeed, wrap_RandomGenerator.cpp:49-62 and 88-93).
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
      low, high = seed.is_a?(Array) ? seed : [seed]
      Native::Math.random_generator.set_seed(number(low), high && number(high))
    end

    # A bound, which must be a number, as getrandom checks.
    private_class_method def self.number(value)
      case value
      when Integer, Float then value
      else raise TypeError, "wrong argument type #{value.class} (expected Float or Integer)"
      end
    end

    # SPDX-SnippetEnd
  end
end
