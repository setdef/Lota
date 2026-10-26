// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/random_generator.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "math/RandomGenerator.h"

#include "common/int.h"

#include <bit>
#include <cmath>
#include <optional>

namespace lota::native {

using love::math::RandomGenerator;

namespace {

// The overload of random() with no range: a double in [0, 1)
// (RandomGenerator.h), which w_RandomGenerator__random calls
// (wrap_RandomGenerator.cpp:69-74). It is returned, not stored in a
// variable, because Rice keeps a method passed as an lvalue by reference
// (define_method forwards Method_T&&, and rice/detail/NativeMethod.hpp:82
// stores a Method_T), so a local would dangle once the binding returned.
using UnitRandom = double (RandomGenerator::*)();
constexpr UnitRandom unit_random() { return &RandomGenerator::random; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// checkrandomseed_part (vendor/love/src/modules/math/
// wrap_RandomGenerator.cpp:36-47): a seed part may not be infinite or NaN,
// and is cast to the integer type as LÖVE casts it. luaL_argerror's
// "invalid random seed" becomes Ruby's ArgumentError.
template <typename T> T seed_part(double number) {
  if (std::isinf(number) || std::isnan(number)) {
    raise_argument_error("invalid random seed");
  }
  return static_cast<T>(number);
}

// w_RandomGenerator_setSeed (wrap_RandomGenerator.cpp:88-93), through
// luax_checkrandomseed (lines 49-62): a seed of two 32-bit halves when
// +high+ is given, or of one 64-bit number when it is not. RandomGenerator::
// Seed is a union of the 64-bit number and its halves, low and high in the
// machine's order (RandomGenerator.h:46-59), so writing the halves is
// writing the number whose high 32 bits are +high+ and low 32 bits +low+;
// the seed is made from that number, without reaching into the union.
void set_seed(RandomGenerator &rng, double low, std::optional<double> high) {
  constexpr unsigned half = 32U;
  love::uint64 number = 0;
  if (high.has_value()) {
    number = (static_cast<love::uint64>(seed_part<love::uint32>(high.value())) << half) |
             seed_part<love::uint32>(low);
  } else {
    number = seed_part<love::uint64>(low);
  }
  rng.setSeed(std::bit_cast<RandomGenerator::Seed>(number));
}

// SPDX-SnippetEnd

} // namespace

// love::math::RandomGenerator, whose other methods the generator binds
// from LÖVE's wrap functions (ext/lota/native/generated/math.cpp).
// RandomGenerator:random's ranges are Lua in LÖVE (wrap_RandomGenerator.lua:
// 33-49), so they are Ruby's to port (Lota::Math.random), and setSeed reads
// its seed's two halves at a position LÖVE computes
// (wrap_RandomGenerator.cpp:49-62 and 88-102), so it is bound here.
void define_random_generator(const Rice::Module &native) {
  Rice::define_class_under<RandomGenerator>(native, "RandomGenerator")
      // love.math.newRandomGenerator() with no seed: Math::newRandomGenerator
      // is `new RandomGenerator()` (vendor/love/src/modules/math/
      // MathModule.cpp:216-219), and the wrapper adopts its reference.
      .define_constructor(Rice::Constructor<RandomGenerator>())
      // LÖVE's _random, under the name of the Lua RandomGenerator:random
      // that wraps it (wrap_RandomGenerator.lua:46-49).
      .define_method("random", unit_random())
      .define_method("set_seed", &set_seed, Rice::Arg("low"),
                     Rice::Arg("high") = std::optional<double>());
}

} // namespace lota::native
