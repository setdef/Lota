// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/font.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/int.h"
#include "filesystem/FileData.h"
#include "font/BMFontRasterizer.h"
#include "font/Font.h"
#include "font/GlyphData.h"
#include "font/ImageRasterizer.h"
#include "font/Rasterizer.h"
#include "font/TrueTypeRasterizer.h"
#include "font/freetype/Font.h"
#include "image/ImageData.h"

#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::font::GlyphData;
using love::font::Rasterizer;
using love::font::TrueTypeRasterizer;

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from the wrap functions cited below (vendor/love/src/modules/
// font), with each read of the Lua stack made a parameter, which
// Lota::Font reads from Ruby's arguments as LÖVE reads them from Lua's.

TrueTypeRasterizer::Settings truetype_settings(const std::optional<std::string> &hinting,
                                               std::optional<double> dpiscale, bool sdf) {
  TrueTypeRasterizer::Settings settings;
  if (hinting.has_value() && !TrueTypeRasterizer::getConstant(hinting->c_str(), settings.hinting)) {
    raise_enum_error("TrueType font hinting mode",
                     TrueTypeRasterizer::getConstants(settings.hinting), *hinting);
  }
  if (dpiscale.has_value()) {
    settings.dpiScale.set(static_cast<float>(dpiscale.value()));
  }
  settings.sdf = sdf;
  return settings;
}

namespace {

// luaopen_love_font (wrap_Font.cpp:261-279) creates the FreeType font
// module once; it then lives as long as the process, as LÖVE's lives until
// the game quits. The graphics module rasterizes its default font, and
// every font made from a file, with it (graphics/Graphics.cpp:336-344).
void open() { open_module<love::font::Font, love::font::freetype::Font>(love::Module::M_FONT); }

// Whether the module is open, as boot.lua asks with "if love.font".
bool is_open() {
  return love::Module::getInstance<love::font::Font>(love::Module::M_FONT) != nullptr;
}

// The module, as LÖVE's instance() macro reaches it (wrap_Font.cpp:36),
// on any thread.
love::font::Font *instance() {
  auto *module = love::Module::getInstance<love::font::Font>(love::Module::M_FONT);
  if (module == nullptr) {
    throw love::Exception("Lota::Font is not open.");
  }
  return module;
}

// w_newRasterizer with one argument that is not a number (wrap_Font.cpp:
// 45-59): a TrueType font at 12 pixels, or a BMFont definition, as +data+
// holds.
Rasterizer *new_rasterizer(love::filesystem::FileData *data) {
  return instance()->newRasterizer(data);
}

// w_newTrueTypeRasterizer with a size or nothing (wrap_Font.cpp:110-121):
// LÖVE's default font, 13 pixels tall unless told otherwise.
Rasterizer *new_default_truetype_rasterizer(std::optional<int> size,
                                            const std::optional<std::string> &hinting,
                                            std::optional<double> dpiscale, bool sdf) {
  constexpr int default_size = 13;
  const TrueTypeRasterizer::Settings settings = truetype_settings(hinting, dpiscale, sdf);
  return instance()->newTrueTypeRasterizer(size.value_or(default_size), settings);
}

// w_newTrueTypeRasterizer with data (wrap_Font.cpp:122-145): the TrueType
// font in +data+, 12 pixels tall unless told otherwise.
Rasterizer *new_truetype_rasterizer(love::Data *data, std::optional<int> size,
                                    const std::optional<std::string> &hinting,
                                    std::optional<double> dpiscale, bool sdf) {
  constexpr int default_size = 12;
  const TrueTypeRasterizer::Settings settings = truetype_settings(hinting, dpiscale, sdf);
  return instance()->newTrueTypeRasterizer(data, size.value_or(default_size), settings);
}

// w_newBMFontRasterizer (wrap_Font.cpp:158-196): the BMFont definition in
// +definition+ and the pages it names, in order, from +images+, at
// +dpiscale+, 1 unless told otherwise. A page left out is loaded from the
// definition's folder.
Rasterizer *new_bmfont_rasterizer(love::filesystem::FileData *definition, Rice::Array images,
                                  std::optional<double> dpiscale) {
  const Rice::Array pages = std::move(images);
  std::vector<love::image::ImageData *> list;
  for (const auto page : pages) {
    list.push_back(Rice::detail::From_Ruby<love::image::ImageData *>().convert(page.value()));
  }
  return instance()->newBMFontRasterizer(definition, list,
                                         static_cast<float>(dpiscale.value_or(1.0)));
}

// w_newImageRasterizer (wrap_Font.cpp:198-215): the glyphs in +glyphs+ in
// the order the image +data+ draws them, spaced +extraspacing+ pixels
// further apart than it draws them, at +dpiscale+.
Rasterizer *new_image_rasterizer(love::image::ImageData *data, const std::string &glyphs,
                                 std::optional<int> extraspacing, std::optional<double> dpiscale) {
  return instance()->newImageRasterizer(data, glyphs, extraspacing.value_or(0),
                                        static_cast<float>(dpiscale.value_or(1.0)));
}

// w_newGlyphData with a string (wrap_Font.cpp:217-237): the glyph of
// +glyph+'s first character.
GlyphData *new_glyph_data_of_text(Rasterizer *rasterizer, const std::string &glyph) {
  return instance()->newGlyphData(rasterizer, glyph);
}

// w_newGlyphData with a number: the glyph of the code point +glyph+, cast
// to an unsigned 32-bit integer as LÖVE casts it.
GlyphData *new_glyph_data(Rasterizer *rasterizer, double glyph) {
  return instance()->newGlyphData(rasterizer, static_cast<love::uint32>(glyph));
}

// w_Rasterizer_getGlyphData with a string (wrap_Rasterizer.cpp:70-92):
// the glyph of +glyph+'s first character.
GlyphData *rasterizer_glyph_data_of_text(const Rasterizer &rasterizer, const std::string &glyph) {
  return rasterizer.getGlyphData(glyph);
}

// w_Rasterizer_getGlyphData with a number: the glyph of the code point
// +glyph+.
GlyphData *rasterizer_glyph_data(const Rasterizer &rasterizer, double glyph) {
  return rasterizer.getGlyphData(static_cast<love::uint32>(glyph));
}

// w_Rasterizer_hasGlyphs with a string (wrap_Rasterizer.cpp:101-125):
// whether the rasterizer has every glyph of +text+.
bool rasterizer_has_text_glyphs(const Rasterizer &rasterizer, const std::string &text) {
  return rasterizer.hasGlyphs(text);
}

// w_Rasterizer_hasGlyphs with a number: whether the rasterizer has the
// glyph of one code point.
bool rasterizer_has_glyph(const Rasterizer &rasterizer, double glyph) {
  return rasterizer.hasGlyph(static_cast<love::uint32>(glyph));
}

} // namespace

// SPDX-SnippetEnd

namespace {

// Whether +rasterizer+ is of the C++ class Kind, the class the factory
// rule 25 of doc/contributors/design/translation.md names a module for makes:
// love.font.newTrueTypeRasterizer a TrueTypeRasterizer
// (font/freetype/Font.cpp:59-67), newBMFontRasterizer a BMFontRasterizer, and
// newImageRasterizer an ImageRasterizer (font/Font.cpp:53-78), so that the
// module's === matches what its factory makes.
template <typename Kind> bool rasterizer_is(const Rasterizer &rasterizer) {
  return dynamic_cast<const Kind *>(&rasterizer) != nullptr;
}

} // namespace

void define_font(const Rice::Module &native) {
  Rice::define_module_under(native, "Font")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_rasterizer", &new_rasterizer, Rice::Arg("data"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_default_truetype_rasterizer",
                                 &new_default_truetype_rasterizer, Rice::Arg("size"),
                                 Rice::Arg("hinting"), Rice::Arg("dpiscale"), Rice::Arg("sdf"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_truetype_rasterizer", &new_truetype_rasterizer,
                                 Rice::Arg("data"), Rice::Arg("size"), Rice::Arg("hinting"),
                                 Rice::Arg("dpiscale"), Rice::Arg("sdf"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_bmfont_rasterizer", &new_bmfont_rasterizer,
                                 Rice::Arg("definition"), Rice::Arg("images"),
                                 Rice::Arg("dpiscale"), Rice::Return().takeOwnership())
      .define_singleton_function("new_image_rasterizer", &new_image_rasterizer, Rice::Arg("data"),
                                 Rice::Arg("glyphs"), Rice::Arg("extraspacing"),
                                 Rice::Arg("dpiscale"), Rice::Return().takeOwnership())
      .define_singleton_function("new_glyph_data_of_text", &new_glyph_data_of_text,
                                 Rice::Arg("rasterizer"), Rice::Arg("glyph"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_glyph_data", &new_glyph_data, Rice::Arg("rasterizer"),
                                 Rice::Arg("glyph"), Rice::Return().takeOwnership());
  // Rasterizer's and GlyphData's other methods are generated.
  define_engine_class<Rasterizer>(native, "Rasterizer")
      .define_method("glyph_data_of_text", &rasterizer_glyph_data_of_text, Rice::Arg("glyph"),
                     Rice::Return().takeOwnership())
      .define_method("glyph_data", &rasterizer_glyph_data, Rice::Arg("glyph"),
                     Rice::Return().takeOwnership())
      .define_method("text_glyphs?", &rasterizer_has_text_glyphs, Rice::Arg("text"))
      .define_method("glyph?", &rasterizer_has_glyph, Rice::Arg("glyph"))
      .define_method("truetype?", &rasterizer_is<TrueTypeRasterizer>)
      .define_method("bmfont?", &rasterizer_is<love::font::BMFontRasterizer>)
      .define_method("image?", &rasterizer_is<love::font::ImageRasterizer>);
  define_engine_class<GlyphData, love::Data>(native, "GlyphData");
}

} // namespace lota::native
