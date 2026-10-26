// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Lota::Native: LÖVE's engine, bound to Ruby with Rice (ADR 001, section 4).

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/event.hpp"
#include "native/filesystem.hpp"
#include "native/font.hpp"
#include "native/generated/bindings.hpp"
#include "native/graphics.hpp"
#include "native/image.hpp"
#include "native/keyboard.hpp"
#include "native/math.hpp"
#include "native/mouse.hpp"
#include "native/random_generator.hpp"
#include "native/system.hpp"
#include "native/timer.hpp"
#include "native/touch.hpp"
#include "native/window.hpp"

#include "common/version.h"

#include <cstddef>
#include <string>

namespace {

// The point where the main thread carries out the releases Ruby's garbage
// collector asked for on other threads (ADR 001, section 5). The game loop
// calls it once a frame; until then, whoever drives the engine does, and
// lib/lota.rb drains it at exit.
std::size_t drain_release_queue() { return lota::native::ReleaseQueue::instance().drain(); }

std::size_t queued_releases() { return lota::native::ReleaseQueue::instance().size(); }

} // namespace

// Ruby calls this when it loads the bundle (require "lota/native"). It is
// the only symbol the bundle exports (cmake/LotaExtension.cmake).
extern "C" __attribute__((visibility("default"))) void Init_native() {
  // Before any binding, so that every error the engine raises reaches Ruby
  // with LÖVE's Lua names translated (native/errors.hpp).
  lota::native::install_error_translation();
  Rice::Module native = Rice::define_module_under(Rice::define_module("Lota"), "Native");
  lota::native::define_random_generator(native);
  lota::native::define_math(native);
  lota::native::define_filesystem(native);
  lota::native::define_image(native);
  lota::native::define_font(native);
  lota::native::define_timer(native);
  lota::native::define_event(native);
  lota::native::define_keyboard(native);
  lota::native::define_mouse(native);
  lota::native::define_touch(native);
  lota::native::define_system(native);
  lota::native::define_window(native);
  lota::native::define_graphics(native);
  // After the hand-written bindings, which define the classes the
  // generated ones add methods to.
  lota::native::define_generated(native);

  // love._version (vendor/love/src/modules/love/love.cpp:546-547), the
  // engine's version, which boot.lua's settings default to.
  Rice::String version(std::string{love::VERSION});
  version.freeze();
  native.const_set("VERSION", version);

  native.define_singleton_function("drain_release_queue", &drain_release_queue)
      .define_singleton_function("queued_releases", &queued_releases);
}
