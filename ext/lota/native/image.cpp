// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/image.hpp"

#include "native/binding.hpp"

#include "common/Color.h"
#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "image/Image.h"
#include "image/ImageData.h"

namespace lota::native {

using love::image::Image;
using love::image::ImageData;

namespace {

// luaopen_love_image (vendor/love/src/modules/image/wrap_Image.cpp:
// 161-178) creates the module once; it then lives as long as the process,
// as LÖVE's lives until the game quits.
void open() { open_module<Image, Image>(love::Module::M_IMAGE); }

// Whether the module is open, as a game asks with "if love.image then".
bool is_open() { return love::Module::getInstance<Image>(love::Module::M_IMAGE) != nullptr; }

// w_newImageData from encoded Data (wrap_Image.cpp:84-96): decodes it with
// the first of the module's format handlers that can. Its one reference
// goes to the Ruby wrapper.
ImageData *new_image_data(love::Data *data) {
  auto *instance = love::Module::getInstance<Image>(love::Module::M_IMAGE);
  if (instance == nullptr) {
    throw love::Exception("Lota::Image is not open.");
  }
  return instance->newImageData(data);
}

// w_ImageData_getPixel (wrap_ImageData.cpp:104-118): the pixel's red,
// green, blue, and alpha, each widened from float as Lua's numbers are.
Rice::Array pixel(const ImageData &image_data, int x, int y) {
  const love::Colorf color = image_data.getPixel(x, y);
  Rice::Array components;
  components.push(static_cast<double>(color.r), false);
  components.push(static_cast<double>(color.g), false);
  components.push(static_cast<double>(color.b), false);
  components.push(static_cast<double>(color.a), false);
  return components;
}

} // namespace

void define_image(const Rice::Module &native) {
  Rice::define_class_under<ImageData>(native, "ImageData")
      .define_method("width", &ImageData::getWidth)
      .define_method("height", &ImageData::getHeight)
      .define_method("pixel", &pixel, Rice::Arg("x"), Rice::Arg("y"));

  Rice::define_module_under(native, "Image")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_image_data", &new_image_data, Rice::Arg("data"),
                                 Rice::Return().takeOwnership());
}

} // namespace lota::native
