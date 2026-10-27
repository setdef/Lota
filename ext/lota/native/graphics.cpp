// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/graphics.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Color.h"
#include "common/Data.h"
#include "common/Exception.h"
#include "common/Matrix.h"
#include "common/Module.h"
#include "common/Optional.h"
#include "common/Vector.h"
#include "common/math.h"
#include "filesystem/FileData.h"
#include "font/Font.h"
#include "font/Rasterizer.h"
#include "font/TextShaper.h"
#include "font/TrueTypeRasterizer.h"
#include "graphics/Font.h"
#include "graphics/Graphics.h"
#include "graphics/Quad.h"
#include "graphics/SpriteBatch.h"
#include "graphics/Texture.h"
#include "graphics/vertex.h"
#include "image/CompressedImageData.h"
#include "image/Image.h"
#include "image/ImageData.h"

#include <array>
#include <cstddef>
#include <cstdlib>
#include <exception>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace lota::native {

using love::graphics::Font;
using love::graphics::Graphics;
using love::graphics::SamplerState;
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

// w_newCanvas with a width and a height (wrap_Graphics.cpp:873-913): a 2D
// render target, as large as the window unless told otherwise, at the
// screen's DPI scale, with +msaa+ antialiasing samples unless it is nil, the
// one setting of luax_checktexturesettings (lines 759-871) Lota binds so
// far, which Lota::Graphics::Canvas.new reads as luax_intflag does;
// otherwise Texture::Settings' one sample (graphics/Texture.h:186-203). It
// arrives as a Ruby object, as an entry of LÖVE's settings table does, by
// value, as Rice converts it, and is moved, as capture_screenshot moves its
// callable. Its one reference goes to the Ruby wrapper.
Texture *new_canvas(std::optional<int> width, std::optional<int> height, Rice::Object msaa) {
  const Rice::Object samples = std::move(msaa);
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
  if (!samples.is_nil()) {
    settings.msaa = Rice::detail::From_Ruby<int>().convert(samples.value());
  }
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

// luax_checkgraphicscreated (wrap_Graphics.cpp:56-61): the module, once
// it has a window to draw in.
Graphics &created_graphics() {
  Graphics &instance = graphics();
  if (!instance.isCreated()) {
    throw love::Exception("%s cannot function without a window.", MODULE);
  }
  return instance;
}

// parseDPIScale (wrap_Graphics.cpp:692-712): a file named like
// "image@2x.png" holds pixels at twice the density, so the texture made
// from it takes a DPI scale of 2. Data that is not a file has no name to
// parse.
void parse_dpi_scale(love::Data *data, float &dpiscale) {
  const auto *file = dynamic_cast<love::filesystem::FileData *>(data);
  if (file == nullptr) {
    return;
  }
  const std::string &fname = file->getName();
  const std::size_t namelen = fname.length();
  const std::size_t atpos = fname.rfind('@');
  if (atpos != std::string::npos && atpos + 2 < namelen &&
      (fname.back() == 'x' || fname.back() == 'X')) {
    char *end = nullptr;
    constexpr int base = 10;
    const long density = std::strtol(&fname.at(atpos + 1), &end, base);
    if (end != nullptr && density > 0) {
      dpiscale = static_cast<float>(density);
    }
  }
}

// w_newTexture of one 2D image (wrap_Graphics.cpp:916-975), its pixels
// from +data+ as getImageData decodes them (lines 714-745): compressed
// formats the image module recognizes stay compressed, and everything else
// is decoded to an ImageData. Of luax_checktexturesettings's settings
// (lines 759-871), Lota binds the canvas setting so far, which makes the
// texture one you can draw into (lines 770-771). The texture's one
// reference goes to the Ruby wrapper.
Texture *new_texture_from_data(love::Data *data, bool canvas) {
  Graphics &instance = created_graphics();
  auto *imagemodule = love::Module::getInstance<love::image::Image>(love::Module::M_IMAGE);
  if (imagemodule == nullptr) {
    throw love::Exception("Cannot load images without the love.image module.");
  }
  Texture::Settings settings;
  settings.type = love::graphics::TEXTURE_2D;
  settings.renderTarget = canvas;
  parse_dpi_scale(data, settings.dpiScale);
  Texture::Slices slices(love::graphics::TEXTURE_2D);
  if (imagemodule->isCompressed(data)) {
    const love::StrongRef<love::image::CompressedImageData> cdata(
        imagemodule->newCompressedData(data), love::Acquire::NORETAIN);
    slices.add(cdata.get(), 0, 0, false, settings.mipmaps != Texture::MIPMAPS_NONE);
  } else {
    const love::StrongRef<love::image::ImageData> idata(imagemodule->newImageData(data),
                                                        love::Acquire::NORETAIN);
    slices.set(0, 0, idata.get());
  }
  return instance.newTexture(settings, &slices);
}

// w_newTexture of an ImageData (wrap_Graphics.cpp:916-975 and 714-722):
// the texture takes the ImageData's pixels as they are, at a DPI scale of
// 1, with the canvas setting as new_texture_from_data takes it.
Texture *new_texture_from_image_data(love::image::ImageData *data, bool canvas) {
  Graphics &instance = created_graphics();
  Texture::Settings settings;
  settings.type = love::graphics::TEXTURE_2D;
  settings.renderTarget = canvas;
  Texture::Slices slices(love::graphics::TEXTURE_2D);
  slices.set(0, 0, data);
  return instance.newTexture(settings, &slices);
}

// The font module, which rasterizes the glyphs of every font the graphics
// module makes, with Graphics::newDefaultFont's message when it is not
// open (Graphics.cpp:338-340).
love::font::Font &font_module() {
  auto *instance = love::Module::getInstance<love::font::Font>(love::Module::M_FONT);
  if (instance == nullptr) {
    throw love::Exception("Font module has not been loaded.");
  }
  return *instance;
}

// luax_checktruetypesettings (wrap_Font.cpp:67-104): the hinting mode by
// name, the DPI scale when given, and whether glyphs are signed distance
// fields.
love::font::TrueTypeRasterizer::Settings
truetype_settings(const std::optional<std::string> &hinting, std::optional<double> dpiscale,
                  bool sdf) {
  love::font::TrueTypeRasterizer::Settings settings;
  if (hinting.has_value() &&
      !love::font::TrueTypeRasterizer::getConstant(hinting->c_str(), settings.hinting)) {
    raise_enum_error("TrueType font hinting mode",
                     love::font::TrueTypeRasterizer::getConstants(settings.hinting), *hinting);
  }
  if (dpiscale.has_value()) {
    settings.dpiScale.set(static_cast<float>(dpiscale.value()));
  }
  settings.sdf = sdf;
  return settings;
}

// w_newFont (wrap_Graphics.cpp:1382-1408) of the Rasterizer +rasterizer+,
// which the font takes its own reference to; the font's one reference goes
// to the Ruby wrapper.
Font *new_font(Graphics &instance, love::font::Rasterizer *made) {
  const love::StrongRef<love::font::Rasterizer> rasterizer(made, love::Acquire::NORETAIN);
  return instance.newFont(rasterizer.get());
}

// w_newFont with a size or nothing, through w_newTrueTypeRasterizer
// (wrap_Font.cpp:106-121): LÖVE's default font, 13 pixels tall unless
// told otherwise.
Font *new_default_font(std::optional<int> size, const std::optional<std::string> &hinting,
                       std::optional<double> dpiscale, bool sdf) {
  Graphics &instance = created_graphics();
  const love::font::TrueTypeRasterizer::Settings settings =
      truetype_settings(hinting, dpiscale, sdf);
  constexpr int default_size = 13;
  return new_font(instance,
                  font_module().newTrueTypeRasterizer(size.value_or(default_size), settings));
}

// w_newFont with data and a size, through w_newTrueTypeRasterizer
// (wrap_Font.cpp:122-145): the TrueType font in +data+.
Font *new_truetype_font(love::Data *data, int size, const std::optional<std::string> &hinting,
                        std::optional<double> dpiscale, bool sdf) {
  Graphics &instance = created_graphics();
  const love::font::TrueTypeRasterizer::Settings settings =
      truetype_settings(hinting, dpiscale, sdf);
  return new_font(instance, font_module().newTrueTypeRasterizer(data, size, settings));
}

// w_newFont with a file's data alone, through w_newRasterizer
// (wrap_Font.cpp:45-59): Font::newRasterizer reads a TrueType font at 12
// pixels, or a BMFont definition, as the data holds.
Font *new_font_from_file(love::filesystem::FileData *data) {
  Graphics &instance = created_graphics();
  return new_font(instance, font_module().newRasterizer(data));
}

// w_getFont (wrap_Graphics.cpp:2580-2589): the font text is drawn in,
// which is LÖVE's default font, made on first use, until one is set.
Font *font() { return created_graphics().getFont(); }

// A Ruby number, read as a float, as luaL_checknumber and LÖVE's casts
// read each number of a color or a placement.
float to_float(const Rice::Object &number) {
  return static_cast<float>(Rice::detail::From_Ruby<double>().convert(number.value()));
}

// The elements of +array+.
std::vector<Rice::Object> elements(const Rice::Array &array) {
  std::vector<Rice::Object> values;
  for (const auto item : array) {
    values.emplace_back(item.value());
  }
  return values;
}

// luax_checkcoloredstring (wrap_Font.cpp:33-76), from what Lota::Graphics
// passes: an Array of Arrays, each a string and the red, green, blue, and
// alpha it is drawn in.
std::vector<love::font::ColoredString> colored_strings(const Rice::Array &text) {
  std::vector<love::font::ColoredString> strings;
  for (const auto item : text) {
    const std::vector<Rice::Object> part = elements(Rice::Array(item.value()));
    love::font::ColoredString colored;
    colored.str = Rice::String(part.at(0).value()).str();
    colored.color = love::Colorf(to_float(part.at(1)), to_float(part.at(2)), to_float(part.at(3)),
                                 to_float(part.at(4)));
    strings.push_back(colored);
  }
  return strings;
}

// The placement LÖVE builds from a position, an angle, scale factors,
// origin offsets, and shearing factors, each read as a float
// (luax_checkstandardtransform, wrap_SpriteBatch.h:33-64, and w_printf),
// from an Array of those nine numbers in that order.
love::Matrix4 placement_of(const Rice::Array &numbers) {
  constexpr std::size_t count = 9;
  const std::vector<Rice::Object> given = elements(numbers);
  std::array<float, count> values{};
  for (std::size_t index = 0; index < count; index++) {
    values.at(index) = to_float(given.at(index));
  }
  return std::apply([](auto... value) { return love::Matrix4(value...); }, values);
}

// w_print with numbers (wrap_Graphics.cpp:3410-3433): +text+ in the
// current font, from the top left of its first line.
void print(Rice::Array text, Rice::Array placement) {
  const Rice::Array parts = std::move(text);
  const Rice::Array numbers = std::move(placement);
  const std::vector<love::font::ColoredString> strings = colored_strings(parts);
  graphics().print(strings, placement_of(numbers));
}

// w_printf with numbers (wrap_Graphics.cpp:3435-3492): +text+ in the
// current font, wrapped at +limit+ and aligned within it. The alignment is
// checked after the numbers, and before the module.
void printf(Rice::Array text, Rice::Array placement, double limit,
            const std::optional<std::string> &align) {
  const Rice::Array parts = std::move(text);
  const Rice::Array numbers = std::move(placement);
  const std::vector<love::font::ColoredString> strings = colored_strings(parts);
  const love::Matrix4 matrix = placement_of(numbers);
  Font::AlignMode mode = Font::ALIGN_LEFT;
  if (align.has_value() && !Font::getConstant(align->c_str(), mode)) {
    raise_enum_error("alignment", Font::getConstants(mode), *align);
  }
  graphics().printf(strings, static_cast<float>(limit), mode, matrix);
}

// w_draw of a Drawable with numbers (wrap_Graphics.cpp:3245-3279): the
// drawable, placed by luax_checkstandardtransform's nine numbers. Lota
// draws textures so far, which are LÖVE's Drawables.
void draw(Texture *texture, Rice::Array placement) {
  const Rice::Array numbers = std::move(placement);
  graphics().draw(texture, placement_of(numbers));
}

// w_draw of a SpriteBatch with numbers (wrap_Graphics.cpp:3245-3279):
// every sprite in the batch, placed together by the nine numbers.
void draw_sprite_batch(love::graphics::SpriteBatch *batch, Rice::Array placement) {
  const Rice::Array numbers = std::move(placement);
  graphics().draw(batch, placement_of(numbers));
}

// w_draw of a Texture through a Quad (wrap_Graphics.cpp:3245-3279): the
// part of +texture+ the quad shows, placed by the nine numbers.
void draw_quad(Texture *texture, love::graphics::Quad *quad, Rice::Array placement) {
  const Rice::Array numbers = std::move(placement);
  graphics().draw(texture, quad, placement_of(numbers));
}

// The viewport a Quad shows, from an Array of its left edge, top edge,
// width, and height, each read as LÖVE reads them, as doubles
// (wrap_Graphics.cpp:1339-1343 and wrap_Quad.cpp:38-42).
love::graphics::Quad::Viewport viewport_of(const Rice::Array &sides) {
  const std::vector<Rice::Object> given = elements(sides);
  const auto number = [&given](std::size_t index) {
    return Rice::detail::From_Ruby<double>().convert(given.at(index).value());
  };
  love::graphics::Quad::Viewport v{};
  v.x = number(0);
  v.y = number(1);
  v.w = number(2);
  v.h = number(3);
  return v;
}

// w_newQuad (wrap_Graphics.cpp:1335-1380) of the layer of an array
// texture it shows, counting from 1 as Lua does, a viewport, as
// viewport_of reads it, and the size of the texture it is a part of.
// Lota::Graphics::Quad.new reads the size from a texture, or as numbers,
// as w_newQuad chooses between them. Its one reference goes to the Ruby
// wrapper.
love::graphics::Quad *new_quad(int layer, Rice::Array viewport, double sw, double sh) {
  const Rice::Array sides = std::move(viewport);
  Graphics &instance = created_graphics();
  love::graphics::Quad *quad = instance.newQuad(viewport_of(sides), sw, sh);
  quad->setLayer(layer - 1);
  return quad;
}

// w_newQuad's forms that take the size from a texture
// (wrap_Graphics.cpp:1349-1361): its width and height, as w_newQuad reads
// them.
love::graphics::Quad *new_quad_of_texture(int layer, Rice::Array viewport, Texture *texture) {
  created_graphics();
  return new_quad(layer, std::move(viewport), texture->getWidth(), texture->getHeight());
}

// Quad:setViewport (wrap_Quad.cpp:34-54): a viewport, as viewport_of reads
// it, within the same texture, or within a texture of +sw+ by +sh+ when
// they are given.
void quad_set_viewport(love::graphics::Quad &quad, Rice::Array viewport, std::optional<double> sw,
                       std::optional<double> sh) {
  require_main_thread(MODULE);
  const Rice::Array sides = std::move(viewport);
  const love::graphics::Quad::Viewport v = viewport_of(sides);
  if (!sw.has_value()) {
    quad.setViewport(v);
  } else {
    quad.refresh(v, sw.value(), required(sh, "sh"));
  }
}

// Quad:getLayer (wrap_Quad.cpp:85-90), counting from 1 as Lua does.
int quad_layer(const love::graphics::Quad &quad) {
  require_main_thread(MODULE);
  return quad.getLayer() + 1;
}

// w_newSpriteBatch (wrap_Graphics.cpp:1438-1460): a batch of +size+
// sprites, 1000 unless given, drawn from +texture+, with a usage hint,
// dynamic unless given. Its one reference goes to the Ruby wrapper.
love::graphics::SpriteBatch *new_sprite_batch(Texture *texture, std::optional<int> size,
                                              const std::optional<std::string> &usagestr) {
  Graphics &instance = created_graphics();
  love::graphics::BufferDataUsage usage = love::graphics::BUFFERDATAUSAGE_DYNAMIC;
  if (usagestr.has_value() && !love::graphics::getConstant(usagestr->c_str(), usage)) {
    raise_enum_error("usage hint", love::graphics::getConstants(usage), *usagestr);
  }
  constexpr int default_size = 1000;
  return instance.newSpriteBatch(texture, size.value_or(default_size), usage);
}

// w_SpriteBatch_add (wrap_SpriteBatch.cpp:36-56 and 85-93): adds a sprite
// of the whole texture, or of +quad+ unless it is nil, placed by the nine
// numbers, and returns its index, counting from 1 as Lua does.
int sprite_batch_add(love::graphics::SpriteBatch &batch, love::graphics::Quad *quad,
                     Rice::Array placement) {
  require_main_thread(MODULE);
  const Rice::Array numbers = std::move(placement);
  const love::Matrix4 m = placement_of(numbers);
  const int index = (quad != nullptr) ? batch.add(quad, m, -1) : batch.add(m, -1);
  return index + 1;
}

// w_SpriteBatch_set (wrap_SpriteBatch.cpp:36-56 and 95-103): replaces the
// sprite at +index+, counting from 1 as Lua does, as sprite_batch_add adds
// one.
void sprite_batch_set(love::graphics::SpriteBatch &batch, int index, love::graphics::Quad *quad,
                      Rice::Array placement) {
  require_main_thread(MODULE);
  const Rice::Array numbers = std::move(placement);
  const love::Matrix4 m = placement_of(numbers);
  if (quad != nullptr) {
    batch.add(quad, m, index - 1);
  } else {
    batch.add(m, index - 1);
  }
}

// SpriteBatch:setColor with numbers (wrap_SpriteBatch.cpp:154-182), as
// set_color binds love.graphics.setColor.
void sprite_batch_set_color(love::graphics::SpriteBatch &batch, double red, double green,
                            double blue, double alpha) {
  require_main_thread(MODULE);
  batch.setColor(love::Colorf(static_cast<float>(red), static_cast<float>(green),
                              static_cast<float>(blue), static_cast<float>(alpha)));
}

// SpriteBatch:getTexture (wrap_SpriteBatch.cpp:147-152). The batch keeps
// its own reference, and the Ruby wrapper takes another.
Texture *sprite_batch_texture(const love::graphics::SpriteBatch &batch) {
  require_main_thread(MODULE);
  return batch.getTexture();
}

// SpriteBatch:getDrawRange (wrap_SpriteBatch.cpp:249-261): the first
// sprite drawn, counting from 1, and how many, or nil when the batch draws
// every sprite.
Rice::Object sprite_batch_draw_range(const love::graphics::SpriteBatch &batch) {
  require_main_thread(MODULE);
  int start = 0;
  int count = 1;
  if (!batch.getDrawRange(start, count)) {
    return {};
  }
  Rice::Array range;
  range.push(start + 1, false);
  range.push(count, false);
  return range;
}

// w__optMipmap (wrap_Texture.cpp:38-51): the mipmap +mipmap+ names,
// counting from 1 as Lua does, or the first when nil.
int mipmap_of(const Texture &texture, std::optional<int> mipmap) {
  if (!mipmap.has_value()) {
    return 0;
  }
  const int index = *mipmap - 1;
  if (index < 0 || index >= texture.getMipmapCount()) {
    throw love::Exception("Invalid mipmap index: %d", index + 1);
  }
  return index;
}

// Texture:getWidth and getHeight (wrap_Texture.cpp:53-65), of the first
// mipmap or the one given.
int texture_width(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getWidth(mipmap_of(texture, mipmap));
}

int texture_height(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getHeight(mipmap_of(texture, mipmap));
}

// w_line (wrap_Graphics.cpp:3542-3589) with its coordinates in one Array,
// as Lota::Graphics.line passes them however they were given: LÖVE checks
// their count before it reads them, and reads each as a float.
void line(Rice::Array coordinates) {
  const Rice::Array list = std::move(coordinates);
  const std::vector<Rice::Object> given = elements(list);
  const auto args = static_cast<int>(given.size());
  if (args % 2 != 0) {
    throw love::Exception("Number of vertex components must be a multiple of two.");
  }
  if (args < 4) {
    throw love::Exception("Need at least two vertices to draw a line.");
  }
  Graphics &instance = graphics();
  const int numvertices = args / 2;
  const std::span<love::Vector2> coords(instance.getScratchBuffer<love::Vector2>(numvertices),
                                        static_cast<std::size_t>(numvertices));
  std::size_t component = 0;
  for (love::Vector2 &coord : coords) {
    coord.x = to_float(given.at(component));
    coord.y = to_float(given.at(component + 1));
    component += 2;
  }
  instance.polyline(coords.data(), numvertices);
}

// w_arc (wrap_Graphics.cpp:3705-3739): the arc mode is pie unless given,
// and the draw mode is checked before it. Its position, radius, angles,
// and optional count of points arrive in one Array, as Lota::Graphics.arc
// passes what follows the arc mode, and each is read as LÖVE reads it.
void arc(const std::string &drawstr, const std::optional<std::string> &arcstr,
         Rice::Array arguments) {
  const Rice::Array list = std::move(arguments);
  const std::vector<Rice::Object> given = elements(list);
  Graphics::DrawMode drawmode = Graphics::DRAW_LINE;
  if (!Graphics::getConstant(drawstr.c_str(), drawmode)) {
    raise_enum_error("draw mode", Graphics::getConstants(drawmode), drawstr);
  }
  Graphics::ArcMode arcmode = Graphics::ARC_PIE;
  if (arcstr.has_value() && !Graphics::getConstant(arcstr->c_str(), arcmode)) {
    raise_enum_error("arc mode", Graphics::getConstants(arcmode), *arcstr);
  }
  const float x = to_float(given.at(0));
  const float y = to_float(given.at(1));
  const float radius = to_float(given.at(2));
  const float angle1 = to_float(given.at(3));
  const float angle2 = to_float(given.at(4));
  constexpr std::size_t points_index = 5;
  Graphics &instance = graphics();
  if (given.size() <= points_index || given.at(points_index).is_nil()) {
    instance.arc(drawmode, arcmode, x, y, radius, angle1, angle2);
  } else {
    const int points = Rice::detail::From_Ruby<int>().convert(given.at(points_index).value());
    instance.arc(drawmode, arcmode, x, y, radius, angle1, angle2, points);
  }
}

// w_getDefaultFilter (wrap_Graphics.cpp:2769-2782): the two filters'
// names and the anisotropy, which LÖVE holds as an integer.
Rice::Array default_filter() {
  const SamplerState &state = graphics().getDefaultSamplerState();
  const char *min = nullptr;
  const char *mag = nullptr;
  if (!SamplerState::getConstant(state.minFilter, min)) {
    throw love::Exception("Unknown minification filter mode");
  }
  if (!SamplerState::getConstant(state.magFilter, mag)) {
    throw love::Exception("Unknown magnification filter mode");
  }
  Rice::Array filter;
  filter.push(std::string(min), false);
  filter.push(std::string(mag), false);
  filter.push(static_cast<int>(state.maxAnisotropy), false);
  return filter;
}

// SPDX-SnippetEnd

} // namespace

void define_graphics(const Rice::Module &native) {
  // Its methods are generated (ext/lota/native/generated/graphics.cpp).
  define_engine_class<Texture>(native, "Texture")
      .define_method("width", &texture_width, Rice::Arg("mipmap") = std::optional<int>())
      .define_method("height", &texture_height, Rice::Arg("mipmap") = std::optional<int>());
  // Their other methods are generated too.
  define_engine_class<love::graphics::Quad>(native, "Quad")
      .define_method("layer", &quad_layer)
      .define_method("set_viewport", &quad_set_viewport, Rice::Arg("viewport"),
                     Rice::Arg("sw") = std::optional<double>(),
                     Rice::Arg("sh") = std::optional<double>());
  define_engine_class<love::graphics::SpriteBatch>(native, "SpriteBatch")
      .define_method("add", &sprite_batch_add, Rice::Arg("quad"), Rice::Arg("placement"))
      .define_method("set", &sprite_batch_set, Rice::Arg("index"), Rice::Arg("quad"),
                     Rice::Arg("placement"))
      .define_method("set_color", &sprite_batch_set_color, Rice::Arg("red"), Rice::Arg("green"),
                     Rice::Arg("blue"), Rice::Arg("alpha"))
      .define_method("texture", &sprite_batch_texture)
      .define_method("draw_range", &sprite_batch_draw_range);
  // LÖVE's graphics Font is Native::Graphics::Font, since Native::Font is
  // love.font, the module that rasterizes its glyphs (native/font.cpp).
  Rice::Module graphics_module = Rice::define_module_under(native, "Graphics");
  define_engine_class<Font>(graphics_module, "Font");

  graphics_module.define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("set_gamma_correct", &set_gamma_correct,
                                 Rice::Arg("gamma_correct"))
      .define_singleton_function("set_low_power_preferred", &set_low_power_preferred,
                                 Rice::Arg("preferred"))
      .define_singleton_function("default_renderers", &default_renderers)
      .define_singleton_function("set_renderers", &set_renderers, Rice::Arg("names"))
      .define_singleton_function("present", &present)
      .define_singleton_function("new_canvas", &new_canvas, Rice::Arg("width"), Rice::Arg("height"),
                                 Rice::Arg("msaa"), Rice::Return().takeOwnership())
      .define_singleton_function("new_texture_from_data", &new_texture_from_data, Rice::Arg("data"),
                                 Rice::Arg("canvas"), Rice::Return().takeOwnership())
      .define_singleton_function("new_texture_from_image_data", &new_texture_from_image_data,
                                 Rice::Arg("data"), Rice::Arg("canvas"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("set_canvas", &set_canvas, Rice::Arg("texture"))
      .define_singleton_function("reset_canvas", &reset_canvas)
      .define_singleton_function("clear", &clear, Rice::Arg("red"), Rice::Arg("green"),
                                 Rice::Arg("blue"), Rice::Arg("alpha"))
      .define_singleton_function("readback_texture", &readback_texture, Rice::Arg("texture"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("set_color", &set_color, Rice::Arg("red"), Rice::Arg("green"),
                                 Rice::Arg("blue"), Rice::Arg("alpha"))
      .define_singleton_function("capture_screenshot", &capture_screenshot, Rice::Arg("callable"))
      .define_singleton_function("new_default_font", &new_default_font, Rice::Arg("size"),
                                 Rice::Arg("hinting"), Rice::Arg("dpiscale"), Rice::Arg("sdf"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_truetype_font", &new_truetype_font, Rice::Arg("data"),
                                 Rice::Arg("size"), Rice::Arg("hinting"), Rice::Arg("dpiscale"),
                                 Rice::Arg("sdf"), Rice::Return().takeOwnership())
      .define_singleton_function("new_font_from_file", &new_font_from_file, Rice::Arg("data"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("font", &font)
      .define_singleton_function("print", &print, Rice::Arg("text"), Rice::Arg("placement"))
      .define_singleton_function("printf", &printf, Rice::Arg("text"), Rice::Arg("placement"),
                                 Rice::Arg("limit"), Rice::Arg("align"))
      .define_singleton_function("default_filter", &default_filter)
      .define_singleton_function("draw", &draw, Rice::Arg("texture"), Rice::Arg("placement"))
      .define_singleton_function("draw_sprite_batch", &draw_sprite_batch, Rice::Arg("batch"),
                                 Rice::Arg("placement"))
      .define_singleton_function("draw_quad", &draw_quad, Rice::Arg("texture"), Rice::Arg("quad"),
                                 Rice::Arg("placement"))
      .define_singleton_function("new_quad", &new_quad, Rice::Arg("layer"), Rice::Arg("viewport"),
                                 Rice::Arg("sw"), Rice::Arg("sh"), Rice::Return().takeOwnership())
      .define_singleton_function("new_quad_of_texture", &new_quad_of_texture, Rice::Arg("layer"),
                                 Rice::Arg("viewport"), Rice::Arg("texture"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_sprite_batch", &new_sprite_batch, Rice::Arg("texture"),
                                 Rice::Arg("size"), Rice::Arg("usage"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("line", &line, Rice::Arg("coordinates"))
      .define_singleton_function("arc", &arc, Rice::Arg("drawstr"), Rice::Arg("arcstr"),
                                 Rice::Arg("arguments"));
}

} // namespace lota::native
