// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/math.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "common/Exception.h"
#include "common/Matrix.h"
#include "common/Module.h"
#include "common/Vector.h"
#include "math/BezierCurve.h"
#include "math/MathModule.h"
#include "math/RandomGenerator.h"
#include "math/Transform.h"

#include <array>
#include <cstddef>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::math::BezierCurve;
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

// The math module, as LÖVE's instance() macro reaches it (wrap_Math.cpp:
// 43), on any thread.
Math *instance() {
  auto *module = love::Module::getInstance<Math>(love::Module::M_MATH);
  if (module == nullptr) {
    throw love::Exception("Lota::Math is not open.");
  }
  return module;
}

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
RandomGenerator *random_generator() { return instance()->getRandomGenerator(); }

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

// The points w_newBezierCurve, w_triangulate, and w_isConvex read
// (wrap_Math.cpp:86-115, 150-179, and 220-249), from the coordinates a
// table or the arguments hold, which Lota::Math passes as one Array: an x
// and a y for each, each read as a number and stored as a float. A last x
// without its y is read as LÖVE reads it, past the end, where nil is not
// a number, so it raises TypeError.
std::vector<love::Vector2> points_of(const Rice::Array &coordinates) {
  const long top = ruby::length(coordinates);
  std::vector<love::Vector2> points;
  points.reserve(static_cast<std::size_t>(top / 2));
  for (long i = 0; i < top; i += 2) {
    const double x = Rice::detail::From_Ruby<double>().convert(ruby::entry(coordinates, i).value());
    const double y =
        Rice::detail::From_Ruby<double>().convert(ruby::entry(coordinates, i + 1).value());
    points.emplace_back(static_cast<float>(x), static_cast<float>(y));
  }
  return points;
}

// The coordinates of +points+, x then y for each, as w_BezierCurve_render
// and w_triangulate push them, each a float pushed as a lua_Number.
Rice::Array coordinates_of(const std::vector<love::Vector2> &points) {
  Rice::Array coordinates;
  for (const love::Vector2 &point : points) {
    coordinates.push(static_cast<double>(point.x), false);
    coordinates.push(static_cast<double>(point.y), false);
  }
  return coordinates;
}

// w_newBezierCurve (wrap_Math.cpp:84-121).
BezierCurve *new_bezier_curve(Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  return instance()->newBezierCurve(points_of(coordinates));
}

// w_triangulate (wrap_Math.cpp:148-216): the triangles that fill the
// polygon, each its three corners' six coordinates, in an Array of them.
Rice::Array triangulate(Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  const std::vector<love::Vector2> vertices = points_of(coordinates);
  if (vertices.size() < 3) {
    throw love::Exception("Need at least 3 vertices to triangulate (got %d).",
                          static_cast<int>(vertices.size()));
  }
  std::vector<love::math::Triangle> triangles;
  if (vertices.size() == 3) {
    triangles.emplace_back(vertices.at(0), vertices.at(1), vertices.at(2));
  } else {
    triangles = love::math::triangulate(vertices);
  }
  Rice::Array results;
  for (const love::math::Triangle &tri : triangles) {
    results.push(coordinates_of({tri.a, tri.b, tri.c}), false);
  }
  return results;
}

// w_isConvex (wrap_Math.cpp:218-253).
bool is_convex(Rice::Array coordinates_given) {
  const Rice::Array coordinates = std::move(coordinates_given);
  return love::math::isConvex(points_of(coordinates));
}

// The C function LÖVE's FFI code in wrap_Math.lua calls for
// love.math.gammaToLinear and linearToGamma (ffifuncs, wrap_Math.cpp:
// 427-441, called at wrap_Math.lua:153-183): the FFI converts the Lua
// number to the float the function takes, and the float it returns back
// to a Lua number.
double gamma_to_linear(double c) {
  return static_cast<double>(love::math::gammaToLinear(static_cast<float>(c)));
}

double linear_to_gamma(double c) {
  return static_cast<double>(love::math::linearToGamma(static_cast<float>(c)));
}

// The noise functions wrap_Math.lua's FFI code calls (ffifuncs,
// wrap_Math.cpp:427-441, called at wrap_Math.lua:115-151), by how many
// dimensions they take: MathModule.h's, each over the double the FFI
// passes.
double simplex_noise1(double x) { return love::math::simplexNoise1(x); }
double simplex_noise2(double x, double y) { return love::math::simplexNoise2(x, y); }
double simplex_noise3(double x, double y, double z) { return love::math::simplexNoise3(x, y, z); }
double simplex_noise4(double x, double y, double z, double w) {
  return love::math::simplexNoise4(x, y, z, w);
}
double perlin_noise1(double x) { return love::math::perlinNoise1(x); }
double perlin_noise2(double x, double y) { return love::math::perlinNoise2(x, y); }
double perlin_noise3(double x, double y, double z) { return love::math::perlinNoise3(x, y, z); }
double perlin_noise4(double x, double y, double z, double w) {
  return love::math::perlinNoise4(x, y, z, w);
}

// w_BezierCurve_getControlPoint (wrap_BezierCurve.cpp:52-67): the point at
// +idx+, counted from 1, as an x and a y, each a float pushed as a
// lua_Number. LÖVE passes 0 and negative indices on as they are.
Rice::Array bezier_control_point(const BezierCurve &curve, int idx) {
  if (idx > 0) {
    idx--;
  }
  const love::Vector2 &v = curve.getControlPoint(idx);
  Rice::Array results;
  results.push(static_cast<double>(v.x), false);
  results.push(static_cast<double>(v.y), false);
  return results;
}

// w_BezierCurve_render (wrap_BezierCurve.cpp:174-192): the points the
// curve passes through, at 2^+accuracy+ steps, as one Array of their
// coordinates, as LÖVE fills one table with them.
Rice::Array bezier_render(const BezierCurve &curve, int accuracy) {
  return coordinates_of(curve.render(accuracy));
}

// w_BezierCurve_renderSegment (wrap_BezierCurve.cpp:194-214): the same,
// for the part of the curve from +start+ to +end+.
Rice::Array bezier_render_segment(const BezierCurve &curve, double start, double end,
                                  int accuracy) {
  return coordinates_of(curve.renderSegment(start, end, accuracy));
}

// SPDX-SnippetEnd

} // namespace

void define_math(const Rice::Module &native) {
  // render's default accuracy, LÖVE's luaL_optinteger default
  // (wrap_BezierCurve.cpp:177 and 199).
  constexpr int render_accuracy = 5;
  Rice::define_module_under(native, "Math")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("random_generator", &random_generator)
      .define_singleton_function("new_bezier_curve", &new_bezier_curve, Rice::Arg("coordinates"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("triangulate", &triangulate, Rice::Arg("coordinates"))
      .define_singleton_function("convex?", &is_convex, Rice::Arg("coordinates"))
      .define_singleton_function("gamma_to_linear", &gamma_to_linear, Rice::Arg("c"))
      .define_singleton_function("linear_to_gamma", &linear_to_gamma, Rice::Arg("c"))
      .define_singleton_function("simplex_noise1", &simplex_noise1, Rice::Arg("x"))
      .define_singleton_function("simplex_noise2", &simplex_noise2, Rice::Arg("x"), Rice::Arg("y"))
      .define_singleton_function("simplex_noise3", &simplex_noise3, Rice::Arg("x"), Rice::Arg("y"),
                                 Rice::Arg("z"))
      .define_singleton_function("simplex_noise4", &simplex_noise4, Rice::Arg("x"), Rice::Arg("y"),
                                 Rice::Arg("z"), Rice::Arg("w"))
      .define_singleton_function("perlin_noise1", &perlin_noise1, Rice::Arg("x"))
      .define_singleton_function("perlin_noise2", &perlin_noise2, Rice::Arg("x"), Rice::Arg("y"))
      .define_singleton_function("perlin_noise3", &perlin_noise3, Rice::Arg("x"), Rice::Arg("y"),
                                 Rice::Arg("z"))
      .define_singleton_function("perlin_noise4", &perlin_noise4, Rice::Arg("x"), Rice::Arg("y"),
                                 Rice::Arg("z"), Rice::Arg("w"));
  // Its other methods are generated (ext/lota/native/generated/math.cpp).
  define_engine_class<BezierCurve>(native, "BezierCurve")
      .define_method("control_point", &bezier_control_point, Rice::Arg("idx"))
      .define_method("render", &bezier_render, Rice::Arg("accuracy") = render_accuracy)
      .define_method("render_segment", &bezier_render_segment, Rice::Arg("start"), Rice::Arg("end"),
                     Rice::Arg("accuracy") = render_accuracy);
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
