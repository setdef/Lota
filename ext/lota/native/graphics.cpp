// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/graphics.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Color.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Optional.h"
#include "common/math.h"
#include "graphics/Graphics.h"
#include "graphics/Texture.h"
#include "image/ImageData.h"

#include <exception>
#include <memory>
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

// The first error a screenshot callback raised during the present under
// way, which present raises once LÖVE's present has returned.
std::exception_ptr &screenshot_error() {
  static std::exception_ptr error;
  return error;
}

// A Ruby callable waiting for the next presented frame. The Pin keeps it
// from Ruby's garbage collector until then.
struct PendingScreenshot {
  Rice::Pin callable;
};

// A screenshot callback (graphics/Graphics.h:338-345), after
// screenshotFunctionCallback (wrap_Graphics.cpp:441-461): it calls the
// callable with the frame, or forgets it when there is no frame, which is
// how LÖVE cancels a capture. LÖVE releases the frame after the callback
// returns (metal/Graphics.mm:1780-1781), so the wrapper Ruby gets retains
// its own reference. An error the callable raises waits for present to
// raise it, rather than unwinding through LÖVE's present, which would leave
// the frame and the remaining captures unreleased.
void deliver_screenshot(const Graphics::ScreenshotInfo *info, love::image::ImageData *image,
                        void * /*data*/) {
  if (info == nullptr) {
    return;
  }
  const std::unique_ptr<PendingScreenshot> pending(static_cast<PendingScreenshot *>(info->data));
  if (image == nullptr) {
    return;
  }
  try {
    Rice::Object(pending->callable.value()).call("call", image);
  } catch (...) {
    if (!screenshot_error()) {
      screenshot_error() = std::current_exception();
    }
  }
}

// w_captureScreenshot with a function (wrap_Graphics.cpp:508-518 and
// 552-555): the next present calls +callable+ with the frame it shows, as
// an ImageData. Only the parity harness uses it so far, and Lota::Graphics
// does not translate it yet. The callable arrives by value, as Rice
// converts it, and is moved, as set_renderers moves its Array.
void capture_screenshot(Rice::Object callable) {
  Graphics &instance = graphics();
  const Rice::Object held = std::move(callable);
  Graphics::ScreenshotInfo info;
  info.data =
      std::make_unique<PendingScreenshot>(PendingScreenshot{Rice::Pin(held.value())}).release();
  info.callback = &deliver_screenshot;
  try {
    instance.captureScreenshot(info);
  } catch (...) {
    info.callback(&info, nullptr, nullptr);
    throw;
  }
}

// w_present (wrap_Graphics.cpp:177-181). LÖVE passes its lua_State, which
// its screenshot callbacks call back into; deliver_screenshot needs
// nothing from it.
void present() {
  graphics().present(nullptr);
  if (const std::exception_ptr error = std::exchange(screenshot_error(), nullptr)) {
    std::rethrow_exception(error);
  }
}

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

// w_setColor with three or four numbers (wrap_Graphics.cpp:2491-2515):
// LÖVE reads each as a float; the renderer clamps them to 0 through 1
// (metal/Graphics.mm:1810-1818).
void set_color(double red, double green, double blue, double alpha) {
  graphics().setColor(love::Colorf(static_cast<float>(red), static_cast<float>(green),
                                   static_cast<float>(blue), static_cast<float>(alpha)));
}

// w_getColor (wrap_Graphics.cpp:2517-2525): red, green, blue, and alpha,
// each widened from float as Lua's numbers are.
Rice::Array color() {
  const love::Colorf color = graphics().getColor();
  Rice::Array components;
  components.push(static_cast<double>(color.r), false);
  components.push(static_cast<double>(color.g), false);
  components.push(static_cast<double>(color.b), false);
  components.push(static_cast<double>(color.a), false);
  return components;
}

// w_setLineWidth and w_getLineWidth (wrap_Graphics.cpp:2816-2821 and
// 2845-2849): the width is a float, 1 until set.
void set_line_width(double width) { graphics().setLineWidth(static_cast<float>(width)); }

double line_width() { return static_cast<double>(graphics().getLineWidth()); }

// w_setLineStyle and w_getLineStyle (wrap_Graphics.cpp:2823-2832 and
// 2851-2859): the style is checked before the module, and its name comes
// back as LÖVE spells it.
void set_line_style(const std::string &name) {
  Graphics::LineStyle style = Graphics::LINE_MAX_ENUM;
  if (!Graphics::getConstant(name.c_str(), style)) {
    raise_enum_error("line style", Graphics::getConstants(style), name);
  }
  graphics().setLineStyle(style);
}

std::string line_style() {
  const char *name = nullptr;
  if (!Graphics::getConstant(graphics().getLineStyle(), name)) {
    throw love::Exception("Unknown line style");
  }
  return name;
}

// The draw mode named +name+, as w_rectangle and w_circle read their first
// argument (wrap_Graphics.cpp:3630-3633 and 3662-3665).
Graphics::DrawMode draw_mode(const std::string &name) {
  Graphics::DrawMode mode = Graphics::DRAW_MAX_ENUM;
  if (!Graphics::getConstant(name.c_str(), mode)) {
    raise_enum_error("draw mode", Graphics::getConstants(mode), name);
  }
  return mode;
}

// w_rectangle without rounded corners (wrap_Graphics.cpp:3628-3644): the
// mode is checked before the module, and each number is read as a float.
void rectangle(const std::string &mode, double x, double y, double width, double height) {
  const Graphics::DrawMode drawmode = draw_mode(mode);
  graphics().rectangle(drawmode, static_cast<float>(x), static_cast<float>(y),
                       static_cast<float>(width), static_cast<float>(height));
}

// w_circle (wrap_Graphics.cpp:3660-3680): with no count of segments, the
// renderer picks one from the radius and the current scale.
void circle(const std::string &mode, double x, double y, double radius,
            std::optional<int> segments) {
  const Graphics::DrawMode drawmode = draw_mode(mode);
  Graphics &instance = graphics();
  if (segments.has_value()) {
    instance.circle(drawmode, static_cast<float>(x), static_cast<float>(y),
                    static_cast<float>(radius), segments.value());
  } else {
    instance.circle(drawmode, static_cast<float>(x), static_cast<float>(y),
                    static_cast<float>(radius));
  }
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
                                 Rice::Return().takeOwnership())
      .define_singleton_function("set_color", &set_color, Rice::Arg("red"), Rice::Arg("green"),
                                 Rice::Arg("blue"), Rice::Arg("alpha"))
      .define_singleton_function("color", &color)
      .define_singleton_function("set_line_width", &set_line_width, Rice::Arg("width"))
      .define_singleton_function("line_width", &line_width)
      .define_singleton_function("set_line_style", &set_line_style, Rice::Arg("name"))
      .define_singleton_function("line_style", &line_style)
      .define_singleton_function("rectangle", &rectangle, Rice::Arg("mode"), Rice::Arg("x"),
                                 Rice::Arg("y"), Rice::Arg("width"), Rice::Arg("height"))
      .define_singleton_function("circle", &circle, Rice::Arg("mode"), Rice::Arg("x"),
                                 Rice::Arg("y"), Rice::Arg("radius"),
                                 Rice::Arg("segments") = std::optional<int>())
      .define_singleton_function("capture_screenshot", &capture_screenshot, Rice::Arg("callable"));
}

} // namespace lota::native
