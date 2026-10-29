// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/graphics.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/math.hpp"

#include "common/Color.h"
#include "common/Data.h"
#include "common/Exception.h"
#include "common/Matrix.h"
#include "common/Module.h"
#include "common/Object.h"
#include "common/Optional.h"
#include "common/Vector.h"
#include "common/int.h"
#include "common/math.h"
#include "common/pixelformat.h"
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
#include "image/FormatHandler.h"
#include "image/Image.h"
#include "image/ImageData.h"
#include "math/Transform.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <cstdlib>
#include <exception>
#include <iostream>
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

// What waits for the next presented frame: a Ruby callable, which the Pin
// keeps from Ruby's garbage collector until then, or, with no callable,
// the name of a file and the format its extension names, as
// ScreenshotFileInfo holds them (wrap_Graphics.cpp:463-467).
struct PendingScreenshot {
  std::optional<Rice::Pin> callable;
  std::string filename;
  love::image::FormatHandler::EncodedFormat format{};
};

// screenshotFileCallback (wrap_Graphics.cpp:469-490): it encodes the frame
// into the save directory, and prints, rather than raises, an error in
// encoding or saving it, as LÖVE does.
void save_screenshot(const PendingScreenshot &pending, const love::image::ImageData &image) {
  try {
    const love::StrongRef<love::filesystem::FileData> saved(
        image.encode(pending.format, pending.filename.c_str(), true), love::Acquire::NORETAIN);
  } catch (const love::Exception &error) {
    std::cout << "Screenshot encoding or saving failed: " << error.what() << std::flush;
  }
}

// A screenshot callback (graphics/Graphics.h:338-345), after
// screenshotFunctionCallback (wrap_Graphics.cpp:441-461): it calls the
// callable with the frame, or saves it to the file, or forgets it when
// there is no frame, which is how LÖVE cancels a capture. LÖVE releases
// the frame after the callback returns (metal/Graphics.mm:1780-1781), so
// the wrapper Ruby gets retains its own reference. An error the callable
// raises waits for present to raise it, rather than unwinding through
// LÖVE's present, which would leave the frame and the remaining captures
// unreleased.
void deliver_screenshot(const Graphics::ScreenshotInfo *info, love::image::ImageData *image,
                        void * /*data*/) {
  if (info == nullptr) {
    return;
  }
  const std::unique_ptr<PendingScreenshot> pending(static_cast<PendingScreenshot *>(info->data));
  if (image == nullptr) {
    return;
  }
  if (!pending->callable) {
    save_screenshot(*pending, *image);
    return;
  }
  try {
    Rice::Object(pending->callable->value()).call("call", image);
  } catch (...) {
    if (!screenshot_error()) {
      screenshot_error() = std::current_exception();
    }
  }
}

// Asks LÖVE for the next presented frame, for +pending+, and forgets it
// when LÖVE refuses, as w_captureScreenshot does (wrap_Graphics.cpp:552-555).
void request_screenshot(std::unique_ptr<PendingScreenshot> pending) {
  Graphics &instance = graphics();
  Graphics::ScreenshotInfo info;
  info.data = pending.release();
  info.callback = &deliver_screenshot;
  try {
    instance.captureScreenshot(info);
  } catch (...) {
    info.callback(&info, nullptr, nullptr);
    throw;
  }
}

// w_captureScreenshot with a function (wrap_Graphics.cpp:508-518): the
// next present calls +callable+ with the frame it shows, as an ImageData.
// The callable arrives by value, as Rice converts it, and is moved, as
// set_renderers moves its Array.
void capture_screenshot(Rice::Object callable) {
  const Rice::Object held = std::move(callable);
  auto pending = std::make_unique<PendingScreenshot>();
  pending->callable.emplace(held.value());
  request_screenshot(std::move(pending));
}

// w_captureScreenshot with a filename (wrap_Graphics.cpp:519-540): the
// next present saves the frame it shows in the format the extension
// names, which LÖVE checks first, ignoring its case.
void capture_screenshot_to_file(const std::string &filename) {
  std::string ext;
  const std::size_t dotpos = filename.rfind('.');
  if (dotpos != std::string::npos) {
    ext = filename.substr(dotpos + 1);
  }
  std::ranges::transform(ext, ext.begin(),
                         [](unsigned char letter) { return std::tolower(letter); });
  love::image::FormatHandler::EncodedFormat format{};
  if (!love::image::ImageData::getConstant(ext.c_str(), format)) {
    raise_enum_error("encoded image format", love::image::ImageData::getConstants(format), ext);
  }
  auto pending = std::make_unique<PendingScreenshot>();
  pending->filename = filename;
  pending->format = format;
  request_screenshot(std::move(pending));
}

// Sets the field +name+ of a record's Hash to +value+, as lua_setfield
// sets a table's.
template <typename T> void set_field(Rice::Hash &fields, const char *name, T value) {
  fields.call("[]=", Rice::String(name), value);
}

// Sets a field of +fields+ for each of +values+, by the name LÖVE gives
// its index, skipping an index with no name, as LÖVE's loops over an enum
// do.
template <typename Enum, typename T, std::size_t N>
void set_fields(Rice::Hash &fields, const std::span<const T, N> values,
                bool (*name_of)(Enum, const char *&)) {
  int index = 0;
  for (const T value : values) {
    const char *name = nullptr;
    if (name_of(static_cast<Enum>(index++), name)) {
      set_field(fields, name, value);
    }
  }
}

// w_getStats (wrap_Graphics.cpp:3206-3243): the renderer's counts since
// the last present, by LÖVE's field names, each an Integer as the C++
// holds it (ADR 001, rule 14).
Rice::Hash stats() {
  const Graphics::Stats stats = graphics().getStats();
  Rice::Hash fields;
  set_field(fields, "drawcalls", stats.drawCalls);
  set_field(fields, "drawcallsbatched", stats.drawCallsBatched);
  set_field(fields, "canvasswitches", stats.renderTargetSwitches);
  set_field(fields, "shaderswitches", stats.shaderSwitches);
  set_field(fields, "textures", stats.textures);
  set_field(fields, "fonts", stats.fonts);
  set_field(fields, "buffers", stats.buffers);
  set_field(fields, "texturememory", static_cast<long long>(stats.textureMemory));
  set_field(fields, "buffermemory", static_cast<long long>(stats.bufferMemory));
  return fields;
}

// w_getSupported (wrap_Graphics.cpp:2998-3020): whether the renderer has
// each optional feature, by the feature's name.
Rice::Hash supported() {
  const Graphics::Capabilities &caps = graphics().getCapabilities();
  Rice::Hash fields;
  set_fields<Graphics::Feature>(fields, std::span(caps.features), &Graphics::getConstant);
  return fields;
}

// w_getSystemLimits (wrap_Graphics.cpp:3182-3204): each of the renderer's
// limits, by its name, as the double LÖVE holds it.
Rice::Hash system_limits() {
  const Graphics::Capabilities &caps = graphics().getCapabilities();
  Rice::Hash fields;
  set_fields<Graphics::SystemLimit>(fields, std::span(caps.limits), &Graphics::getConstant);
  return fields;
}

// w_getTextureFormats (wrap_Graphics.cpp:3022-3064): whether a texture
// with the given settings can have each pixel format, by the format's
// name. A format is sampled unless +readable+ says otherwise, and by
// default unless it is a depth or stencil format.
Rice::Hash texture_formats(bool rt, bool computewrite, bool shaderatomics,
                           std::optional<bool> readable) {
  Graphics &instance = graphics();
  Rice::Hash fields;
  for (int i = 0; i < static_cast<int>(love::PIXELFORMAT_MAX_ENUM); i++) {
    const auto format = static_cast<love::PixelFormat>(i);
    const char *name = nullptr;
    if (format == love::PIXELFORMAT_UNKNOWN || !love::getConstant(format, name)) {
      continue;
    }
    love::uint32 usage = love::graphics::PIXELFORMATUSAGEFLAGS_NONE;
    if (rt) {
      usage |= love::graphics::PIXELFORMATUSAGEFLAGS_RENDERTARGET;
    }
    if (readable.value_or(!love::isPixelFormatDepthStencil(format))) {
      usage |= love::graphics::PIXELFORMATUSAGEFLAGS_SAMPLE;
    }
    if (computewrite) {
      usage |= love::graphics::PIXELFORMATUSAGEFLAGS_COMPUTEWRITE;
    }
    if (shaderatomics) {
      usage |= love::graphics::PIXELFORMATUSAGEFLAGS_SHADERATOMICS;
    }
    set_field(fields, name, instance.isPixelFormatSupported(format, usage));
  }
  return fields;
}

// w_getTextureTypes (wrap_Graphics.cpp:3146-3168): whether the renderer
// has each type of texture, by the type's name.
Rice::Hash texture_types() {
  const Graphics::Capabilities &caps = graphics().getCapabilities();
  Rice::Hash fields;
  set_fields<love::graphics::TextureType>(fields, std::span(caps.textureTypes),
                                          &Texture::getConstant);
  return fields;
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

// w_setBackgroundColor with three or four numbers
// (wrap_Graphics.cpp:2527-2551), as set_color binds love.graphics.setColor.
void set_background_color(double red, double green, double blue, double alpha) {
  graphics().setBackgroundColor(love::Colorf(static_cast<float>(red), static_cast<float>(green),
                                             static_cast<float>(blue), static_cast<float>(alpha)));
}

// The rectangle w_setScissor and w_intersectScissor read
// (wrap_Graphics.cpp:570-576 and 586-592): each side as a float, and no
// negative size.
love::FRect scissor_rect(double x, double y, double width, double height) {
  const love::FRect rect{
      .x = static_cast<float>(x),
      .y = static_cast<float>(y),
      .w = static_cast<float>(width),
      .h = static_cast<float>(height),
  };
  if (rect.w < 0 || rect.h < 0) {
    throw love::Exception("Can't set scissor with negative width and/or height.");
  }
  return rect;
}

// w_setScissor with a rectangle (wrap_Graphics.cpp:560-582).
void set_scissor(double x, double y, double width, double height) {
  graphics().setScissor(scissor_rect(x, y, width, height));
}

// w_intersectScissor (wrap_Graphics.cpp:584-597): clip to where the
// scissor and the rectangle overlap.
void intersect_scissor(double x, double y, double width, double height) {
  graphics().intersectScissor(scissor_rect(x, y, width, height));
}

// w_setScissor with no rectangle (wrap_Graphics.cpp:562-568): stop
// clipping.
void reset_scissor() { graphics().setScissor(); }

// w_getCanvas (wrap_Graphics.cpp:389-437) of the targets set_canvas sets:
// none, which LÖVE returns as nil, or one 2D texture at its first mipmap,
// which it returns alone. LÖVE returns its other targets as a table, or
// as several values, which Lota binds with the forms of setCanvas that
// set them.
Texture *canvas() {
  const Graphics::RenderTargets targets = graphics().getRenderTargets();
  if (targets.colors.empty()) {
    return nullptr;
  }
  const Graphics::RenderTarget &target = targets.colors.front();
  if (targets.colors.size() > 1 || targets.depthStencil.texture != nullptr || target.mipmap != 0 ||
      target.texture->getTextureType() != love::graphics::TEXTURE_2D) {
    throw love::Exception("%s.canvas returns only a canvas %s.canvas= set.", MODULE, MODULE);
  }
  return target.texture;
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

// w_Font_getWidth with a string (wrap_Font.cpp:90-104): the width of
// +text+'s widest line.
double font_text_width(Font &font, const std::string &text) {
  require_main_thread(MODULE);
  return font.getWidth(text);
}

// w_Font_getWidth with a number: the width of one glyph, by its code
// point, read as LÖVE reads it (uint32 of a number).
double font_glyph_width(Font &font, double glyph) {
  require_main_thread(MODULE);
  return font.getWidth(static_cast<love::uint32>(glyph));
}

// w_Font_getWrap (wrap_Font.cpp:106-133): +text+, as colored_strings
// reads it, wrapped at +wraplimit+, as the width of its widest line and
// its lines.
Rice::Array font_wrap(Font &font, Rice::Array text, double wraplimit) {
  require_main_thread(MODULE);
  const Rice::Array parts = std::move(text);
  const std::vector<love::font::ColoredString> strings = colored_strings(parts);
  std::vector<std::string> lines;
  std::vector<float> widths;
  font.getWrap(strings, static_cast<float>(wraplimit), lines, &widths);
  float max_width = 0;
  for (const float width : widths) {
    max_width = std::max(max_width, width);
  }
  Rice::Array wrapped;
  for (const std::string &line : lines) {
    wrapped.push(line, false);
  }
  Rice::Array results;
  results.push(static_cast<double>(max_width), false);
  results.push(wrapped, false);
  return results;
}

// w_Font_hasGlyphs with a string (wrap_Font.cpp:204-226): whether the
// font has every glyph of +text+.
bool font_has_text_glyphs(const Font &font, const std::string &text) {
  require_main_thread(MODULE);
  return font.hasGlyphs(text);
}

// w_Font_hasGlyphs with a number: whether the font has the glyph of one
// code point.
bool font_has_glyph(const Font &font, double glyph) {
  require_main_thread(MODULE);
  return font.hasGlyph(static_cast<love::uint32>(glyph));
}

// w_Font_getKerning with strings (wrap_Font.cpp:228-251): the kerning
// between the first characters of +left+ and +right+.
double font_text_kerning(Font &font, const std::string &left, const std::string &right) {
  require_main_thread(MODULE);
  return font.getKerning(left, right);
}

// w_Font_getKerning with numbers: the kerning between two glyphs, by
// their code points.
double font_glyph_kerning(Font &font, double left, double right) {
  require_main_thread(MODULE);
  return font.getKerning(static_cast<love::uint32>(left), static_cast<love::uint32>(right));
}

// w_Font_setFallbacks (wrap_Font.cpp:253-262): the fonts whose glyphs
// stand in, in order, for those +font+ lacks; none clears them.
void font_set_fallbacks(Font &font, Rice::Array fallbacks) {
  require_main_thread(MODULE);
  const Rice::Array given = std::move(fallbacks);
  std::vector<Font *> fonts;
  for (const auto item : given) {
    fonts.push_back(Rice::detail::From_Ruby<Font *>().convert(item.value()));
  }
  font.setFallbacks(fonts);
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

// w_print with numbers (wrap_Graphics.cpp:3410-3433): +text+ in +font+,
// or in the current font when +font+ is nil, from the top left of its
// first line.
void print(Rice::Array text, Font *font, Rice::Array placement) {
  const Rice::Array parts = std::move(text);
  const Rice::Array numbers = std::move(placement);
  const std::vector<love::font::ColoredString> strings = colored_strings(parts);
  if (font != nullptr) {
    graphics().print(strings, font, placement_of(numbers));
  } else {
    graphics().print(strings, placement_of(numbers));
  }
}

// w_printf with numbers (wrap_Graphics.cpp:3435-3492): +text+ in +font+,
// or in the current font when +font+ is nil, wrapped at +limit+ and aligned within it. The
// alignment is checked after the numbers, and before the module.
void printf(Rice::Array text, Font *font, Rice::Array placement, double limit,
            const std::optional<std::string> &align) {
  const Rice::Array parts = std::move(text);
  const Rice::Array numbers = std::move(placement);
  const std::vector<love::font::ColoredString> strings = colored_strings(parts);
  const love::Matrix4 matrix = placement_of(numbers);
  Font::AlignMode mode = Font::ALIGN_LEFT;
  if (align.has_value() && !Font::getConstant(align->c_str(), mode)) {
    raise_enum_error("alignment", Font::getConstants(mode), *align);
  }
  if (font != nullptr) {
    graphics().printf(strings, font, static_cast<float>(limit), mode, matrix);
  } else {
    graphics().printf(strings, static_cast<float>(limit), mode, matrix);
  }
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

// Texture:renderTo (wrap_Texture.cpp:459-514): draws to the texture, or
// to the slice of it that +slice+ names, counting from 1, for a texture
// that is not 2D, while +block+ runs, then puts back the render targets
// that were set before, also when the block raises, and raises again what
// it raised, as LÖVE raises the error its function raised after putting
// them back. The old targets are held while the block runs, as LÖVE holds
// them. Without the graphics module open, LÖVE neither draws nor calls the
// function, and neither does Lota.
void texture_render_to(Texture &texture, std::optional<int> slice, Rice::Object block) {
  require_main_thread(MODULE);
  const Rice::Object function = std::move(block);
  Graphics::RenderTarget target(&texture);

  if (target.texture->getTextureType() != love::graphics::TEXTURE_2D) {
    target.slice = required(slice, "slice") - 1;
  }

  auto *instance = love::Module::getInstance<Graphics>(love::Module::M_GRAPHICS);
  if (instance == nullptr) {
    return;
  }

  // Save the current render targets so we can restore them when we're done.
  const Graphics::RenderTargets oldtargets = instance->getRenderTargets();
  const auto release = [&oldtargets] {
    for (const auto &color : oldtargets.colors) {
      color.texture->release();
    }
    if (oldtargets.depthStencil.texture != nullptr) {
      oldtargets.depthStencil.texture->release();
    }
  };

  for (const auto &color : oldtargets.colors) {
    color.texture->retain();
  }
  if (oldtargets.depthStencil.texture != nullptr) {
    oldtargets.depthStencil.texture->retain();
  }

  try {
    instance->setRenderTarget(target, 0);
  } catch (...) {
    release();
    throw;
  }

  std::exception_ptr raised;
  try {
    function.call("call");
  } catch (...) {
    raised = std::current_exception();
  }

  instance->setRenderTargets(oldtargets);
  release();

  if (raised) {
    std::rethrow_exception(raised);
  }
}

// w_push (wrap_Graphics.cpp:3910-3926): the transformation, or all the
// state when +stack+ names "all", which LÖVE checks before it pushes, and
// then +transform+ applied, when it is not nil.
void push(const std::optional<std::string> &stack, const love::math::Transform *transform) {
  Graphics::StackType stype = Graphics::STACK_TRANSFORM;
  if (stack.has_value() && !Graphics::getConstant(stack->c_str(), stype)) {
    raise_enum_error("graphics stack type", Graphics::getConstants(stype), *stack);
  }
  Graphics &instance = graphics();
  instance.push(stype);
  if (transform != nullptr) {
    instance.applyTransform(transform->getMatrix());
  }
}

// w_applyTransform with a Transform (wrap_Graphics.cpp:3971-3978, through
// luax_checkstandardtransform, wrap_SpriteBatch.h:33-64).
void apply_transform(const love::math::Transform *transform) {
  graphics().applyTransform(transform->getMatrix());
}

// w_applyTransform with numbers: the placement luax_checkstandardtransform
// builds from them.
void apply_placement(Rice::Array placement) {
  const Rice::Array numbers = std::move(placement);
  graphics().applyTransform(placement_of(numbers));
}

// w_replaceTransform with a Transform (wrap_Graphics.cpp:3980-3987).
void replace_transform(const love::math::Transform *transform) {
  graphics().replaceTransform(transform->getMatrix());
}

// w_replaceTransform with numbers, as apply_placement.
void replace_placement(Rice::Array placement) {
  const Rice::Array numbers = std::move(placement);
  graphics().replaceTransform(placement_of(numbers));
}

// w_transformPoint (wrap_Graphics.cpp:3989-3998): the point through the
// current transformation, each coordinate read as a float and pushed as a
// lua_Number, a double.
Rice::Array transform_point(double x, double y) {
  const love::Vector2 p =
      graphics().transformPoint(love::Vector2(static_cast<float>(x), static_cast<float>(y)));
  Rice::Array results;
  results.push(static_cast<double>(p.x), false);
  results.push(static_cast<double>(p.y), false);
  return results;
}

// w_inverseTransformPoint (wrap_Graphics.cpp:4000-4009), as
// transform_point, through the inverse.
Rice::Array inverse_transform_point(double x, double y) {
  const love::Vector2 p =
      graphics().inverseTransformPoint(love::Vector2(static_cast<float>(x), static_cast<float>(y)));
  Rice::Array results;
  results.push(static_cast<double>(p.x), false);
  results.push(static_cast<double>(p.y), false);
  return results;
}

// w_setProjection with a Transform (wrap_Graphics.cpp:4011-4037).
void set_projection(const love::math::Transform *transform) {
  graphics().setProjection(transform->getMatrix());
}

// w_setProjection with a matrix layout's name or nil and the sixteen
// elements in one Array, read as luax_checkmatrix reads them.
void set_projection_matrix(const std::optional<std::string> &layout, Rice::Array elements) {
  const Rice::Array given = std::move(elements);
  const love::Matrix4 matrix = matrix_of(layout, given);
  graphics().setProjection(matrix);
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

// w_points with its coordinates in one Array (wrap_Graphics.cpp:3490-3576),
// as Lota::Graphics.points passes them however they were given: LÖVE
// checks their count before it reads them, reads each as a float, and
// draws every point in the current color.
void points(Rice::Array coordinates) {
  const Rice::Array list = std::move(coordinates);
  const std::vector<Rice::Object> given = elements(list);
  if (given.size() % 2 != 0) {
    throw love::Exception("Number of vertex components must be a multiple of two");
  }
  Graphics &instance = graphics();
  const std::size_t numpositions = given.size() / 2;
  const std::span<love::Vector2> positions(
      instance.getScratchBuffer<love::Vector2>(static_cast<int>(numpositions)), numpositions);
  std::size_t component = 0;
  for (love::Vector2 &position : positions) {
    position.x = to_float(given.at(component));
    position.y = to_float(given.at(component + 1));
    component += 2;
  }
  instance.points(positions.data(), nullptr, numpositions);
}

// w_polygon with its coordinates in one Array (wrap_Graphics.cpp:3742-3788),
// as Lota::Graphics.polygon passes them however they were given: LÖVE
// checks the draw mode, then the count, reads each coordinate as a float,
// and closes the loop by repeating the first vertex.
void polygon(const std::string &str, Rice::Array coordinates) {
  const Rice::Array list = std::move(coordinates);
  const std::vector<Rice::Object> given = elements(list);
  Graphics::DrawMode mode = Graphics::DRAW_LINE;
  if (!Graphics::getConstant(str.c_str(), mode)) {
    raise_enum_error("draw mode", Graphics::getConstants(mode), str);
  }
  constexpr std::size_t least = 6;
  if (given.size() % 2 != 0) {
    throw love::Exception("Number of vertex components must be a multiple of two");
  }
  if (given.size() < least) {
    throw love::Exception("Need at least three vertices to draw a polygon");
  }
  Graphics &instance = graphics();
  const std::size_t numvertices = given.size() / 2;
  const std::span<love::Vector2> coords(
      instance.getScratchBuffer<love::Vector2>(static_cast<int>(numvertices + 1)), numvertices + 1);
  std::size_t component = 0;
  for (love::Vector2 &coord : coords.first(numvertices)) {
    coord.x = to_float(given.at(component));
    coord.y = to_float(given.at(component + 1));
    component += 2;
  }
  coords.back() = coords.front();
  instance.polygon(mode, coords.data(), numvertices + 1);
}

// SPDX-SnippetEnd

} // namespace

void define_graphics(const Rice::Module &native) {
  // Its methods are generated (ext/lota/native/generated/graphics.cpp).
  define_engine_class<Texture>(native, "Texture")
      .define_method("width", &texture_width, Rice::Arg("mipmap") = std::optional<int>())
      .define_method("height", &texture_height, Rice::Arg("mipmap") = std::optional<int>())
      .define_method("render_to", &texture_render_to, Rice::Arg("slice"), Rice::Arg("block"));
  // Their other methods are generated too.
  define_engine_class<love::graphics::Quad>(native, "Quad")
      .define_method("set_viewport", &quad_set_viewport, Rice::Arg("viewport"),
                     Rice::Arg("sw") = std::optional<double>(),
                     Rice::Arg("sh") = std::optional<double>());
  define_engine_class<love::graphics::SpriteBatch>(native, "SpriteBatch")
      .define_method("add", &sprite_batch_add, Rice::Arg("quad"), Rice::Arg("placement"))
      .define_method("set", &sprite_batch_set, Rice::Arg("index"), Rice::Arg("quad"),
                     Rice::Arg("placement"))
      .define_method("set_color", &sprite_batch_set_color, Rice::Arg("red"), Rice::Arg("green"),
                     Rice::Arg("blue"), Rice::Arg("alpha"));
  // LÖVE's graphics Font is Native::Graphics::Font, since Native::Font is
  // love.font, the module that rasterizes its glyphs (native/font.cpp).
  Rice::Module graphics_module = Rice::define_module_under(native, "Graphics");
  // Font's other methods are generated.
  define_engine_class<Font>(graphics_module, "Font")
      .define_method("text_width", &font_text_width, Rice::Arg("text"))
      .define_method("glyph_width", &font_glyph_width, Rice::Arg("glyph"))
      .define_method("wrap", &font_wrap, Rice::Arg("text"), Rice::Arg("wraplimit"))
      .define_method("text_glyphs?", &font_has_text_glyphs, Rice::Arg("text"))
      .define_method("glyph?", &font_has_glyph, Rice::Arg("glyph"))
      .define_method("text_kerning", &font_text_kerning, Rice::Arg("left"), Rice::Arg("right"))
      .define_method("glyph_kerning", &font_glyph_kerning, Rice::Arg("left"), Rice::Arg("right"))
      .define_method("set_fallbacks", &font_set_fallbacks, Rice::Arg("fallbacks"));

  graphics_module.define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("set_gamma_correct", &set_gamma_correct,
                                 Rice::Arg("gamma_correct"))
      .define_singleton_function("set_low_power_preferred", &set_low_power_preferred,
                                 Rice::Arg("preferred"))
      .define_singleton_function("default_renderers", &default_renderers)
      .define_singleton_function("set_renderers", &set_renderers, Rice::Arg("names"))
      .define_singleton_function("present", &present)
      .define_singleton_function("push", &push, Rice::Arg("stack") = std::optional<std::string>(),
                                 Rice::Arg("transform") =
                                     static_cast<const love::math::Transform *>(nullptr))
      .define_singleton_function("apply_transform", &apply_transform, Rice::Arg("transform"))
      .define_singleton_function("apply_placement", &apply_placement, Rice::Arg("placement"))
      .define_singleton_function("replace_transform", &replace_transform, Rice::Arg("transform"))
      .define_singleton_function("replace_placement", &replace_placement, Rice::Arg("placement"))
      .define_singleton_function("transform_point", &transform_point, Rice::Arg("x"),
                                 Rice::Arg("y"))
      .define_singleton_function("inverse_transform_point", &inverse_transform_point,
                                 Rice::Arg("x"), Rice::Arg("y"))
      .define_singleton_function("set_projection", &set_projection, Rice::Arg("transform"))
      .define_singleton_function("set_projection_matrix", &set_projection_matrix,
                                 Rice::Arg("layout"), Rice::Arg("elements"))
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
      .define_singleton_function("capture_screenshot_to_file", &capture_screenshot_to_file,
                                 Rice::Arg("filename"))
      .define_singleton_function("stats", &stats)
      .define_singleton_function("supported", &supported)
      .define_singleton_function("system_limits", &system_limits)
      .define_singleton_function("texture_formats", &texture_formats, Rice::Arg("rt"),
                                 Rice::Arg("computewrite"), Rice::Arg("shaderatomics"),
                                 Rice::Arg("readable"))
      .define_singleton_function("texture_types", &texture_types)
      .define_singleton_function("new_default_font", &new_default_font, Rice::Arg("size"),
                                 Rice::Arg("hinting"), Rice::Arg("dpiscale"), Rice::Arg("sdf"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_truetype_font", &new_truetype_font, Rice::Arg("data"),
                                 Rice::Arg("size"), Rice::Arg("hinting"), Rice::Arg("dpiscale"),
                                 Rice::Arg("sdf"), Rice::Return().takeOwnership())
      .define_singleton_function("new_font_from_file", &new_font_from_file, Rice::Arg("data"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("print", &print, Rice::Arg("text"), Rice::Arg("font"),
                                 Rice::Arg("placement"))
      .define_singleton_function("printf", &printf, Rice::Arg("text"), Rice::Arg("font"),
                                 Rice::Arg("placement"), Rice::Arg("limit"), Rice::Arg("align"))
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
      .define_singleton_function("points", &points, Rice::Arg("coordinates"))
      .define_singleton_function("polygon", &polygon, Rice::Arg("mode"), Rice::Arg("coordinates"))
      .define_singleton_function("set_background_color", &set_background_color, Rice::Arg("red"),
                                 Rice::Arg("green"), Rice::Arg("blue"), Rice::Arg("alpha"))
      .define_singleton_function("set_scissor", &set_scissor, Rice::Arg("x"), Rice::Arg("y"),
                                 Rice::Arg("width"), Rice::Arg("height"))
      .define_singleton_function("reset_scissor", &reset_scissor)
      .define_singleton_function("intersect_scissor", &intersect_scissor, Rice::Arg("x"),
                                 Rice::Arg("y"), Rice::Arg("width"), Rice::Arg("height"))
      .define_singleton_function("canvas", &canvas)
      .define_singleton_function("arc", &arc, Rice::Arg("drawstr"), Rice::Arg("arcstr"),
                                 Rice::Arg("arguments"));
}

} // namespace lota::native
