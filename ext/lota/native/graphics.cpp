// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/graphics.hpp"

#include "native/binding.hpp"

#include "common/Color.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Optional.h"
#include "common/math.h"
#include "graphics/Graphics.h"
#include "graphics/Texture.h"
#include "image/ImageData.h"

#include <optional>

namespace lota::native {

using love::graphics::Graphics;
using love::graphics::Texture;

namespace {

constexpr const char *MODULE = "Lota::Graphics";

// The graphics module, on the main thread only (ADR 001, section 6).
Graphics &graphics() {
  require_main_thread(MODULE);
  auto *instance = love::Module::getInstance<Graphics>(love::Module::M_GRAPHICS);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", MODULE);
  }
  return *instance;
}

// luaopen_love_graphics (vendor/love/src/modules/graphics/
// wrap_Graphics.cpp:4231-4250) creates the module with
// Graphics::createInstance, which picks the first renderer that works and
// throws if none does. The module then lives as long as the process, as
// LÖVE's lives until the game quits; opening it again changes nothing.
void open() {
  require_main_thread(MODULE);
  if (love::Module::getInstance<Graphics>(love::Module::M_GRAPHICS) == nullptr) {
    Graphics::createInstance();
  }
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w_newCanvas with no settings table (wrap_Graphics.cpp:873-913): a 2D
// render target, as large as the window unless told otherwise, at the
// screen's DPI scale. Its one reference goes to the Ruby wrapper.
Texture *new_canvas(std::optional<int> width, std::optional<int> height) {
  Graphics &instance = graphics();
  // luax_checkgraphicscreated (wrap_Graphics.cpp:56-61).
  if (!instance.isCreated()) {
    throw love::Exception("%s cannot function without a window.", MODULE);
  }
  Texture::Settings settings;
  settings.width = width.value_or(instance.getWidth());
  settings.height = height.value_or(instance.getHeight());
  // luax_checktexturesettings forces renderTarget (wrap_Graphics.cpp:762-763).
  settings.renderTarget = true;
  settings.dpiScale = static_cast<float>(instance.getScreenDPIScale());
  return instance.newTexture(settings);
}

// w_setCanvas with one 2D texture (wrap_Graphics.cpp:274-378): the texture,
// at its first mipmap, becomes the only render target.
void set_canvas(Texture *texture) {
  Graphics &instance = graphics();
  Graphics::RenderTargets targets;
  targets.colors.emplace_back(texture, 0);
  instance.setRenderTargets(targets);
}

// w_setCanvas with no argument or nil (wrap_Graphics.cpp:276-281): draw to
// the window again.
void reset_canvas() { graphics().setRenderTarget(); }

// w_clear with a color (wrap_Graphics.cpp:117-125 and 144-145): LÖVE reads
// each component as a float, and clears the stencil to 0 and the depth to
// 1.
void clear(double red, double green, double blue, double alpha) {
  const love::ColorD color(static_cast<float>(red), static_cast<float>(green),
                           static_cast<float>(blue), static_cast<float>(alpha));
  graphics().clear(love::graphics::OptionalColorD(color), love::OptionalInt(0),
                   love::OptionalDouble(1.0));
}

// w_readbackTexture of a whole 2D texture (wrap_Graphics.cpp:2411-2449):
// slice 0, mipmap 0, every pixel, into a new ImageData whose one reference
// goes to the Ruby wrapper.
love::image::ImageData *readback_texture(Texture *texture) {
  Graphics &instance = graphics();
  const int mipmap = 0;
  const love::Rect rect = {
      .x = 0,
      .y = 0,
      .w = texture->getPixelWidth(mipmap),
      .h = texture->getPixelHeight(mipmap),
  };
  return instance.readbackTexture(texture, 0, mipmap, rect, nullptr, 0, 0);
}

// w_Texture_isCanvas (wrap_Texture.cpp:282-287): whether the texture was
// made as a render target, as w_newCanvas makes every texture it returns.
// A Texture belongs to love.graphics, so it answers only on the main
// thread, as the module does.
bool is_canvas(const Texture &texture) {
  require_main_thread(MODULE);
  return texture.isRenderTarget();
}

// SPDX-SnippetEnd

} // namespace

void define_graphics(const Rice::Module &native) {
  Rice::define_class_under<Texture>(native, "Texture").define_method("canvas?", &is_canvas);

  Rice::define_module_under(native, "Graphics")
      .define_singleton_function("open", &open)
      .define_singleton_function("new_canvas", &new_canvas, Rice::Arg("width"), Rice::Arg("height"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("set_canvas", &set_canvas, Rice::Arg("texture"))
      .define_singleton_function("reset_canvas", &reset_canvas)
      .define_singleton_function("clear", &clear, Rice::Arg("red"), Rice::Arg("green"),
                                 Rice::Arg("blue"), Rice::Arg("alpha"))
      .define_singleton_function("readback_texture", &readback_texture, Rice::Arg("texture"),
                                 Rice::Return().takeOwnership());
}

} // namespace lota::native
