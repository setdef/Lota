// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/image.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/luajit.hpp"
#include "native/ruby.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/floattypes.h"
#include "common/pixelformat.h"
#include "image/Image.h"
#include "image/ImageData.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::PixelFormat;
using love::image::Image;
using love::image::ImageData;

namespace {

// luaopen_love_image (vendor/love/src/modules/image/wrap_Image.cpp:
// 161-178) creates the module once; it then lives as long as the process,
// as LÖVE's lives until the game quits.
void open() { open_module<Image, Image>(love::Module::M_IMAGE); }

// Whether the module is open, as a game asks with "if love.image then".
bool is_open() { return love::Module::getInstance<Image>(love::Module::M_IMAGE) != nullptr; }

Image *image() {
  auto *instance = love::Module::getInstance<Image>(love::Module::M_IMAGE);
  if (instance == nullptr) {
    throw love::Exception("Lota::Image is not open.");
  }
  return instance;
}

} // namespace

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++ and Lua, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

namespace {

// w_newImageData from encoded Data (wrap_Image.cpp:84-96): decodes it with
// the first of the module's format handlers that can. Its one reference
// goes to the Ruby wrapper.
ImageData *new_image_data(love::Data *data) { return image()->newImageData(data); }

// w_newImageData with a width and a height (wrap_Image.cpp:35-82): blank
// pixels of +format+, rgba8 when it is nil, or a copy of +bytes+, which
// must be as many as the pixels take. Its one reference goes to the Ruby
// wrapper.
ImageData *new_sized_image_data(int w, int h, std::optional<std::string> fstr,
                                std::optional<std::string> bytes) {
  if (w <= 0 || h <= 0) {
    throw love::Exception("Invalid image size.");
  }

  PixelFormat format = love::PIXELFORMAT_RGBA8_UNORM;

  if (fstr.has_value() && !love::getConstant(fstr->c_str(), format)) {
    raise_enum_error("pixel format", *fstr);
  }

  ImageData *t = image()->newImageData(w, h, format);

  if (bytes.has_value()) {
    if (bytes->size() != t->getSize()) {
      t->release();
      throw love::Exception(
          "The size of the raw byte string must match the ImageData's actual size in bytes.");
    }

    std::memcpy(t->getData(), bytes->data(), t->getSize());
  }

  return t;
}

// What follows is the FFI code LÖVE runs under LuaJIT in place of
// ImageData's C++ wrap functions (vendor/love/src/modules/image/
// wrap_ImageData.lua), which reads and writes each pixel's components in
// double precision, as Lua numbers, where the C++ converts them through
// single-precision floats (ImageData::getPixel's Colorf).

// A pixel's components as the Lua code passes them: red, green, blue, and
// alpha, each a Lua number.
using Components = std::array<double, 4>;

// The components a pixel is set to, any of which the caller may leave out
// (nil in Lua), as mapPixel's function may return fewer than four.
struct Given {
  std::optional<double> r;
  std::optional<double> g;
  std::optional<double> b;
  std::optional<double> a;
};

// A component a format's fromlua uses, which Lua cannot leave out: Lua's
// arithmetic on nil raises, and LuaJIT cannot store nil in a number field.
double need(const std::optional<double> &component) {
  if (!component.has_value()) {
    ruby::raise_type_error("a pixel's color component is nil, which is not a number");
  }
  return *component;
}

// clamp01 (wrap_ImageData.lua:37-39): math.min(math.max(x, 0), 1).
double clamp01(double x) {
  const double low = (0 > x) ? 0 : x;
  return (low > 1) ? 1 : low;
}

// The value of type T at pixel +index+ of +bytes+, in a format whose
// pixels are +count+ such values, the C struct the Lua casts the pixels to
// (lines 79-96).
template <typename T> T load(std::span<const std::byte> bytes, std::size_t offset) {
  T value{};
  std::memcpy(&value, bytes.subspan(offset * sizeof(T), sizeof(T)).data(), sizeof(T));
  return value;
}

template <typename T> void store(std::span<std::byte> bytes, std::size_t offset, T value) {
  std::memcpy(bytes.subspan(offset * sizeof(T), sizeof(T)).data(), &value, sizeof(T));
}

// One 8-bit or 16-bit unsigned normalized component, as each tolua divides
// it by its largest value and each fromlua stores
// (clamp01(x) * largest) + 0.5 through LuaJIT's conversion to a C integer.
template <typename T> double unorm_to_lua(std::span<const std::byte> bytes, std::size_t offset) {
  constexpr double largest = std::numeric_limits<T>::max();
  return load<T>(bytes, offset) / largest;
}

template <typename T>
void unorm_from_lua(std::span<std::byte> bytes, std::size_t offset, double x) {
  constexpr double largest = std::numeric_limits<T>::max();
  constexpr double half_step = 0.5;
  store<T>(bytes, offset, static_cast<T>(luajit::to_int32((clamp01(x) * largest) + half_step)));
}

// r8, rg8, rgba8, r16, rg16, and rgba16 (lines 99-158): +count+
// components of type T; a missing alpha is the largest value.
template <typename T, std::size_t count> Components unorm_tolua(std::span<const std::byte> bytes) {
  Components c{0, 0, 0, 1};
  for (std::size_t i = 0; i < count; i++) {
    c.at(i) = unorm_to_lua<T>(bytes, i);
  }
  return c;
}

template <typename T, std::size_t count>
void unorm_fromlua(std::span<std::byte> bytes, const Given &given) {
  unorm_from_lua<T>(bytes, 0, need(given.r));
  if constexpr (count > 1) {
    unorm_from_lua<T>(bytes, 1, need(given.g));
  }
  if constexpr (count > 2) {
    unorm_from_lua<T>(bytes, 2, need(given.b));
    if (given.a.has_value()) {
      unorm_from_lua<T>(bytes, 3, *given.a);
    } else {
      store<T>(bytes, 3, std::numeric_limits<T>::max());
    }
  }
}

// r16f, rg16f, and rgba16f (lines 159-187): half floats, which the Lua
// converts with LÖVE's float16to32 and float32to16, passing each Lua
// number as the C function's float; a missing alpha is 1.0.
template <std::size_t count> Components half_tolua(std::span<const std::byte> bytes) {
  Components c{0, 0, 0, 1};
  for (std::size_t i = 0; i < count; i++) {
    c.at(i) = love::float16to32(load<love::float16>(bytes, i));
  }
  return c;
}

template <std::size_t count> void half_fromlua(std::span<std::byte> bytes, const Given &given) {
  const auto half = [&bytes](std::size_t i, double x) {
    store<love::float16>(bytes, i, love::float32to16(static_cast<float>(x)));
  };
  half(0, need(given.r));
  if constexpr (count > 1) {
    half(1, need(given.g));
  }
  if constexpr (count > 2) {
    half(2, need(given.b));
    half(3, given.a.value_or(1.0));
  }
}

// r32f, rg32f, and rgba32f (lines 188-216): floats, which a Lua number is
// stored in as LuaJIT converts a double to a float; a missing alpha is
// 1.0.
template <std::size_t count> Components float_tolua(std::span<const std::byte> bytes) {
  Components c{0, 0, 0, 1};
  for (std::size_t i = 0; i < count; i++) {
    c.at(i) = load<float>(bytes, i);
  }
  return c;
}

template <std::size_t count> void float_fromlua(std::span<std::byte> bytes, const Given &given) {
  store<float>(bytes, 0, static_cast<float>(need(given.r)));
  if constexpr (count > 1) {
    store<float>(bytes, 1, static_cast<float>(need(given.g)));
  }
  if constexpr (count > 2) {
    store<float>(bytes, 2, static_cast<float>(need(given.b)));
    store<float>(bytes, 3, static_cast<float>(given.a.value_or(1.0)));
  }
}

// LuaJIT's bit library on Lua numbers (bit.band, bit.bor, bit.lshift,
// bit.rshift), each of which takes its operands through bit.tobit and
// returns a signed 32-bit result as a Lua number.
double band(double x, std::uint32_t mask) {
  return static_cast<std::int32_t>(static_cast<std::uint32_t>(luajit::to_bit(x)) & mask);
}

double lshift(double x, unsigned n) {
  return static_cast<std::int32_t>(static_cast<std::uint32_t>(luajit::to_bit(x)) << n);
}

double rshift(double x, unsigned n) {
  return static_cast<std::int32_t>(static_cast<std::uint32_t>(luajit::to_bit(x)) >> n);
}

double bor(std::initializer_list<double> values) {
  std::uint32_t bits = 0;
  for (const double value : values) {
    bits |= static_cast<std::uint32_t>(luajit::to_bit(value));
  }
  return static_cast<std::int32_t>(bits);
}

// Field widths and shifts of the packed formats, as the Lua masks them.
constexpr std::uint32_t bits4 = 0xF;
constexpr std::uint32_t bits5 = 0x1F;
constexpr std::uint32_t bits6 = 0x3F;
constexpr std::uint32_t bits10 = 0x3FF;
constexpr std::uint32_t bits11 = 0x7FF;

// rgba4 (lines 217-238): LSB to MSB, alpha, blue, green, red.
Components rgba4_tolua(std::span<const std::byte> bytes) {
  const double rgba = load<std::uint16_t>(bytes, 0);
  const double a = band(rgba, bits4) / bits4;
  const double b = band(rshift(rgba, 4), bits4) / bits4;
  const double g = band(rshift(rgba, 8), bits4) / bits4;
  const double r = rshift(rgba, 12) / bits4;
  return {r, g, b, a};
}

void rgba4_fromlua(std::span<std::byte> bytes, const Given &given) {
  // bit functions round internally.
  const double r = clamp01(need(given.r)) * bits4;
  const double g = clamp01(need(given.g)) * bits4;
  const double b = clamp01(need(given.b)) * bits4;
  const double a = given.a.has_value() ? clamp01(*given.a) * bits4 : bits4;
  const double rgba = bor({lshift(r, 12), lshift(g, 8), lshift(b, 4), a});
  store<std::uint16_t>(bytes, 0, static_cast<std::uint16_t>(luajit::to_int32(rgba)));
}

// rgb5a1 (lines 239-260): LSB to MSB, alpha, blue, green, red; the alpha
// is 0 or 1 and read as it is, not divided.
Components rgb5a1_tolua(std::span<const std::byte> bytes) {
  const double rgba = load<std::uint16_t>(bytes, 0);
  const double r = band(rshift(rgba, 11), bits5) / bits5;
  const double g = band(rshift(rgba, 6), bits5) / bits5;
  const double b = band(rshift(rgba, 1), bits5) / bits5;
  const double a = band(rgba, 0x1);
  return {r, g, b, a};
}

void rgb5a1_fromlua(std::span<std::byte> bytes, const Given &given) {
  // bit functions round internally.
  const double r = clamp01(need(given.r)) * bits5;
  const double g = clamp01(need(given.g)) * bits5;
  const double b = clamp01(need(given.b)) * bits5;
  const double a = given.a.has_value() ? clamp01(*given.a) : 1;
  const double rgba = bor({lshift(r, 11), lshift(g, 6), lshift(b, 1), a});
  store<std::uint16_t>(bytes, 0, static_cast<std::uint16_t>(luajit::to_int32(rgba)));
}

// rgb565 (lines 261-279): LSB to MSB, blue, green, red; alpha is 1.
Components rgb565_tolua(std::span<const std::byte> bytes) {
  const double rgb = load<std::uint16_t>(bytes, 0);
  const double r = band(rshift(rgb, 11), bits5) / bits5;
  const double g = band(rshift(rgb, 5), bits6) / bits6;
  const double b = band(rgb, bits5) / bits5;
  return {r, g, b, 1};
}

void rgb565_fromlua(std::span<std::byte> bytes, const Given &given) {
  // bit functions round internally.
  const double r = clamp01(need(given.r)) * bits5;
  const double g = clamp01(need(given.g)) * bits6;
  const double b = clamp01(need(given.b)) * bits5;
  const double rgb = bor({lshift(r, 11), lshift(g, 5), b});
  store<std::uint16_t>(bytes, 0, static_cast<std::uint16_t>(luajit::to_int32(rgb)));
}

// rgb10a2 (lines 280-301): LSB to MSB, red, green, blue, alpha. The word
// the bit library makes is signed, and one whose top bit is set, as an
// alpha of 2 or 3 sets it, is negative, which LuaJIT stores in the
// unsigned field as 0 on Apple silicon (luajit::to_uint32).
Components rgb10a2_tolua(std::span<const std::byte> bytes) {
  const double rgba = load<std::uint32_t>(bytes, 0);
  const double r = band(rgba, bits10) / bits10;
  const double g = band(rshift(rgba, 10), bits10) / bits10;
  const double b = band(rshift(rgba, 20), bits10) / bits10;
  const double a = rshift(rgba, 30) / 0x3;
  return {r, g, b, a};
}

void rgb10a2_fromlua(std::span<std::byte> bytes, const Given &given) {
  // bit functions round internally.
  const double r = clamp01(need(given.r)) * bits10;
  const double g = clamp01(need(given.g)) * bits10;
  const double b = clamp01(need(given.b)) * bits10;
  const double a = given.a.has_value() ? clamp01(*given.a) * 0x3 : 0x3;
  const double rgba = bor({r, lshift(g, 10), lshift(b, 20), lshift(a, 30)});
  store<std::uint32_t>(bytes, 0, luajit::to_uint32(rgba));
}

// rg11b10f (lines 302-321): LSB to MSB, red, green, blue, as LÖVE's
// float11to32, float32to11, float10to32, and float32to10 convert them;
// alpha is 1. A word whose top bit is set is stored as rgb10a2's is.
Components rg11b10f_tolua(std::span<const std::byte> bytes) {
  const double rgb = load<std::uint32_t>(bytes, 0);
  const auto eleven = [](double bits) {
    return static_cast<double>(
        love::float11to32(static_cast<love::float11>(luajit::to_int32(bits))));
  };
  const double r = eleven(band(rgb, bits11));
  const double g = eleven(band(rshift(rgb, 11), bits11));
  const double b = love::float10to32(
      static_cast<love::float10>(luajit::to_int32(band(rshift(rgb, 22), bits10))));
  return {r, g, b, 1};
}

void rg11b10f_fromlua(std::span<std::byte> bytes, const Given &given) {
  const double r = love::float32to11(static_cast<float>(need(given.r)));
  const double g = love::float32to11(static_cast<float>(need(given.g)));
  const double b = love::float32to10(static_cast<float>(need(given.b)));
  const double rgb = bor({r, lshift(g, 11), lshift(b, 22)});
  store<std::uint32_t>(bytes, 0, luajit::to_uint32(rgb));
}

// The Lua's conversions table (lines 93-322), by LÖVE's pixel format.
struct Conversion {
  PixelFormat format;
  Components (*tolua)(std::span<const std::byte>);
  void (*fromlua)(std::span<std::byte>, const Given &);
};

constexpr std::array conversions = {
    Conversion{
        .format = love::PIXELFORMAT_R8_UNORM,
        .tolua = unorm_tolua<std::uint8_t, 1>,
        .fromlua = unorm_fromlua<std::uint8_t, 1>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RG8_UNORM,
        .tolua = unorm_tolua<std::uint8_t, 2>,
        .fromlua = unorm_fromlua<std::uint8_t, 2>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGBA8_UNORM,
        .tolua = unorm_tolua<std::uint8_t, 4>,
        .fromlua = unorm_fromlua<std::uint8_t, 4>,
    },
    Conversion{
        .format = love::PIXELFORMAT_R16_UNORM,
        .tolua = unorm_tolua<std::uint16_t, 1>,
        .fromlua = unorm_fromlua<std::uint16_t, 1>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RG16_UNORM,
        .tolua = unorm_tolua<std::uint16_t, 2>,
        .fromlua = unorm_fromlua<std::uint16_t, 2>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGBA16_UNORM,
        .tolua = unorm_tolua<std::uint16_t, 4>,
        .fromlua = unorm_fromlua<std::uint16_t, 4>,
    },
    Conversion{
        .format = love::PIXELFORMAT_R16_FLOAT,
        .tolua = half_tolua<1>,
        .fromlua = half_fromlua<1>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RG16_FLOAT,
        .tolua = half_tolua<2>,
        .fromlua = half_fromlua<2>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGBA16_FLOAT,
        .tolua = half_tolua<4>,
        .fromlua = half_fromlua<4>,
    },
    Conversion{
        .format = love::PIXELFORMAT_R32_FLOAT,
        .tolua = float_tolua<1>,
        .fromlua = float_fromlua<1>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RG32_FLOAT,
        .tolua = float_tolua<2>,
        .fromlua = float_fromlua<2>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGBA32_FLOAT,
        .tolua = float_tolua<4>,
        .fromlua = float_fromlua<4>,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGBA4_UNORM,
        .tolua = rgba4_tolua,
        .fromlua = rgba4_fromlua,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGB5A1_UNORM,
        .tolua = rgb5a1_tolua,
        .fromlua = rgb5a1_fromlua,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGB565_UNORM,
        .tolua = rgb565_tolua,
        .fromlua = rgb565_fromlua,
    },
    Conversion{
        .format = love::PIXELFORMAT_RGB10A2_UNORM,
        .tolua = rgb10a2_tolua,
        .fromlua = rgb10a2_fromlua,
    },
    Conversion{
        .format = love::PIXELFORMAT_RG11B10_FLOAT,
        .tolua = rg11b10f_tolua,
        .fromlua = rg11b10f_fromlua,
    },
};

// The object cache's entry for +data+ (lines 330-352): its format's
// conversion, or an error naming +function+ ("ImageData:getPixel") and
// the format, as the Lua raises where its cache has no pointer.
const Conversion &conversion(const ImageData &data, const char *function) {
  const PixelFormat format = data.getFormat();
  const auto *found = std::ranges::find(conversions, format, &Conversion::format);
  if (found == conversions.end()) {
    const char *name = "";
    love::getConstant(format, name);
    throw love::Exception("%s does not currently support the %s pixel format.", function, name);
  }
  return *found;
}

// inside (lines 33-35), for the Lua numbers the Lua passes it.
bool inside(double x, double y, double w, double h) { return x >= 0 && x < w && y >= 0 && y < h; }

// The bytes of pixel +x+, +y+ of +data+, whose pixels the Lua indexes as
// pixels[y * width + x].
std::span<std::byte> pixel_at(const ImageData &data, double x, double y) {
  const std::span<std::byte> bytes(static_cast<std::byte *>(data.getData()), data.getSize());
  const std::size_t size = data.getPixelSize();
  const auto index = static_cast<std::size_t>((y * data.getWidth()) + x);
  return bytes.subspan(index * size, size);
}

Rice::Array to_array(const Components &c) {
  Rice::Array results;
  for (const double component : c) {
    results.push(component, false);
  }
  return results;
}

// w_ImageData_clone (wrap_ImageData.cpp:47-54), the C++ LÖVE runs: a new
// ImageData with a copy of the pixels. Its one reference goes to the Ruby
// wrapper.
ImageData *clone(const ImageData &data) { return data.clone(); }

// ImageData:getWidth and getHeight (lines 436-442): the object cache's,
// which it read from ImageData:getDimensions, the C++'s.
int width(const ImageData &data) { return data.getWidth(); }

int height(const ImageData &data) { return data.getHeight(); }

// ImageData:getPixel (lines 395-409): +x+ and +y+ rounded down, then the
// pixel's components as the format's tolua reads them.
Rice::Array get_pixel(const ImageData &data, double x, double y) {
  x = std::floor(x);
  y = std::floor(y);

  if (!inside(x, y, data.getWidth(), data.getHeight())) {
    throw love::Exception("Attempt to get out-of-range pixel!");
  }

  const Conversion &convert = conversion(data, "ImageData:getPixel");
  return to_array(convert.tolua(pixel_at(data, x, y)));
}

// A color component of ImageData:setPixel's, which must be a number, but
// alpha, which may be nil (lines 423-426).
std::optional<double> component(const Rice::Object &value, const char *name, bool optional) {
  if (optional && ruby::is_nil(value)) {
    return std::nullopt;
  }
  if (!ruby::is_numeric(value)) {
    ruby::raise_type_error(
        translate_love_names(std::string("bad ") + name +
                             " color component argument to ImageData:setPixel (expected number)"));
  }
  return Rice::detail::From_Ruby<double>().convert(value.value());
}

// The element at +index+ of +values+, or nil past their end.
Rice::Object element(const std::vector<Rice::Object> &values, std::size_t index) {
  return (index < values.size()) ? values.at(index) : ruby::nil();
}

// ImageData:setPixel (lines 411-434), from the Array
// Lota::Image::ImageData#pixel= is given: the position, then red, green,
// blue, and an optional alpha, or an Array of them, as the Lua takes a
// table. The position is rounded down, as getPixel rounds it, and the
// components stored as the format's fromlua stores them.
void set_pixel(ImageData &data, Rice::Array arguments_given) {
  const Rice::Array arguments = std::move(arguments_given);
  const std::vector<Rice::Object> values = ruby::elements(arguments);
  const double x =
      std::floor(Rice::detail::From_Ruby<double>().convert(element(values, 0).value()));
  const double y =
      std::floor(Rice::detail::From_Ruby<double>().convert(element(values, 1).value()));

  std::vector<Rice::Object> components(
      values.begin() + std::min<std::ptrdiff_t>(2, std::ssize(values)), values.end());
  if (!components.empty() && ruby::is_array(components.front())) {
    components = ruby::elements(Rice::Array(components.front().value()));
  }

  const Given given{
      .r = component(element(components, 0), "red", false),
      .g = component(element(components, 1), "green", false),
      .b = component(element(components, 2), "blue", false),
      .a = component(element(components, 3), "alpha", true),
  };

  if (!inside(x, y, data.getWidth(), data.getHeight())) {
    throw love::Exception("Attempt to set out-of-range pixel!");
  }

  const Conversion &convert = conversion(data, "ImageData:setPixel");
  convert.fromlua(pixel_at(data, x, y), given);
}

// A component of what mapPixel's function returned, or none for nil.
std::optional<double> returned_number(const Rice::Object &value) {
  if (ruby::is_nil(value)) {
    return std::nullopt;
  }
  return Rice::detail::From_Ruby<double>().convert(value.value());
}

// What mapPixel's function returned, as the Lua's local r, g, b, a takes
// it: an Array's first four, or a lone value as red.
Given returned(const Rice::Object &result) {
  if (!ruby::is_array(result)) {
    return Given{
        .r = returned_number(result),
        .g = std::nullopt,
        .b = std::nullopt,
        .a = std::nullopt,
    };
  }
  const std::vector<Rice::Object> values = ruby::elements(Rice::Array(result.value()));
  return Given{
      .r = returned_number(element(values, 0)),
      .g = returned_number(element(values, 1)),
      .b = returned_number(element(values, 2)),
      .a = returned_number(element(values, 3)),
  };
}

// ImageData:mapPixel (lines 358-393): calls +block+ with each pixel's
// position, as Integers, and components in the rectangle +rectangle+ gives,
// its x, y, width, and height, each nil for the whole image's, row by row,
// and stores what it returns. The rectangle is checked before its numbers
// are rounded down, as the Lua checks it.
void map_pixels(ImageData &data, const std::vector<Rice::Object> &given,
                const Rice::Object &block) {
  if (ruby::is_nil(block)) {
    throw love::Exception("bad argument #1 to ImageData:mapPixel (expected function)");
  }
  const double idw = data.getWidth();
  const double idh = data.getHeight();
  const auto number_or = [&given](std::size_t index, double fallback) {
    const Rice::Object value = element(given, index);
    return ruby::is_nil(value) ? fallback
                               : Rice::detail::From_Ruby<double>().convert(value.value());
  };

  double ix = number_or(0, 0);
  double iy = number_or(1, 0);
  double iw = number_or(2, idw);
  double ih = number_or(3, idh);

  if (!(inside(ix, iy, idw, idh) && inside(ix + iw - 1, iy + ih - 1, idw, idh))) {
    throw love::Exception("Invalid rectangle dimensions");
  }

  const Conversion &convert = conversion(data, "ImageData:mapPixel");

  ix = std::floor(ix);
  iy = std::floor(iy);
  iw = std::floor(iw);
  ih = std::floor(ih);

  // The rounded rectangle lies inside the image, so its numbers are whole
  // and small enough to count with.
  const auto left = static_cast<long long>(ix);
  const auto top = static_cast<long long>(iy);
  const auto right = static_cast<long long>(ix + iw - 1);
  const auto bottom = static_cast<long long>(iy + ih - 1);
  for (long long y = top; y <= bottom; y++) {
    for (long long x = left; x <= right; x++) {
      const std::span<std::byte> pixel =
          pixel_at(data, static_cast<double>(x), static_cast<double>(y));
      const auto [r, g, b, a] = convert.tolua(pixel);
      const Rice::Object result = block.call("call", x, y, r, g, b, a);
      convert.fromlua(pixel, returned(result));
    }
  }
}

void map_pixel(ImageData &data, Rice::Array call_given) {
  const Rice::Array call = std::move(call_given);
  std::vector<Rice::Object> rectangle = ruby::elements(call);
  const Rice::Object block = rectangle.empty() ? ruby::nil() : rectangle.front();
  if (!rectangle.empty()) {
    rectangle.erase(rectangle.begin());
  }
  map_pixels(data, rectangle, block);
}

} // namespace

// SPDX-SnippetEnd

void define_image(const Rice::Module &native) {
  define_engine_class<ImageData, love::Data>(native, "ImageData")
      .define_method("clone", &clone, Rice::Return().takeOwnership())
      .define_method("width", &width)
      .define_method("height", &height)
      .define_method("pixel", &get_pixel, Rice::Arg("x"), Rice::Arg("y"))
      .define_method("set_pixel", &set_pixel, Rice::Arg("arguments"))
      .define_method("map_pixel", &map_pixel, Rice::Arg("call"));

  Rice::define_module_under(native, "Image")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_image_data", &new_image_data, Rice::Arg("data"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_sized_image_data", &new_sized_image_data, Rice::Arg("w"),
                                 Rice::Arg("h"), Rice::Arg("fstr") = std::optional<std::string>(),
                                 Rice::Arg("bytes") = std::optional<std::string>(),
                                 Rice::Return().takeOwnership());
}

} // namespace lota::native
