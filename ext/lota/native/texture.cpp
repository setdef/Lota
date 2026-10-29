// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/texture.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h"
#include "common/int.h"
#include "common/math.h"
#include "common/pixelformat.h"
#include "filesystem/FileData.h"
#include "graphics/Graphics.h"
#include "graphics/Texture.h"
#include "image/CompressedImageData.h"
#include "image/Image.h"
#include "image/ImageData.h"

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::graphics::Graphics;
using love::graphics::Texture;
using love::image::CompressedImageData;
using love::image::ImageData;

namespace {

constexpr const char *MODULE = "Lota::Graphics";

Graphics &graphics() {
  require_main_thread(MODULE);
  auto *instance = love::Module::getInstance<Graphics>(love::Module::M_GRAPHICS);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", MODULE);
  }
  return *instance;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib

// luax_checkgraphicscreated (wrap_Graphics.cpp:56-61): the module, once
// it has a window to draw in.
Graphics &created_graphics() {
  Graphics &instance = graphics();
  if (!instance.isCreated()) {
    throw love::Exception("%s cannot function without a window.", MODULE);
  }
  return instance;
}

// The element of +elements+ at +index+, or nil past its end, as Lua
// reads a table's missing element (lua_rawgeti).
Rice::Object element(const std::vector<Rice::Object> &elements, std::size_t index) {
  return index < elements.size() ? elements.at(index) : ruby::nil();
}

// --- Texture::Settings, which Lota::Graphics::TextureSettings fills as
// luax_checktexturesettings (wrap_Graphics.cpp:759-871) reads its table.

// luax_checktablefields (common/runtime.h:519-538) of a texture setting:
// LÖVE refuses a name it does not know.
void check_setting_name(const std::string &name) {
  Texture::SettingType setting = Texture::SETTING_MAX_ENUM;
  if (!Texture::getConstant(name.c_str(), setting)) {
    raise_enum_error("texture setting name", name);
  }
}

// The setting "format" (wrap_Graphics.cpp:780-787).
void set_format(Texture::Settings &settings, const std::string &str) {
  if (!love::getConstant(str.c_str(), settings.format)) {
    raise_enum_error("pixel format", str);
  }
}

// The setting "type" (wrap_Graphics.cpp:789-799).
void set_type(Texture::Settings &settings, const std::string &str) {
  if (!Texture::getConstant(str.c_str(), settings.type)) {
    raise_enum_error("texture type", Texture::getConstants(settings.type), str);
  }
}

// The texture type, by its name, which decides whether the settings read
// a layer count (wrap_Graphics.cpp:801-814).
std::string type(const Texture::Settings &settings) {
  const char *str = nullptr;
  Texture::getConstant(settings.type, str);
  return str;
}

// The setting "mipmaps" by its name (wrap_Graphics.cpp:816-827); a
// boolean, which Lota::Graphics::TextureSettings reads as LÖVE does,
// names "manual" or "none".
void set_mipmaps(Texture::Settings &settings, const std::string &str) {
  if (!Texture::getConstant(str.c_str(), settings.mipmaps)) {
    raise_enum_error("Texture mipmap mode", Texture::getConstants(settings.mipmaps), str);
  }
}

// One format of the setting "viewformats" (wrap_Graphics.cpp:837-853).
void add_view_format(Texture::Settings &settings, const std::string &str) {
  love::PixelFormat viewformat = love::PIXELFORMAT_UNKNOWN;
  if (!love::getConstant(str.c_str(), viewformat)) {
    raise_enum_error("pixel format", str);
  }
  settings.viewFormats.push_back(viewformat);
}

// The setting "readable" (wrap_Graphics.cpp:855-858), which LÖVE leaves
// unset unless it is given.
void set_readable(Texture::Settings &settings, bool readable) { settings.readable.set(readable); }

float dpi_scale(const Texture::Settings &settings) { return settings.dpiScale; }

void set_dpi_scale(Texture::Settings &settings, double dpiscale) {
  settings.dpiScale = static_cast<float>(dpiscale);
}

// --- Making textures.

// parseDPIScale (wrap_Graphics.cpp:692-712): a file named like
// "image@2x.png" holds pixels at twice the density, so the texture made
// from it takes a DPI scale of 2. Data that is not a file has no name to
// parse.
void parse_dpi_scale(love::Data *data, float *dpiscale) {
  const auto *file = dynamic_cast<love::filesystem::FileData *>(data);
  if (file == nullptr || dpiscale == nullptr) {
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
      *dpiscale = static_cast<float>(density);
    }
  }
}

using ImagePair = std::pair<love::StrongRef<ImageData>, love::StrongRef<CompressedImageData>>;

// getImageData (wrap_Graphics.cpp:714-745) of what Lota::Graphics passes
// for one image: an ImageData as it is, or a Data, which Lota::Graphics
// makes of a file name, a FileData, or other Data, as luax_getdata reads
// them, decoded to an ImageData, or kept compressed in a format the image
// module recognizes. Every caller allows compressed images.
ImagePair image_data_of(const Rice::Object &source, float *dpiscale) {
  ImagePair result;
  if (ruby::is_kind_of(source, Rice::Data_Type<ImageData>::klass())) {
    result.first.set(Rice::detail::From_Ruby<ImageData *>().convert(source.value()));
    return result;
  }
  if (!ruby::is_kind_of(source, Rice::Data_Type<love::Data>::klass())) {
    ruby::raise_type_error("wrong argument type " + ruby::class_name(source) +
                           " (expected Lota::Image::ImageData)");
  }
  auto *imagemodule = love::Module::getInstance<love::image::Image>(love::Module::M_IMAGE);
  if (imagemodule == nullptr) {
    throw love::Exception("Cannot load images without the love.image module.");
  }
  love::Data *fdata = Rice::detail::From_Ruby<love::Data *>().convert(source.value());
  parse_dpi_scale(fdata, dpiscale);
  if (imagemodule->isCompressed(fdata)) {
    result.second.set(imagemodule->newCompressedData(fdata), love::Acquire::NORETAIN);
  } else {
    result.first.set(imagemodule->newImageData(fdata), love::Acquire::NORETAIN);
  }
  return result;
}

// The images Lota::Graphics passes as an Array, which luaL_checktype
// requires where LÖVE reads a table of tables.
std::vector<Rice::Object> array_elements(const Rice::Object &images) {
  if (!ruby::is_array(images)) {
    ruby::raise_type_error("wrong argument type " + ruby::class_name(images) + " (expected Array)");
  }
  return ruby::elements(Rice::Array(images));
}

// luax_isarrayoftables (common/runtime.cpp:243-252): whether +images+'
// first element is an Array.
bool array_of_arrays(const std::vector<Rice::Object> &images) {
  return !images.empty() && ruby::is_array(images.front());
}

// luax_objlen of an Array, at least 1, as LÖVE counts a table of images
// (wrap_Graphics.cpp:944, 1102, and 1179).
std::size_t image_count(const std::vector<Rice::Object> &images) {
  return std::max<std::size_t>(1, images.size());
}

int index_of(std::size_t index) { return static_cast<int>(index); }

// The image +pair+ holds, set at +slice+ and +mipmap+: an ImageData, or a
// compressed image's first slice, as w_newTexture and its kin set each
// image of a table of tables.
void set_slice(Texture::Slices &slices, int slice, int mipmap, const ImagePair &pair) {
  if (pair.first.get() != nullptr) {
    slices.set(slice, mipmap, pair.first);
  } else {
    slices.set(slice, mipmap, pair.second->getSlice(0, 0));
  }
}

// One image of a list that is not a table of tables: an ImageData at
// +slice+, or every mipmap of a compressed image there, as w_newTexture
// and its kin add one (wrap_Graphics.cpp:1145-1149).
void add_slice(Texture::Slices &slices, const Texture::Settings &settings, int slice,
               const ImagePair &pair) {
  if (pair.first.get() != nullptr) {
    slices.set(slice, 0, pair.first);
  } else {
    slices.add(pair.second, slice, 0, false, settings.mipmaps != Texture::MIPMAPS_NONE);
  }
}

// One image that holds every slice: an ImageData's +slices+, which the
// image module cuts from it, or every slice and mipmap of a compressed
// image (wrap_Graphics.cpp:1017-1029 and 1220-1233).
void add_whole(Texture::Slices &slices, const Texture::Settings &settings,
               const std::vector<love::StrongRef<ImageData>> &cut, const ImagePair &pair) {
  if (pair.first.get() != nullptr) {
    for (std::size_t i = 0; i < cut.size(); i++) {
      slices.set(index_of(i), 0, cut.at(i));
    }
  } else {
    slices.add(pair.second, 0, 0, true, settings.mipmaps != Texture::MIPMAPS_NONE);
  }
}

// One Array of a table of tables, each image at +outer+ and its own index,
// as +place+ sets it: a face's or a layer's mipmaps, or a mipmap's layers.
template <typename Place>
void set_each(const Rice::Object &images, float *autodpiscale, bool first, const Place &place) {
  const std::vector<Rice::Object> inner = array_elements(images);
  const std::size_t count = image_count(inner);
  for (std::size_t i = 0; i < count; i++) {
    place(index_of(i), image_data_of(element(inner, i), first && i == 0 ? autodpiscale : nullptr));
  }
}

// w__pushNewTexture (wrap_Graphics.cpp:747-757): the texture, whose one
// reference goes to the Ruby wrapper.
Texture *push_new_texture(const Texture::Slices *slices, const Texture::Settings &settings) {
  return graphics().newTexture(settings, slices);
}

// w_newCanvas (wrap_Graphics.cpp:873-913) of the settings
// Lota::Graphics::Canvas.new reads: at the screen's DPI scale unless they
// set one.
Texture *new_canvas(Texture::Settings &settings, bool dpiscaleset) {
  Graphics &instance = created_graphics();
  if (!dpiscaleset) {
    settings.dpiScale = static_cast<float>(instance.getScreenDPIScale());
  }
  return instance.newTexture(settings);
}

// The screen's size, which w_newCanvas makes a canvas unless told
// otherwise (wrap_Graphics.cpp:889-890).
Rice::Array canvas_size() {
  Graphics &instance = created_graphics();
  Rice::Array size;
  size.push(instance.getWidth(), false);
  size.push(instance.getHeight(), false);
  return size;
}

// w_newTexture and its kin given a width and a height
// (wrap_Graphics.cpp:921-937, 1006-1011, 1094-1100, and 1171-1177): a
// texture with no pixels yet.
Texture *new_empty_texture(const Texture::Settings &settings) {
  created_graphics();
  return push_new_texture(nullptr, settings);
}

// w_newTexture given images (wrap_Graphics.cpp:938-972): one image, or an
// Array of them, one mipmap each.
Texture *new_texture(Texture::Settings &settings, bool dpiscaleset, Rice::Object given_images) {
  const Rice::Object images = std::move(given_images);
  created_graphics();
  Texture::Slices slices(love::graphics::TEXTURE_2D);
  float *autodpiscale = dpiscaleset ? nullptr : &settings.dpiScale;

  if (ruby::is_array(images)) {
    set_each(images, autodpiscale, true,
             [&slices](int mip, const ImagePair &data) { set_slice(slices, 0, mip, data); });
  } else {
    const ImagePair data = image_data_of(images, autodpiscale);
    if (data.first.get() != nullptr) {
      slices.set(0, 0, data.first);
    } else {
      slices.add(data.second, 0, 0, false, settings.mipmaps != Texture::MIPMAPS_NONE);
    }
  }
  return push_new_texture(&slices, settings);
}

// w_newCubeTexture's Array of images that is not a table of tables
// (wrap_Graphics.cpp:1054-1081): each a face or, once one is not square,
// a mipmap of all six, whose faces the image module cuts from it. LÖVE
// sets each face of that mipmap from the face its index names (line
// 1070), and so does Lota, which raises where that face is past the six.
void add_cube_list(Texture::Slices &slices, const Texture::Settings &settings,
                   const std::vector<Rice::Object> &images, float *autodpiscale) {
  auto *imagemodule = love::Module::getInstance<love::image::Image>(love::Module::M_IMAGE);
  bool usemipmaps = false;
  for (std::size_t i = 0; i < images.size(); i++) {
    const ImagePair data = image_data_of(images.at(i), i == 0 ? autodpiscale : nullptr);
    if (data.first.get() == nullptr) {
      slices.add(data.second, index_of(i), 0, false, settings.mipmaps != Texture::MIPMAPS_NONE);
    } else if (usemipmaps || data.first->getWidth() != data.first->getHeight()) {
      usemipmaps = true;
      const std::vector<love::StrongRef<ImageData>> faces = imagemodule->newCubeFaces(data.first);
      for (std::size_t face = 0; face < faces.size(); face++) {
        slices.set(index_of(face), index_of(i), faces.at(i));
      }
    } else {
      slices.set(index_of(i), 0, data.first);
    }
  }
}

// w_newCubeTexture given images (wrap_Graphics.cpp:1012-1086): one image
// that holds all six faces, six faces each an Array of mipmaps, or an
// Array of images, as add_cube_list reads them.
Texture *new_cube_texture(Texture::Settings &settings, bool dpiscaleset,
                          Rice::Object given_images) {
  const Rice::Object images = std::move(given_images);
  created_graphics();
  Texture::Slices slices(love::graphics::TEXTURE_CUBE);
  float *autodpiscale = dpiscaleset ? nullptr : &settings.dpiScale;
  auto *imagemodule = love::Module::getInstance<love::image::Image>(love::Module::M_IMAGE);

  if (!ruby::is_array(images)) {
    const ImagePair data = image_data_of(images, autodpiscale);
    const std::vector<love::StrongRef<ImageData>> faces =
        data.first.get() != nullptr ? imagemodule->newCubeFaces(data.first)
                                    : std::vector<love::StrongRef<ImageData>>();
    add_whole(slices, settings, faces, data);
    return push_new_texture(&slices, settings);
  }

  const std::vector<Rice::Object> list = ruby::elements(Rice::Array(images));
  if (!array_of_arrays(list)) {
    add_cube_list(slices, settings, list, autodpiscale);
    return push_new_texture(&slices, settings);
  }

  constexpr std::size_t cube_faces = 6;
  if (list.size() != cube_faces) {
    throw love::Exception("Cubemap images must have 6 faces.");
  }
  for (std::size_t face = 0; face < list.size(); face++) {
    set_each(list.at(face), autodpiscale, face == 0,
             [&slices, face](int mip, const ImagePair &data) {
               set_slice(slices, index_of(face), mip, data);
             });
  }
  return push_new_texture(&slices, settings);
}

// w_newArrayTexture given images (wrap_Graphics.cpp:1101-1152): an Array
// of layers, each an image or an Array of its mipmaps, or one image.
Texture *new_array_texture(Texture::Settings &settings, bool dpiscaleset,
                           Rice::Object given_images) {
  const Rice::Object images = std::move(given_images);
  created_graphics();
  Texture::Slices slices(love::graphics::TEXTURE_2D_ARRAY);
  float *autodpiscale = dpiscaleset ? nullptr : &settings.dpiScale;

  if (!ruby::is_array(images)) {
    const ImagePair data = image_data_of(images, autodpiscale);
    add_whole(slices, settings,
              data.first.get() != nullptr ? std::vector{data.first}
                                          : std::vector<love::StrongRef<ImageData>>(),
              data);
    return push_new_texture(&slices, settings);
  }

  const std::vector<Rice::Object> list = ruby::elements(Rice::Array(images));
  const bool tables = array_of_arrays(list);
  const std::size_t tlen = image_count(list);
  for (std::size_t slice = 0; slice < tlen; slice++) {
    if (tables) {
      set_each(element(list, slice), autodpiscale, slice == 0,
               [&slices, slice](int mip, const ImagePair &data) {
                 set_slice(slices, index_of(slice), mip, data);
               });
    } else {
      add_slice(slices, settings, index_of(slice),
                image_data_of(element(list, slice), slice == 0 ? autodpiscale : nullptr));
    }
  }
  return push_new_texture(&slices, settings);
}

// w_newVolumeTexture given images (wrap_Graphics.cpp:1178-1236): an Array
// of layers, an Array of mipmaps each an Array of layers, or one image
// that holds every layer, which the image module cuts from it.
Texture *new_volume_texture(Texture::Settings &settings, bool dpiscaleset,
                            Rice::Object given_images) {
  const Rice::Object images = std::move(given_images);
  created_graphics();
  auto *imagemodule = love::Module::getInstance<love::image::Image>(love::Module::M_IMAGE);
  Texture::Slices slices(love::graphics::TEXTURE_VOLUME);
  float *autodpiscale = dpiscaleset ? nullptr : &settings.dpiScale;

  if (!ruby::is_array(images)) {
    const ImagePair data = image_data_of(images, autodpiscale);
    const std::vector<love::StrongRef<ImageData>> layers =
        data.first.get() != nullptr ? imagemodule->newVolumeLayers(data.first)
                                    : std::vector<love::StrongRef<ImageData>>();
    add_whole(slices, settings, layers, data);
    return push_new_texture(&slices, settings);
  }

  const std::vector<Rice::Object> list = ruby::elements(Rice::Array(images));
  const bool tables = array_of_arrays(list);
  const std::size_t tlen = image_count(list);
  for (std::size_t outer = 0; outer < tlen; outer++) {
    if (tables) {
      set_each(element(list, outer), autodpiscale, outer == 0,
               [&slices, outer](int slice, const ImagePair &data) {
                 set_slice(slices, slice, index_of(outer), data);
               });
    } else {
      add_slice(slices, settings, index_of(outer),
                image_data_of(element(list, outer), outer == 0 ? autodpiscale : nullptr));
    }
  }
  return push_new_texture(&slices, settings);
}

// --- Reading a texture.

// lua_isnoneornil of an argument Lota::Graphics passes in an Array.
bool none_or_nil(const std::vector<Rice::Object> &arguments, std::size_t index) {
  return ruby::is_nil(element(arguments, index));
}

// luaL_checkinteger and luaL_optinteger of an argument in an Array:
// Rice converts it as LÖVE truncates a number to an int.
int integer_at(const std::vector<Rice::Object> &arguments, std::size_t index) {
  return Rice::detail::From_Ruby<int>().convert(element(arguments, index).value());
}

int optional_integer_at(const std::vector<Rice::Object> &arguments, std::size_t index,
                        int fallback) {
  return none_or_nil(arguments, index) ? fallback : integer_at(arguments, index);
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

// Texture:getWidth, getHeight, getDepth, getPixelWidth, and
// getPixelHeight (wrap_Texture.cpp:53-124), of the first mipmap or the one
// given.
int texture_width(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getWidth(mipmap_of(texture, mipmap));
}

int texture_height(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getHeight(mipmap_of(texture, mipmap));
}

int texture_depth(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getDepth(mipmap_of(texture, mipmap));
}

int texture_pixel_width(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getPixelWidth(mipmap_of(texture, mipmap));
}

int texture_pixel_height(const Texture &texture, std::optional<int> mipmap) {
  require_main_thread(MODULE);
  return texture.getPixelHeight(mipmap_of(texture, mipmap));
}

// w_readbackTexture (wrap_Graphics.cpp:2411-2449) of the arguments after
// the texture, as Lota::Graphics.readback_texture passes them: the slice,
// counting from 1, which a texture that is not 2D needs; the mipmap,
// counting from 1; a rectangle of x, y, width, and height; and an
// ImageData to read into, at a position. The new ImageData's one
// reference goes to the Ruby wrapper; read into one given, it is that
// one, which LÖVE retains as it returns it.
ImageData *readback_texture(Texture *t, Rice::Array arguments) {
  const Rice::Array moved = std::move(arguments);
  const std::vector<Rice::Object> given = ruby::elements(moved);
  Graphics &instance = graphics();

  int slice = 0;
  if (t->getTextureType() != love::graphics::TEXTURE_2D) {
    slice = integer_at(given, 0) - 1;
  } else if (!none_or_nil(given, 0) && !ruby::is_numeric(element(given, 0))) {
    ruby::raise_type_error("wrong argument type " + ruby::class_name(element(given, 0)) +
                           " for slice (expected Integer or nil)");
  }

  const int mipmap = optional_integer_at(given, 1, 1) - 1;

  love::Rect rect = {.x = 0, .y = 0, .w = t->getPixelWidth(mipmap), .h = t->getPixelHeight(mipmap)};
  constexpr std::size_t rect_index = 2;
  if (!none_or_nil(given, rect_index)) {
    rect.x = integer_at(given, rect_index);
    rect.y = integer_at(given, rect_index + 1);
    rect.w = integer_at(given, rect_index + 2);
    rect.h = integer_at(given, rect_index + 3);
  }

  ImageData *dest = nullptr;
  int destx = 0;
  int desty = 0;
  constexpr std::size_t dest_index = 6;
  if (!none_or_nil(given, dest_index)) {
    dest = Rice::detail::From_Ruby<ImageData *>().convert(element(given, dest_index).value());
    destx = optional_integer_at(given, dest_index + 1, 0);
    desty = optional_integer_at(given, dest_index + 2, 0);
  }

  return instance.readbackTexture(t, slice, mipmap, rect, dest, destx, desty);
}

// Texture:replacePixels with an ImageData (wrap_Texture.cpp:375-428), and
// the arguments after it, as Lota::Graphics::Texture#replace_pixels
// passes them: the slice, counting from 1, which a texture that is not 2D
// needs; the mipmap, counting from 1; a position; and whether to make the
// mipmaps again, which a texture with mipmaps "auto" does unless told not
// to.
void texture_replace_pixels(Texture &t, ImageData *id, Rice::Array arguments) {
  const Rice::Array moved = std::move(arguments);
  require_main_thread(MODULE);
  const std::vector<Rice::Object> given = ruby::elements(moved);
  int slice = 0;
  int x = 0;
  int y = 0;
  bool reloadmipmaps = t.getMipmapsMode() == Texture::MIPMAPS_AUTO;

  if (t.getTextureType() != love::graphics::TEXTURE_2D) {
    slice = integer_at(given, 0) - 1;
  }

  const int dstmip = optional_integer_at(given, 1, 1) - 1;

  constexpr std::size_t position_index = 2;
  if (!none_or_nil(given, position_index)) {
    x = integer_at(given, position_index);
    y = integer_at(given, position_index + 1);

    constexpr std::size_t reload_index = 4;
    if (reloadmipmaps && !none_or_nil(given, reload_index)) {
      reloadmipmaps = ruby::truthy(element(given, reload_index));
    }
  }

  t.replacePixels(id, slice, dstmip, x, y, reloadmipmaps);
}

// --- Drawing into textures.

// luax_checktexture of an argument Lota::Graphics passes: a Texture, or a
// TypeError, as LÖVE raises one.
Texture *texture_at(const Rice::Object &argument) {
  if (!ruby::is_kind_of(argument, Rice::Data_Type<Texture>::klass())) {
    ruby::raise_type_error("wrong argument type " + ruby::class_name(argument) +
                           " (expected Lota::Graphics::Texture)");
  }
  return Rice::detail::From_Ruby<Texture *>().convert(argument.value());
}

// The render targets set, or the window when the first is none
// (wrap_Graphics.cpp:360-365).
void set_render_targets(Graphics &instance, const Graphics::RenderTargets &targets) {
  if (targets.getFirstTarget().texture != nullptr) {
    instance.setRenderTargets(targets);
  } else {
    instance.setRenderTarget();
  }
}

// w_setCanvas with no argument or nil (wrap_Graphics.cpp:276-281): draw to
// the window again.
void reset_canvas() { graphics().setRenderTarget(); }

// w_setCanvas with textures as its arguments (wrap_Graphics.cpp:336-358),
// as Lota::Graphics.set_canvas passes them: textures, each 2D one
// optionally followed by its mipmap, counting from 1, or one texture that
// is not 2D followed by its slice and optionally its mipmap.
void set_canvas(Rice::Array arguments) {
  const Rice::Array moved = std::move(arguments);
  const std::vector<Rice::Object> given = ruby::elements(moved);
  Graphics &instance = graphics();
  Graphics::RenderTargets targets;

  for (std::size_t i = 0; i < given.size(); i++) {
    Graphics::RenderTarget target(texture_at(given.at(i)), 0);
    const love::graphics::TextureType type = target.texture->getTextureType();

    if (i == 0 && type != love::graphics::TEXTURE_2D) {
      target.slice = integer_at(given, i + 1) - 1;
      target.mipmap = optional_integer_at(given, i + 2, 1) - 1;
      targets.colors.push_back(target);
      break;
    }
    if (type == love::graphics::TEXTURE_2D && ruby::is_numeric(element(given, i + 1))) {
      target.mipmap = optional_integer_at(given, i + 1, 1) - 1;
      i++;
    }

    if (i > 0 && type != love::graphics::TEXTURE_2D) {
      throw love::Exception("This variant of setCanvas only supports 2D texture types.");
    }

    targets.colors.push_back(target);
  }

  set_render_targets(instance, targets);
}

// An integer field of a render target, which LÖVE requires
// (luax_checkintflag, common/runtime.cpp:362-377), as
// Lota::Graphics.set_canvas passes it at +index+, or nil.
int check_int_field(const std::vector<Rice::Object> &fields, std::size_t index,
                    const std::string &name) {
  if (!ruby::is_numeric(element(fields, index))) {
    ruby::raise_argument_error("expected integer field '" + name + "' in table");
  }
  return integer_at(fields, index);
}

// checkRenderTarget (wrap_Graphics.cpp:257-272) of a target as
// Lota::Graphics.set_canvas passes it: an Array of the texture, its layer,
// its face, and its mipmap, each counting from 1 and nil when not given.
// A texture that is not 2D needs its layer, or a cube's its face; the
// mipmap is the first unless given.
Graphics::RenderTarget render_target_of(const Rice::Object &target) {
  const std::vector<Rice::Object> fields = array_elements(target);
  Graphics::RenderTarget rt(texture_at(element(fields, 0)), 0);
  const love::graphics::TextureType type = rt.texture->getTextureType();
  constexpr std::size_t layer = 1;
  constexpr std::size_t face = 2;
  constexpr std::size_t mipmap = 3;
  if (type == love::graphics::TEXTURE_2D_ARRAY || type == love::graphics::TEXTURE_VOLUME) {
    rt.slice = check_int_field(fields, layer, "layer") - 1;
  } else if (type == love::graphics::TEXTURE_CUBE) {
    rt.slice = check_int_field(fields, face, "face") - 1;
  }
  rt.mipmap = (ruby::is_numeric(element(fields, mipmap)) ? integer_at(fields, mipmap) : 1) - 1;
  return rt;
}

// w_setCanvas with a table of targets and its options
// (wrap_Graphics.cpp:283-335), as Lota::Graphics.set_canvas passes them in
// one Array: the targets, an Array of 2D textures, or of targets as
// render_target_of reads them; depthstencil, a texture, a target, or a
// boolean that asks for a temporary depth and stencil buffer; and depth
// and stencil, each of which asks for a temporary buffer of its own when
// depthstencil does not give one.
void set_canvas_with_options(Rice::Array arguments) {
  const Rice::Array moved = std::move(arguments);
  const std::vector<Rice::Object> given = ruby::elements(moved);
  const Rice::Object depthstencil = element(given, 1);
  Graphics &instance = graphics();
  Graphics::RenderTargets targets;

  const std::vector<Rice::Object> colors = array_elements(element(given, 0));
  const bool table_of_tables = !colors.empty() && ruby::is_array(colors.front());
  for (const Rice::Object &color : colors) {
    if (table_of_tables) {
      targets.colors.push_back(render_target_of(color));
      continue;
    }
    targets.colors.emplace_back(texture_at(color), 0);
    if (targets.colors.back().texture->getTextureType() != love::graphics::TEXTURE_2D) {
      throw love::Exception("Non-2D textures must use the table-of-tables variant of setCanvas.");
    }
  }

  const love::uint32 tempdepthflag = Graphics::TEMPORARY_RT_DEPTH;
  const love::uint32 tempstencilflag = Graphics::TEMPORARY_RT_STENCIL;

  if (ruby::is_array(depthstencil)) {
    targets.depthStencil = render_target_of(depthstencil);
  } else if (ruby::is_boolean(depthstencil)) {
    targets.temporaryRTFlags |= ruby::is_true(depthstencil) ? (tempdepthflag | tempstencilflag) : 0;
  } else if (!ruby::is_nil(depthstencil)) {
    targets.depthStencil.texture = texture_at(depthstencil);
  }

  if (targets.depthStencil.texture == nullptr && (targets.temporaryRTFlags & tempdepthflag) == 0) {
    targets.temporaryRTFlags |= ruby::truthy(element(given, 2)) ? tempdepthflag : 0;
  }

  if (targets.depthStencil.texture == nullptr &&
      (targets.temporaryRTFlags & tempstencilflag) == 0) {
    targets.temporaryRTFlags |= ruby::truthy(element(given, 3)) ? tempstencilflag : 0;
  }

  set_render_targets(instance, targets);
}

// pushRenderTarget (wrap_Graphics.cpp:380-398): a target as an Array of
// its texture, its layer for an array or volume texture, its face for a
// cube, each nil otherwise, and its mipmap, each counting from 1, as
// render_target_of reads one.
Rice::Array render_target_fields(const Graphics::RenderTarget &rt) {
  const love::graphics::TextureType type = rt.texture->getTextureType();
  const bool layered =
      type == love::graphics::TEXTURE_2D_ARRAY || type == love::graphics::TEXTURE_VOLUME;
  const bool cube = type == love::graphics::TEXTURE_CUBE;
  Rice::Array fields;
  fields.push(rt.texture, false);
  for (const bool named : {layered, cube}) {
    if (named) {
      fields.push(rt.slice + 1, false);
    } else {
      fields.push(ruby::nil(), false);
    }
  }
  fields.push(rt.mipmap + 1, false);
  return fields;
}

// w_getCanvas (wrap_Graphics.cpp:400-437): whether LÖVE returns the
// targets as a table, which it does for a depth and stencil texture, a
// mipmap but the first, or a texture that is not 2D; the targets, each as
// render_target_fields gives it; and the depth and stencil texture's, or
// nil. Lota::Graphics.canvas returns them as LÖVE's values.
Rice::Array canvas() {
  const Graphics::RenderTargets targets = graphics().getRenderTargets();
  bool tables = targets.depthStencil.texture != nullptr;
  Rice::Array colors;
  for (const Graphics::RenderTarget &rt : targets.colors) {
    tables = tables || rt.mipmap != 0 || rt.texture->getTextureType() != love::graphics::TEXTURE_2D;
    colors.push(render_target_fields(rt), false);
  }
  Rice::Array result;
  result.push(tables, false);
  result.push(colors, false);
  result.push(targets.depthStencil.texture != nullptr
                  ? Rice::Object(render_target_fields(targets.depthStencil))
                  : ruby::nil(),
              false);
  return result;
}

// SPDX-SnippetEnd

} // namespace

void define_texture(const Rice::Module &native) {
  // The settings luax_checktexturesettings reads from its table
  // (wrap_Graphics.cpp:759-871) start from Texture::Settings' own
  // defaults (graphics/Texture.h:187-204).
  Rice::define_class_under<Texture::Settings>(native, "TextureSettings")
      .define_constructor(Rice::Constructor<Texture::Settings>())
      .define_singleton_function("check_name", &check_setting_name, Rice::Arg("name"))
      .define_attr("width", &Texture::Settings::width)
      .define_attr("height", &Texture::Settings::height)
      .define_attr("layers", &Texture::Settings::layers)
      .define_attr("mipmapcount", &Texture::Settings::mipmapCount)
      .define_attr("linear", &Texture::Settings::linear)
      .define_attr("msaa", &Texture::Settings::msaa)
      .define_attr("canvas", &Texture::Settings::renderTarget)
      .define_attr("computewrite", &Texture::Settings::computeWrite)
      .define_attr("debugname", &Texture::Settings::debugName)
      .define_method("dpiscale", &dpi_scale)
      .define_method("dpiscale=", &set_dpi_scale, Rice::Arg("dpiscale"))
      .define_method("readable=", &set_readable, Rice::Arg("readable"))
      .define_method("set_format", &set_format, Rice::Arg("str"))
      .define_method("set_type", &set_type, Rice::Arg("str"))
      .define_method("type", &type)
      .define_method("set_mipmaps", &set_mipmaps, Rice::Arg("str"))
      .define_method("add_view_format", &add_view_format, Rice::Arg("str"));

  Rice::define_class_under<Texture>(native, "Texture")
      .define_method("width", &texture_width, Rice::Arg("mipmap") = std::optional<int>())
      .define_method("height", &texture_height, Rice::Arg("mipmap") = std::optional<int>())
      .define_method("depth", &texture_depth, Rice::Arg("mipmap") = std::optional<int>())
      .define_method("pixel_width", &texture_pixel_width,
                     Rice::Arg("mipmap") = std::optional<int>())
      .define_method("pixel_height", &texture_pixel_height,
                     Rice::Arg("mipmap") = std::optional<int>())
      .define_method("replace_pixels", &texture_replace_pixels, Rice::Arg("imagedata"),
                     Rice::Arg("arguments"));

  Rice::define_module_under(native, "Graphics")
      .define_singleton_function("canvas_size", &canvas_size)
      .define_singleton_function("new_canvas", &new_canvas, Rice::Arg("settings"),
                                 Rice::Arg("dpiscaleset"), Rice::Return().takeOwnership())
      .define_singleton_function("new_empty_texture", &new_empty_texture, Rice::Arg("settings"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_texture", &new_texture, Rice::Arg("settings"),
                                 Rice::Arg("dpiscaleset"), Rice::Arg("images"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_cube_texture", &new_cube_texture, Rice::Arg("settings"),
                                 Rice::Arg("dpiscaleset"), Rice::Arg("images"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_array_texture", &new_array_texture, Rice::Arg("settings"),
                                 Rice::Arg("dpiscaleset"), Rice::Arg("images"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_volume_texture", &new_volume_texture, Rice::Arg("settings"),
                                 Rice::Arg("dpiscaleset"), Rice::Arg("images"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("readback_texture", &readback_texture, Rice::Arg("texture"),
                                 Rice::Arg("arguments"), Rice::Return().takeOwnership())
      .define_singleton_function("reset_canvas", &reset_canvas)
      .define_singleton_function("canvas", &canvas)
      .define_singleton_function("set_canvas", &set_canvas, Rice::Arg("arguments"))
      .define_singleton_function("set_canvas_with_options", &set_canvas_with_options,
                                 Rice::Arg("arguments"));
}

} // namespace lota::native
