// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/touch.hpp"

#include "native/binding.hpp"

#include "touch/Touch.h"

namespace lota::native {

namespace {

// w__setTrackpadTouch (vendor/love/src/modules/love/love.cpp:447-453):
// whether a trackpad reports touches (touch/sdl/Touch.cpp:37-40).
void set_trackpad_touch(bool enable) { love::touch::setTrackpadTouch(enable); }

} // namespace

void define_touch(const Rice::Module &native) {
  Rice::define_module_under(native, "Touch")
      .define_singleton_function("set_trackpad_touch", &set_trackpad_touch, Rice::Arg("enable"));
}

} // namespace lota::native
