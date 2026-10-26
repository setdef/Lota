// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/random_generator.hpp"

#include "native/binding.hpp"

#include "math/RandomGenerator.h"

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

} // namespace

// love::math::RandomGenerator, whose other methods the generator binds
// from LÖVE's wrap functions (ext/lota/native/generated/math.cpp).
// RandomGenerator:random's ranges are Lua in LÖVE (wrap_RandomGenerator.lua:
// 33-49), and the seed's two halves are read at a position LÖVE computes
// (wrap_RandomGenerator.cpp:49-62 and 88-102), so they are Ruby's to port.
void define_random_generator(const Rice::Module &native) {
  Rice::define_class_under<RandomGenerator>(native, "RandomGenerator")
      // love.math.newRandomGenerator() with no seed: Math::newRandomGenerator
      // is `new RandomGenerator()` (vendor/love/src/modules/math/
      // MathModule.cpp:216-219), and the wrapper adopts its reference.
      .define_constructor(Rice::Constructor<RandomGenerator>())
      // LÖVE's _random, under the name of the Lua RandomGenerator:random
      // that wraps it (wrap_RandomGenerator.lua:46-49).
      .define_method("random", unit_random());
}

} // namespace lota::native
