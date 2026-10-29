// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/math.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Exception.h"
#include "common/Matrix.h"
#include "common/Module.h"
#include "common/Vector.h"
#include "math/MathModule.h"
#include "math/RandomGenerator.h"
#include "math/Transform.h"

#include <array>
#include <cstddef>
#include <optional>
#include <span>
#include <string>
#include <utility>

namespace lota::native {

using love::math::Math;
using love::math::RandomGenerator;
using love::math::Transform;

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// luax_checkmatrix with its elements as numbers (wrap_Transform.cpp:
// 106-122), after w_Transform_setMatrix's read of the layout (lines
// 236-246): LÖVE checks the layout's name first, reads each element as a
// float, and stores them column-major, so a row-major element at row r
// and column c goes to c * 4 + r.
love::Matrix4 matrix_of(const std::optional<std::string> &layout, const Rice::Array &elements) {
  Transform::MatrixLayout matrix_layout = Transform::MATRIX_ROW_MAJOR;
  if (layout.has_value() && !Transform::getConstant(layout->c_str(), matrix_layout)) {
    raise_enum_error("matrix layout", Transform::getConstants(matrix_layout), *layout);
  }
  constexpr std::size_t side = 4;
  std::array<float, side * side> values{};
  const bool columnmajor = matrix_layout == Transform::MATRIX_COLUMN_MAJOR;
  for (std::size_t column = 0; column < side; column++) {
    for (std::size_t row = 0; row < side; row++) {
      const std::size_t given = columnmajor ? (column * side) + row : (row * side) + column;
      const Rice::Object element(elements.call("fetch", static_cast<long>(given)));
      values.at((column * side) + row) =
          static_cast<float>(Rice::detail::From_Ruby<double>().convert(element.value()));
    }
  }
  return {values.data()};
}

// SPDX-SnippetEnd

namespace {

// luaopen_love_math (vendor/love/src/modules/math/wrap_Math.cpp:471-499)
// creates the math module once; it then lives as long as the process, as
// LÖVE's lives until the game quits. Its constructor seeds its random
// number generator with the time (MathModule.cpp:202-210).
void open() { open_module<Math, Math>(love::Module::M_MATH); }

// Whether the module is open, as a game asks with "if love.math".
bool is_open() { return love::Module::getInstance<Math>(love::Module::M_MATH) != nullptr; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w__getRandomGenerator (vendor/love/src/modules/math/wrap_Math.cpp:45-50):
// the module's own generator, which love.math.random and the rest of
// wrap_Math.lua draw from (lines 35-59). The module keeps its reference,
// and the Ruby wrapper retains one more, as luax_pushtype does.
RandomGenerator *random_generator() {
  auto *instance = love::Module::getInstance<Math>(love::Module::M_MATH);
  if (instance == nullptr) {
    throw love::Exception("Lota::Math is not open.");
  }
  return instance->getRandomGenerator();
}

// w_Transform_getMatrix (wrap_Transform.cpp:256-270): the sixteen
// elements, row-major, each as a lua_Number, a double.
Rice::Array transform_matrix(const Transform &transform) {
  constexpr std::size_t side = 4;
  const std::span<const float> stored(transform.getMatrix().getElements(), side * side);
  Rice::Array matrix;
  for (std::size_t row = 0; row < side; row++) {
    for (std::size_t column = 0; column < side; column++) {
      matrix.push(static_cast<double>(stored.subspan((column * side) + row).front()), false);
    }
  }
  return matrix;
}

// w_Transform_transformPoint (wrap_Transform.cpp:272-282): the point
// through the Transform, each coordinate read as a float and pushed as a
// lua_Number, a double.
Rice::Array transform_point(const Transform &transform, double x, double y) {
  const love::Vector2 p =
      transform.transformPoint(love::Vector2(static_cast<float>(x), static_cast<float>(y)));
  Rice::Array results;
  results.push(static_cast<double>(p.x), false);
  results.push(static_cast<double>(p.y), false);
  return results;
}

// w_Transform_inverseTransformPoint (wrap_Transform.cpp:284-294), as
// transform_point, through the inverse.
Rice::Array inverse_transform_point(Transform &transform, double x, double y) {
  const love::Vector2 p =
      transform.inverseTransformPoint(love::Vector2(static_cast<float>(x), static_cast<float>(y)));
  Rice::Array results;
  results.push(static_cast<double>(p.x), false);
  results.push(static_cast<double>(p.y), false);
  return results;
}

// w_Transform_setMatrix (wrap_Transform.cpp:233-254), with the layout's
// name or nil and the elements in one Array.
void transform_set_matrix(Transform &transform, const std::optional<std::string> &layout,
                          Rice::Array elements) {
  const Rice::Array given = std::move(elements);
  transform.setMatrix(matrix_of(layout, given));
}

// SPDX-SnippetEnd

} // namespace

void define_math(const Rice::Module &native) {
  Rice::define_module_under(native, "Math")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("random_generator", &random_generator);
  // Its other methods are generated (ext/lota/native/generated/math.cpp).
  define_engine_class<Transform>(native, "Transform")
      .define_method("matrix", &transform_matrix)
      .define_method("transform_point", &transform_point, Rice::Arg("x"), Rice::Arg("y"))
      .define_method("inverse_transform_point", &inverse_transform_point, Rice::Arg("x"),
                     Rice::Arg("y"))
      .define_method("set_matrix", &transform_set_matrix, Rice::Arg("layout"),
                     Rice::Arg("elements"));
}

} // namespace lota::native
