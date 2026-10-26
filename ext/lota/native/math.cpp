// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/math.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "math/MathModule.h"
#include "math/RandomGenerator.h"

namespace lota::native {

using love::math::Math;
using love::math::RandomGenerator;

namespace {

// luaopen_love_math (vendor/love/src/modules/math/wrap_Math.cpp:471-499)
// creates the math module once; it then lives as long as the process, as
// LÖVE's lives until the game quits. Its constructor seeds its random
// number generator with the time (MathModule.cpp:202-210).
void open() { open_module<Math, Math>(love::Module::M_MATH); }

// Whether the module is open, as a game asks with "if love.math".
bool is_open() { return love::Module::getInstance<Math>(love::Module::M_MATH) != nullptr; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w__getRandomGenerator (vendor/love/src/modules/math/wrap_Math.cpp:45-50):
// the module's own generator, which love.math.random and the rest of
// wrap_Math.lua draw from (lines 35-59). The module keeps its reference,
// and the Ruby wrapper retains one more, as luax_pushtype does.
RandomGenerator *random_generator() {
  auto *instance = love::Module::getInstance<Math>(love::Module::M_MATH);
  if (instance == nullptr) {
    throw love::Exception("Lota::Math is not open.");
  }
  return instance->getRandomGenerator();
}

// SPDX-SnippetEnd

} // namespace

void define_math(const Rice::Module &native) {
  Rice::define_module_under(native, "Math")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("random_generator", &random_generator);
}

} // namespace lota::native
