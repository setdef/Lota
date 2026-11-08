// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef LOTA_NATIVE_FONT_HPP
#define LOTA_NATIVE_FONT_HPP

#include "native/binding.hpp"

#include "font/TrueTypeRasterizer.h"

#include <optional>
#include <string>

namespace lota::native {

// luax_checktruetypesettings (vendor/love/src/modules/font/wrap_Font.cpp:
// 67-104): the hinting mode by name, the DPI scale when given, and whether
// glyphs are signed distance fields. An unknown hinting mode raises LÖVE's
// enum error. love.graphics.newFont reads its settings through it too
// (native/graphics.cpp).
love::font::TrueTypeRasterizer::Settings
truetype_settings(const std::optional<std::string> &hinting, std::optional<double> dpiscale,
                  bool sdf);

// Binds love.font's functions as module functions of <native>::Font, with
// the functions that open the module, and its Rasterizer and GlyphData
// classes as <native>::Rasterizer and <native>::GlyphData. The graphics
// module makes its fonts with the module too (native/graphics.cpp).
void define_font(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_FONT_HPP
