// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/particle_system.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "common/Color.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Vector.h"
#include "common/int.h"
#include "graphics/Graphics.h"
#include "graphics/ParticleSystem.h"
#include "graphics/Quad.h"
#include "graphics/Texture.h"

#include <cstddef>
#include <optional>
#include <utility>
#include <vector>

namespace lota::native {

using love::graphics::Graphics;
using love::graphics::ParticleSystem;
using love::graphics::Quad;
using love::graphics::Texture;

namespace {

constexpr const char *MODULE = "Lota::Graphics";

// The most sizes or colors a particle system holds (wrap_ParticleSystem.cpp:
// 371 and 498).
constexpr std::size_t MOST_STEPS = 8;

// The components of a color.
constexpr std::size_t COLOR_COMPONENTS = 4;
constexpr std::size_t COLOR_REQUIRED_COMPONENTS = 3;

using Values = std::vector<Rice::Object>;

Rice::Object at(const Values &values, std::size_t index) {
  return index < values.size() ? values.at(index) : ruby::nil();
}

[[noreturn]] void raise_expected(const Rice::Object &value, const char *expected) {
  ruby::raise_type_error("wrong argument type " + ruby::class_name(value) + " (expected " +
                         expected + ")");
}

// luaL_checknumber, of what Lota::Graphics::ParticleSystem passes.
double check_number(const Rice::Object &value) {
  if (!ruby::is_numeric(value)) {
    raise_expected(value, "Float");
  }
  return Rice::detail::From_Ruby<double>().convert(value.value());
}

// The particles a system holds when a game says no size
// (wrap_Graphics.cpp:1464).
constexpr double DEFAULT_SIZE = 1000.0;

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
//
// Ported from w_newParticleSystem (vendor/love/src/modules/graphics/
// wrap_Graphics.cpp:1462-1479) and the functions of
// wrap_ParticleSystem.cpp that read or push a number of values that
// varies, and changed to read and return Arrays where LÖVE reads and
// pushes Lua's stack.

// w_newParticleSystem (wrap_Graphics.cpp:1462-1479): a system of +size+
// particles, 1000 unless given, that shows +texture+. Its one reference
// goes to the Ruby wrapper.
ParticleSystem *new_particle_system(Texture *texture, std::optional<double> size) {
  Graphics &instance = graphics();
  if (!instance.isCreated()) {
    throw love::Exception("%s cannot function without a window.", MODULE);
  }
  const double count = size.value_or(DEFAULT_SIZE);
  if (count < 1.0 || count > ParticleSystem::MAX_PARTICLES) {
    throw love::Exception("Invalid ParticleSystem size");
  }
  return instance.newParticleSystem(texture, static_cast<int>(count));
}

// w_ParticleSystem_setBufferSize (wrap_ParticleSystem.cpp:68-77).
void particle_system_set_buffer_size(ParticleSystem &t, double size) {
  require_main_thread(MODULE);
  if (size < 1.0 || size > ParticleSystem::MAX_PARTICLES) {
    throw love::Exception("Invalid buffer size");
  }
  t.setBufferSize(static_cast<love::uint32>(size));
}

// w_ParticleSystem_getPosition (wrap_ParticleSystem.cpp:171-178).
Rice::Array particle_system_position(const ParticleSystem &t) {
  require_main_thread(MODULE);
  const love::Vector2 &pos = t.getPosition();
  Rice::Array position;
  position.push(static_cast<double>(pos.x), false);
  position.push(static_cast<double>(pos.y), false);
  return position;
}

// w_ParticleSystem_setSizes (lines 365-387): one size, or up to eight.
void particle_system_set_sizes(ParticleSystem &t, Rice::Array sizes) {
  require_main_thread(MODULE);
  const Rice::Array given = std::move(sizes);
  const Values values = ruby::elements(given);
  if (values.size() > MOST_STEPS) {
    throw love::Exception("At most eight (8) sizes may be used.");
  }
  if (values.size() <= 1) {
    t.setSize(static_cast<float>(check_number(at(values, 0))));
    return;
  }
  std::vector<float> floats;
  floats.reserve(values.size());
  for (const Rice::Object &value : values) {
    floats.push_back(static_cast<float>(check_number(value)));
  }
  t.setSizes(floats);
}

// w_ParticleSystem_getSizes (lines 389-396).
Rice::Array particle_system_sizes(const ParticleSystem &t) {
  require_main_thread(MODULE);
  Rice::Array sizes;
  for (const float size : t.getSizes()) {
    sizes.push(static_cast<double>(size), false);
  }
  return sizes;
}

// w_ParticleSystem_setColors (lines 489-549): up to eight colors, each an
// Array of red, green, blue, and optionally alpha when +tables+ is true,
// as Lua's tables are, or the numbers of every color one after another,
// four to a color, when it is false.
void particle_system_set_colors(ParticleSystem &t, Rice::Array colors, bool tables) {
  require_main_thread(MODULE);
  const Rice::Array given = std::move(colors);
  const Values values = ruby::elements(given);
  std::vector<love::Colorf> result;

  if (tables) {
    if (values.size() > MOST_STEPS) {
      throw love::Exception("At most eight (8) colors may be used.");
    }
    result.resize(values.size());
    for (std::size_t i = 0; i < values.size(); i++) {
      if (!ruby::is_array(values.at(i))) {
        raise_expected(values.at(i), "Array");
      }
      const Values components = ruby::elements(Rice::Array(values.at(i).value()));
      if (components.size() < COLOR_REQUIRED_COMPONENTS) {
        raise_argument_error("expected 4 color components");
      }
      love::Colorf &color = result.at(i);
      color.r = static_cast<float>(check_number(at(components, 0)));
      color.g = static_cast<float>(check_number(at(components, 1)));
      color.b = static_cast<float>(check_number(at(components, 2)));
      color.a = ruby::is_nil(at(components, 3))
                    ? 1.0F
                    : static_cast<float>(check_number(at(components, 3)));
    }
  } else {
    const std::size_t cargs = values.size();
    const std::size_t ncolors = (cargs + COLOR_REQUIRED_COMPONENTS) / COLOR_COMPONENTS;
    if (cargs != COLOR_REQUIRED_COMPONENTS && (cargs % COLOR_COMPONENTS != 0 || cargs == 0)) {
      throw love::Exception("Expected red, green, blue, and alpha. Only got %d of 4 components.",
                            static_cast<int>(cargs % COLOR_COMPONENTS));
    }
    if (ncolors > MOST_STEPS) {
      throw love::Exception("At most eight (8) colors may be used.");
    }
    result.resize(ncolors);
    for (std::size_t i = 0; i < ncolors; i++) {
      love::Colorf &color = result.at(i);
      color.r = static_cast<float>(check_number(at(values, (i * COLOR_COMPONENTS) + 0)));
      color.g = static_cast<float>(check_number(at(values, (i * COLOR_COMPONENTS) + 1)));
      color.b = static_cast<float>(check_number(at(values, (i * COLOR_COMPONENTS) + 2)));
      color.a = static_cast<float>(check_number(at(values, (i * COLOR_COMPONENTS) + 3)));
    }
  }
  t.setColor(result);
}

// w_ParticleSystem_getColors (lines 551-572): each color as an Array of
// red, green, blue, and alpha.
Rice::Array particle_system_colors(const ParticleSystem &t) {
  require_main_thread(MODULE);
  Rice::Array colors;
  for (const love::Colorf &color : t.getColor()) {
    Rice::Array components;
    components.push(static_cast<double>(color.r), false);
    components.push(static_cast<double>(color.g), false);
    components.push(static_cast<double>(color.b), false);
    components.push(static_cast<double>(color.a), false);
    colors.push(components, false);
  }
  return colors;
}

// w_ParticleSystem_setQuads (lines 574-602).
void particle_system_set_quads(ParticleSystem &t, Rice::Array quads) {
  require_main_thread(MODULE);
  const Rice::Array given = std::move(quads);
  std::vector<Quad *> result;
  for (const Rice::Object &value : ruby::elements(given)) {
    if (!ruby::is_kind_of(value, Rice::Data_Type<Quad>::klass())) {
      raise_expected(value, "Lota::Graphics::Quad");
    }
    result.push_back(Rice::detail::From_Ruby<Quad *>().convert(value.value()));
  }
  t.setQuads(result);
}

// w_ParticleSystem_getQuads (lines 604-618).
Rice::Array particle_system_quads(const ParticleSystem &t) {
  require_main_thread(MODULE);
  Rice::Array quads;
  for (Quad *quad : t.getQuads()) {
    quads.push(quad, false);
  }
  return quads;
}

// SPDX-SnippetEnd

} // namespace

void define_particle_system(const Rice::Module &native) {
  // Its other methods are generated (ext/lota/native/generated/graphics.cpp).
  define_engine_class<ParticleSystem>(native, "ParticleSystem")
      .define_method("set_buffer_size", &particle_system_set_buffer_size, Rice::Arg("size"))
      .define_method("position", &particle_system_position)
      .define_method("set_sizes", &particle_system_set_sizes, Rice::Arg("sizes"))
      .define_method("sizes", &particle_system_sizes)
      .define_method("set_colors", &particle_system_set_colors, Rice::Arg("colors"),
                     Rice::Arg("tables"))
      .define_method("colors", &particle_system_colors)
      .define_method("set_quads", &particle_system_set_quads, Rice::Arg("quads"))
      .define_method("quads", &particle_system_quads);

  Rice::define_module_under(native, "Graphics")
      .define_singleton_function("new_particle_system", &new_particle_system, Rice::Arg("texture"),
                                 Rice::Arg("size") = std::optional<double>(),
                                 Rice::Return().takeOwnership());
}

} // namespace lota::native
