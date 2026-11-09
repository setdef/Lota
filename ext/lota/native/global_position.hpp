// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Where a point on the desktop lies on its displays, the arithmetic of
// Lota::Mouse.global_position (native/mouse.cpp). It is apart from SDL's
// calls so that a test can give it displays the computer running the test
// has not got (LotaNativeTest.place_on_displays).
//
// LÖVE's Mouse::getGlobalPosition subtracts the origin of every display
// before the one the point is on (doc/contributors/upstream/022.md). This
// subtracts that display's origin alone, which is what LÖVE means and what
// it answers whenever the displays before that one start at the desktop's
// origin, as on a desktop of one display.

#ifndef LOTA_NATIVE_GLOBAL_POSITION_HPP
#define LOTA_NATIVE_GLOBAL_POSITION_HPP

#include <SDL3/SDL_rect.h>

#include <span>

namespace lota::native {

// A point's place on a display, and that display's index, counting from 0
// as SDL's list of displays does.
struct DisplayPlace {
  double x;
  double y;
  int displayindex;
};

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from Mouse::getGlobalPosition (vendor/love/src/modules/mouse/sdl/
// Mouse.cpp:166-197), given the displays' bounds instead of asking SDL for
// them, and subtracting only the origin of the display the point is on.

// The place of the point at +globalx+ and +globaly+ on the first of
// +bounds+, in order, that holds it, as SDL_PointInRectFloat decides, so a
// point on the edge between two displays is on the earlier one. The
// subtraction is a float's, as LÖVE's is. A point on no display is on
// the first, as LÖVE has it (lines 192-193), and placed against that
// display's origin; with no displays at all it keeps its desktop position.
inline DisplayPlace place_on_displays(float globalx, float globaly,
                                      std::span<const SDL_Rect> bounds) {
  const SDL_FPoint point = {.x = globalx, .y = globaly};
  int index = 0;
  for (const SDL_Rect &rect : bounds) {
    const SDL_FRect frect = {
        .x = static_cast<float>(rect.x),
        .y = static_cast<float>(rect.y),
        .w = static_cast<float>(rect.w),
        .h = static_cast<float>(rect.h),
    };
    if (SDL_PointInRectFloat(&point, &frect)) {
      const float x = globalx - frect.x;
      const float y = globaly - frect.y;
      return {.x = static_cast<double>(x), .y = static_cast<double>(y), .displayindex = index};
    }
    index++;
  }
  if (bounds.empty()) {
    const auto x = static_cast<double>(globalx);
    const auto y = static_cast<double>(globaly);
    return {.x = x, .y = y, .displayindex = 0};
  }
  const float x = globalx - static_cast<float>(bounds.front().x);
  const float y = globaly - static_cast<float>(bounds.front().y);
  return {.x = static_cast<double>(x), .y = static_cast<double>(y), .displayindex = 0};
}

// SPDX-SnippetEnd

} // namespace lota::native

#endif // LOTA_NATIVE_GLOBAL_POSITION_HPP
