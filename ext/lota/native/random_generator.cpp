// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/random_generator.hpp"

#include "native/binding.hpp"

#include "math/RandomGenerator.h"

namespace lota::native {

using love::math::RandomGenerator;

namespace {

// The overload of random() with no range: a double in [0, 1)
// (RandomGenerator.h). It is returned, not stored in a variable, because
// Rice keeps a method passed as an lvalue by reference (define_method
// forwards Method_T&&, and rice/detail/NativeMethod.hpp:82 stores a
// Method_T), so a local would dangle once the binding returned.
using UnitRandom = double (RandomGenerator::*)();
constexpr UnitRandom unit_random() { return &RandomGenerator::random; }

} // namespace

// The methods LÖVE implements in C++ (vendor/love/src/modules/math/
// wrap_RandomGenerator.cpp:69-116), bound as the C++ defines them.
// RandomGenerator:random's ranges, randomNormal's mean, and the seed's two
// halves are Lua in LÖVE (wrap_RandomGenerator.lua:33-49, and
// wrap_RandomGenerator.cpp:49-62 and 80-84), so they are Ruby's to port.
void define_random_generator(const Rice::Module &native) {
  Rice::define_class_under<RandomGenerator>(native, "RandomGenerator")
      // love.math.newRandomGenerator() with no seed: Math::newRandomGenerator
      // is `new RandomGenerator()` (vendor/love/src/modules/math/
      // MathModule.cpp:216-219), and the wrapper adopts its reference.
      .define_constructor(Rice::Constructor<RandomGenerator>())
      .define_method("random", unit_random())
      .define_method("random_normal", &RandomGenerator::randomNormal, Rice::Arg("stddev"))
      .define_method("state", &RandomGenerator::getState)
      // setState raises love::Exception ("Invalid random state: ...",
      // RandomGenerator.cpp), which Rice raises in Ruby as a RuntimeError
      // with the same message (rice/detail/cpp_protect.hpp:92).
      .define_method("state=", &RandomGenerator::setState, Rice::Arg("state"));
}

} // namespace lota::native
