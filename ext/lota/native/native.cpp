// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Lota::Native: LÖVE's engine, bound to Ruby with Rice (ADR 001, section 4).

#include "native/binding.hpp"
#include "native/random_generator.hpp"

// Ruby calls this when it loads the bundle (require "lota/native"). It is
// the only symbol the bundle exports (cmake/LotaExtension.cmake).
extern "C" __attribute__((visibility("default"))) void Init_native() {
  const Rice::Module native = Rice::define_module_under(Rice::define_module("Lota"), "Native");
  lota::native::define_random_generator(native);
}
