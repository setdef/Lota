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
#include <string>
#include <utility>
#include <vector>

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

// Whether the module is open, as boot.lua and callbacks.lua ask with
// "if love.graphics".
bool is_open() {
  require_main_thread(MODULE);
  return love::Module::getInstance<Graphics>(love::Module::M_GRAPHICS) != nullptr;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w__setGammaCorrect, w__setLowPowerPreferred, w__getDefaultRenderers, and
// w__setRenderers (vendor/love/src/modules/love/love.cpp:354-437), which
// boot.lua calls before the module opens. Renderers go by their names in
// graphics/Graphics.cpp:3021-3027; setRenderers skips a name it does not
// know, as w__setRenderers does.
void set_gamma_correct(bool gamma_correct) {
  require_main_thread(MODULE);
  love::graphics::setGammaCorrect(gamma_correct);
}

void set_low_power_preferred(bool preferred) {
  require_main_thread(MODULE);
  love::graphics::setLowPowerPreferred(preferred);
}

Rice::Array default_renderers() {
  require_main_thread(MODULE);
  Rice::Array names;
  for (const love::graphics::Renderer renderer : love::graphics::getDefaultRenderers()) {
    const char *name = nullptr;
    if (love::graphics::getConstant(renderer, name)) {
      names.push(std::string(name), false);
    }
  }
  return names;
}

// The names arrive as a Ruby Array of Strings: a std::vector parameter
// would make Rice define a Ruby class for it, and Rice converts an Array
// only by value, which this function then owns.
void set_renderers(Rice::Array names) {
  require_main_thread(MODULE);
  const Rice::Array list = std::move(names);
  std::vector<love::graphics::Renderer> renderers;
  for (const auto item : list) {
    const std::string name = Rice::String(item.value()).str();
    love::graphics::Renderer renderer = love::graphics::RENDERER_NONE;
    if (love::graphics::getConstant(name.c_str(), renderer)) {
      renderers.push_back(renderer);
    }
  }
  love::graphics::setRenderers(renderers);
}

// w_isActive (wrap_Graphics.cpp:189-193): whether there is a window, a
// context, and the module is active (Graphics.cpp:814-820).
bool is_active() { return graphics().isActive(); }

// w_origin (wrap_Graphics.cpp:3965-3969).
void origin() { graphics().origin(); }

// w_getBackgroundColor (wrap_Graphics.cpp:2553-2561): red, green, blue,
// and alpha, each widened from float as Lua's numbers are.
Rice::Array background_color() {
  const love::Colorf color = graphics().getBackgroundColor();
  Rice::Array components;
  components.push(static_cast<double>(color.r), false);
  components.push(static_cast<double>(color.g), false);
  components.push(static_cast<double>(color.b), false);
  components.push(static_cast<double>(color.a), false);
  return components;
}

// w_present (wrap_Graphics.cpp:177-181). Lota takes no screenshots yet,
// so no screenshot callback waits for the frame.
void present() { graphics().present(nullptr); }

// w_getWidth and w_getHeight (wrap_Graphics.cpp:207-217): the size of the
// window in units of its DPI scale.
int width() { return graphics().getWidth(); }

int height() { return graphics().getHeight(); }

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
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("set_gamma_correct", &set_gamma_correct,
                                 Rice::Arg("gamma_correct"))
      .define_singleton_function("set_low_power_preferred", &set_low_power_preferred,
                                 Rice::Arg("preferred"))
      .define_singleton_function("default_renderers", &default_renderers)
      .define_singleton_function("set_renderers", &set_renderers, Rice::Arg("names"))
      .define_singleton_function("active?", &is_active)
      .define_singleton_function("origin", &origin)
      .define_singleton_function("background_color", &background_color)
      .define_singleton_function("present", &present)
      .define_singleton_function("width", &width)
      .define_singleton_function("height", &height)
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
