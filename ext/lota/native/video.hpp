// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_VIDEO_HPP
#define LOTA_NATIVE_VIDEO_HPP

#include "native/binding.hpp"

namespace lota::native {

// Binds love::video::VideoStream as <native>::VideoStream, with the
// methods the generator does not write, love.video's functions as module
// functions of <native>::Video, and love::graphics::Video as
// <native>::Graphics::Video, with love.graphics._newVideo. Their other
// methods are generated, so it runs before define_generated.
void define_video(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_VIDEO_HPP
