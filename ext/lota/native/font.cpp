// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/font.hpp"

#include "native/binding.hpp"

#include "common/Module.h"
#include "font/Font.h"
#include "font/freetype/Font.h"

namespace lota::native {

namespace {

// luaopen_love_font (vendor/love/src/modules/font/wrap_Font.cpp:261-279)
// creates the FreeType font module once; it then lives as long as the
// process, as LÖVE's lives until the game quits. The graphics module
// rasterizes its default font, and every font made from a file, with it
// (graphics/Graphics.cpp:336-344).
void open() { open_module<love::font::Font, love::font::freetype::Font>(love::Module::M_FONT); }

// Whether the module is open, as boot.lua asks with "if love.font".
bool is_open() {
  return love::Module::getInstance<love::font::Font>(love::Module::M_FONT) != nullptr;
}

} // namespace

void define_font(const Rice::Module &native) {
  Rice::define_module_under(native, "Font")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open);
}

} // namespace lota::native
