// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/shader.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Matrix.h"
#include "common/Module.h"
#include "graphics/Buffer.h"
#include "graphics/Graphics.h"
#include "graphics/Shader.h"
#include "graphics/Texture.h"
#include "graphics/vertex.h"
#include "math/MathModule.h"
#include "math/Transform.h"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::graphics::Buffer;
using love::graphics::Graphics;
using love::graphics::Shader;
using love::graphics::Texture;
using love::math::Transform;

namespace {

constexpr const char *MODULE = "Lota::Graphics";

// The size of a 4 by 4 matrix, which a Transform holds.
constexpr int MATRIX4_SIDE = 4;
constexpr std::size_t MATRIX4_ELEMENTS = 16;

// The components of a color that are gamma-corrected: red, green, and
// blue, as alpha is always linear.
constexpr int GAMMA_COMPONENTS = 3;

Graphics &graphics() {
  require_main_thread(MODULE);
  auto *instance = love::Module::getInstance<Graphics>(love::Module::M_GRAPHICS);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", MODULE);
  }
  return *instance;
}

// The values a send passes after the uniform's name, as Lua finds them on
// its stack, the first at index 0.
using Values = std::vector<Rice::Object>;

// The value at +index+, or nil past the last, as Lua reads an argument
// not given or a table's missing element.
Rice::Object at(const Values &values, int index) {
  return std::cmp_less(index, values.size()) ? values.at(static_cast<std::size_t>(index))
                                             : ruby::nil();
}

[[noreturn]] void raise_expected(const Rice::Object &value, const char *expected) {
  ruby::raise_type_error("wrong argument type " + ruby::class_name(value) + " (expected " +
                         expected + ")");
}

bool is_data(const Rice::Object &value) {
  return ruby::is_kind_of(value, Rice::Data_Type<love::Data>::klass());
}

bool is_transform(const Rice::Object &value) {
  return ruby::is_kind_of(value, Rice::Data_Type<Transform>::klass());
}

// luaL_checknumber, of what Lota::Graphics::Shader passes.
double check_number(const Rice::Object &value) {
  if (!ruby::is_numeric(value)) {
    raise_expected(value, "Float");
  }
  return Rice::detail::From_Ruby<double>().convert(value.value());
}

// luaL_checkinteger, which LÖVE then casts to the type it stores.
long long check_integer(const Rice::Object &value) {
  if (!ruby::is_numeric(value)) {
    raise_expected(value, "Integer");
  }
  return Rice::detail::From_Ruby<long long>().convert(value.value());
}

// luaL_checktype(L, idx, LUA_TTABLE), and the table's elements.
Values check_table(const Rice::Object &value) {
  if (!ruby::is_array(value)) {
    raise_expected(value, "Array");
  }
  return ruby::elements(Rice::Array(value.value()));
}

// luaL_checktype(L, idx, LUA_TBOOLEAN), and lua_toboolean.
int check_boolean(const Rice::Object &value) {
  if (!ruby::is_boolean(value)) {
    raise_expected(value, "true or false");
  }
  return ruby::is_true(value) ? 1 : 0;
}

// luax_checktexture.
Texture *check_texture(const Rice::Object &value) {
  if (!ruby::is_kind_of(value, Rice::Data_Type<Texture>::klass())) {
    raise_expected(value, "Lota::Graphics::Texture");
  }
  return Rice::detail::From_Ruby<Texture *>().convert(value.value());
}

// What a send reads of a uniform, out of the unions Shader::UniformInfo
// keeps it in (graphics/Shader.h:144-181), which baseType tags: the
// components of a vector, or the columns and rows of a matrix, and the
// memory its values go to.
struct Uniform {
  const Shader::UniformInfo *info;
  int components;
  int columns;
  int rows;
  void *data;
};

// Shader::UniformInfo keeps its size and its memory in anonymous unions
// tagged by baseType, and offers no other accessor; LÖVE's own
// wrap_Shader.cpp reads them the same way.
// NOLINTBEGIN(cppcoreguidelines-pro-type-union-access)
Uniform uniform_of(const Shader::UniformInfo *info) {
  if (info->baseType == Shader::UNIFORM_MATRIX) {
    return {
        .info = info,
        .components = 0,
        .columns = info->matrix.columns,
        .rows = info->matrix.rows,
        .data = info->data,
    };
  }
  return {
      .info = info,
      .components = info->components,
      .columns = 0,
      .rows = 0,
      .data = info->data,
  };
}
// NOLINTEND(cppcoreguidelines-pro-type-union-access)

// Copies +values+ to the start of a uniform's memory.
template <typename T> void store(const Uniform &uniform, const std::vector<T> &values) {
  const std::span<T> memory(static_cast<T *>(uniform.data), values.size());
  std::ranges::copy(values, memory.begin());
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from w_Shader_send, w_Shader_sendColors, and the functions they
// call (vendor/love/src/modules/graphics/wrap_Shader.cpp:50-477), and
// changed to read the values Lota::Graphics::Shader passes, in an Array,
// where LÖVE reads them from Lua's stack, and to raise TypeError where
// LÖVE raises a Lua type error. Each writes its values into a vector
// before it copies them to the uniform, where LÖVE writes them there one
// at a time; a send that fails partway leaves values that no later
// updateUniform reads either way.

// The uniform +name+ (wrap_Shader.cpp:446-450).
const Shader::UniformInfo *uniform_info(const Shader &shader, const std::string &name) {
  const Shader::UniformInfo *info = shader.getUniformInfo(name);
  if (info == nullptr || !info->active) {
    throw love::Exception("Shader uniform '%s' does not exist.\nA common error is to define but "
                          "not use the variable.",
                          name.c_str());
  }
  return info;
}

// _getCount (lines 50-53): how many elements of the uniform the values
// from +start+ on fill, at least one.
int count_of(const Values &values, int start, const Uniform &uniform) {
  return std::min(std::max(static_cast<int>(values.size()) - start, 1), uniform.info->count);
}

// _updateNumbers (lines 55-77): a number for each element, or a table of
// one for each component.
template <typename T, typename Read>
std::vector<T> numbers(const Values &values, int start, const Uniform &uniform, int count,
                       Read read) {
  const int components = uniform.components;
  std::vector<T> result;
  result.reserve(static_cast<std::size_t>(count) * static_cast<std::size_t>(components));
  for (int i = 0; i < count; i++) {
    if (components == 1) {
      result.push_back(static_cast<T>(read(at(values, start + i))));
      continue;
    }
    const Values table = check_table(at(values, start + i));
    for (int k = 0; k < components; k++) {
      result.push_back(static_cast<T>(read(at(table, k))));
    }
  }
  return result;
}

// The gamma correction of colors (lines 89-99 and 418-430): red, green,
// and blue of each element become linear, while gamma correction is on.
void linearize(std::vector<float> &values, int components, bool colors) {
  if (!colors || !love::graphics::isGammaCorrect()) {
    return;
  }
  const int gammacomponents = std::min(components, GAMMA_COMPONENTS);
  for (std::size_t i = 0; i < values.size(); i++) {
    if (std::cmp_less(i % static_cast<std::size_t>(components), gammacomponents)) {
      values.at(i) = love::math::gammaToLinear(values.at(i));
    }
  }
}

// w_Shader_sendFloats (lines 80-105).
void send_floats(const Values &values, int start, Shader &shader, const Uniform &uniform,
                 bool colors) {
  const int count = count_of(values, start, uniform);
  std::vector<float> floats =
      colors ? numbers<float>(values, start, uniform, count,
                              [](const Rice::Object &value) {
                                return std::min(std::max(check_number(value), 0.0), 1.0);
                              })
             : numbers<float>(values, start, uniform, count, &check_number);
  linearize(floats, uniform.components, colors);
  store(uniform, floats);
  shader.updateUniform(uniform.info, count);
}

// w_Shader_sendInts and w_Shader_sendUnsignedInts (lines 107-121).
template <typename T>
void send_integers(const Values &values, int start, Shader &shader, const Uniform &uniform) {
  const int count = count_of(values, start, uniform);
  store(uniform, numbers<T>(values, start, uniform, count, &check_integer));
  shader.updateUniform(uniform.info, count);
}

// w_Shader_sendBooleans (lines 123-158), which sends them as ints.
void send_booleans(const Values &values, int start, Shader &shader, const Uniform &uniform) {
  const int count = count_of(values, start, uniform);
  store(uniform, numbers<int>(values, start, uniform, count, &check_boolean));
  shader.updateUniform(uniform.info, count);
}

// Where the element in +column+ and +row+ of a matrix is, in the
// column-major order the uniform keeps it in.
std::size_t matrix_index(const Uniform &uniform, int column, int row) {
  return (static_cast<std::size_t>(column) * static_cast<std::size_t>(uniform.rows)) +
         static_cast<std::size_t>(row);
}

// How many elements one matrix of the uniform has.
std::size_t matrix_elements(const Uniform &uniform) {
  return static_cast<std::size_t>(uniform.columns) * static_cast<std::size_t>(uniform.rows);
}

// A matrix layout's name (lines 164-171).
Transform::MatrixLayout check_layout(const Rice::Object &value) {
  const std::string name = Rice::detail::From_Ruby<std::string>().convert(value.value());
  Transform::MatrixLayout layout{};
  if (!Transform::getConstant(name.c_str(), layout)) {
    raise_enum_error("matrix layout", Transform::getConstants(layout), name);
  }
  return layout;
}

// One matrix from a table of tables (lines 192-231): each a column, in
// column-major order, or a row.
void matrix_of_tables(const Values &table, bool columnmajor, const Uniform &uniform,
                      std::span<float> matrix) {
  const int outer = columnmajor ? uniform.columns : uniform.rows;
  const int inner = columnmajor ? uniform.rows : uniform.columns;
  for (int i = 0; i < outer; i++) {
    const Values line = check_table(at(table, i));
    for (int j = 0; j < inner; j++) {
      const int column = columnmajor ? i : j;
      const int row = columnmajor ? j : i;
      matrix.subspan(matrix_index(uniform, column, row), 1).front() =
          static_cast<float>(check_number(at(line, j)));
    }
  }
}

// One matrix from a flat table (lines 232-263), in column-major or
// row-major order.
void matrix_of_numbers(const Values &table, bool columnmajor, const Uniform &uniform,
                       std::span<float> matrix) {
  for (int column = 0; column < uniform.columns; column++) {
    for (int row = 0; row < uniform.rows; row++) {
      const int index =
          columnmajor ? (column * uniform.rows) + row : (row * uniform.columns) + column;
      matrix.subspan(matrix_index(uniform, column, row), 1).front() =
          static_cast<float>(check_number(at(table, index)));
    }
  }
}

// w_Shader_sendMatrices (lines 160-269): each a Transform, for a 4 by 4
// matrix, or a table, after an optional layout.
void send_matrices(const Values &values, int start, Shader &shader, const Uniform &uniform) {
  bool columnmajor = false;
  if (ruby::is_string(at(values, start))) {
    columnmajor = check_layout(at(values, start)) == Transform::MATRIX_COLUMN_MAJOR;
    start++;
  }

  const int count = count_of(values, start, uniform);
  const std::size_t elements = matrix_elements(uniform);
  std::vector<float> floats(static_cast<std::size_t>(count) * elements);
  const std::span<float> all(floats);

  for (int i = 0; i < count; i++) {
    const std::span<float> matrix = all.subspan(static_cast<std::size_t>(i) * elements, elements);
    const Rice::Object value = at(values, start + i);
    if (uniform.columns == MATRIX4_SIDE && uniform.rows == MATRIX4_SIDE && is_transform(value)) {
      const Transform *transform = Rice::detail::From_Ruby<Transform *>().convert(value.value());
      std::ranges::copy(std::span(transform->getMatrix().getElements(), MATRIX4_ELEMENTS),
                        matrix.begin());
      continue;
    }

    const Values table = check_table(value);
    if (ruby::is_array(at(table, 0))) {
      matrix_of_tables(table, columnmajor, uniform, matrix);
    } else {
      matrix_of_numbers(table, columnmajor, uniform, matrix);
    }
  }

  store(uniform, floats);
  shader.updateUniform(uniform.info, count);
}

// w_Shader_sendTextures (lines 271-286).
void send_textures(const Values &values, int start, Shader &shader, const Uniform &uniform) {
  const int count = count_of(values, start, uniform);
  std::vector<Texture *> textures;
  textures.reserve(static_cast<std::size_t>(count));
  for (int i = 0; i < count; i++) {
    textures.push_back(check_texture(at(values, start + i)));
  }
  shader.sendTextures(uniform.info, textures.data(), count);
}

// luax_checktype<Buffer>.
Buffer *check_buffer(const Rice::Object &value) {
  if (!ruby::is_kind_of(value, Rice::Data_Type<Buffer>::klass())) {
    raise_expected(value, "Lota::Graphics::Buffer");
  }
  return Rice::detail::From_Ruby<Buffer *>().convert(value.value());
}

// w_Shader_sendBuffers (lines 288-303).
void send_buffers(const Values &values, int start, Shader &shader, const Uniform &uniform) {
  const int count = count_of(values, start, uniform);
  std::vector<Buffer *> buffers;
  buffers.reserve(static_cast<std::size_t>(count));
  for (int i = 0; i < count; i++) {
    buffers.push_back(check_buffer(at(values, start + i)));
  }
  shader.sendBuffers(uniform.info, buffers.data(), count);
}

// w_Shader_sendLuaValues (lines 305-328).
void send_values(const Values &values, int start, Shader &shader, const Uniform &uniform,
                 const std::string &name) {
  switch (uniform.info->baseType) {
  case Shader::UNIFORM_FLOAT:
    send_floats(values, start, shader, uniform, false);
    return;
  case Shader::UNIFORM_MATRIX:
    send_matrices(values, start, shader, uniform);
    return;
  case Shader::UNIFORM_INT:
    send_integers<int>(values, start, shader, uniform);
    return;
  case Shader::UNIFORM_UINT:
    send_integers<unsigned int>(values, start, shader, uniform);
    return;
  case Shader::UNIFORM_BOOL:
    send_booleans(values, start, shader, uniform);
    return;
  case Shader::UNIFORM_SAMPLER:
  case Shader::UNIFORM_STORAGETEXTURE:
    send_textures(values, start, shader, uniform);
    return;
  case Shader::UNIFORM_TEXELBUFFER:
  case Shader::UNIFORM_STORAGEBUFFER:
    send_buffers(values, start, shader, uniform);
    return;
  default:
    throw love::Exception("Unknown variable type for shader uniform '%s", name.c_str());
  }
}

// luaL_optinteger.
long long optional_integer(const Rice::Object &value, long long fallback) {
  return ruby::is_nil(value) ? fallback : check_integer(value);
}

// How many bytes of the Data a send copies (lines 373-401).
std::size_t data_size(const Values &values, int start, const love::Data &data, std::size_t offset,
                      const Uniform &uniform) {
  const std::size_t size = data.getSize();
  const std::size_t packed = uniform.info->dataSizePacked;
  const std::size_t uniformstride = packed / static_cast<std::size_t>(uniform.info->count);

  if (ruby::is_nil(at(values, start + 2))) {
    return std::min(((size - offset) / uniformstride) * uniformstride, packed);
  }

  const long long sizearg = check_integer(at(values, start + 2));
  if (sizearg <= 0) {
    throw love::Exception("Size must be greater than 0.");
  }
  if (std::cmp_greater(sizearg, size - offset)) {
    throw love::Exception("Size and offset must fit within the Data's bounds.");
  }
  if (static_cast<std::size_t>(sizearg) % uniformstride != 0) {
    throw love::Exception("Size (%lld) must be a multiple of the uniform's size in bytes (%zu).",
                          sizearg, uniformstride);
  }
  if (std::cmp_greater(sizearg, packed)) {
    throw love::Exception("Size must not be greater than the uniform's total size in bytes.");
  }
  return static_cast<std::size_t>(sizearg);
}

// Row-major matrices from +bytes+, transposed into the column-major order
// the uniform keeps them in (lines 412-428).
void store_transposed(const Uniform &uniform, std::span<const std::byte> bytes, int count) {
  const std::size_t elements = matrix_elements(uniform);
  std::vector<float> source(static_cast<std::size_t>(count) * elements);
  std::memcpy(source.data(), bytes.data(), std::min(bytes.size(), source.size() * sizeof(float)));
  std::vector<float> floats(source.size());
  for (std::size_t i = 0; std::cmp_less(i, count); i++) {
    for (int row = 0; row < uniform.rows; row++) {
      for (int column = 0; column < uniform.columns; column++) {
        const std::size_t row_major =
            (static_cast<std::size_t>(row) * static_cast<std::size_t>(uniform.columns)) +
            static_cast<std::size_t>(column);
        floats.at((i * elements) + matrix_index(uniform, column, row)) =
            source.at((i * elements) + row_major);
      }
    }
  }
  store(uniform, floats);
}

// The layout of a matrix sent from a Data, given before the Data or,
// LÖVE's older order, after it (lines 337-358), and the index the
// offset's follows.
struct DataLayout {
  Transform::MatrixLayout layout;
  int start;
  int dataidx;
};

DataLayout data_layout(const Values &values, int start, const Uniform &uniform) {
  DataLayout result{.layout = Transform::MATRIX_ROW_MAJOR, .start = start, .dataidx = start};
  if (uniform.info->baseType != Shader::UNIFORM_MATRIX) {
    return result;
  }
  if (ruby::is_string(at(values, start))) {
    result.layout = check_layout(at(values, start));
    result.start = start + 1;
    result.dataidx = start + 1;
  } else if (ruby::is_string(at(values, start + 1))) {
    result.layout = check_layout(at(values, start + 1));
    result.start = start + 1;
  }
  return result;
}

// w_Shader_sendData (lines 330-441).
void send_data(const Values &values, int start, Shader &shader, const Uniform &uniform,
               bool colors) {
  const Shader::UniformType type = uniform.info->baseType;
  if (type == Shader::UNIFORM_SAMPLER || type == Shader::UNIFORM_STORAGETEXTURE ||
      type == Shader::UNIFORM_TEXELBUFFER || type == Shader::UNIFORM_STORAGEBUFFER) {
    throw love::Exception("Only value types (floats, ints, vectors, matrices, etc) be sent to "
                          "Shaders via Data objects.");
  }

  const DataLayout layout = data_layout(values, start, uniform);
  start = layout.start;
  const bool columnmajor = layout.layout == Transform::MATRIX_COLUMN_MAJOR;

  const Rice::Object argument = at(values, layout.dataidx);
  if (!is_data(argument)) {
    raise_expected(argument, "Lota::Data");
  }
  const love::Data *data = Rice::detail::From_Ruby<love::Data *>().convert(argument.value());

  const long long offset = optional_integer(at(values, start + 1), 0);
  if (offset < 0) {
    throw love::Exception("Offset cannot be negative.");
  }
  if (static_cast<std::size_t>(offset) >= data->getSize()) {
    throw love::Exception("Offset must be less than the size of the Data.");
  }

  const std::size_t size =
      data_size(values, start, *data, static_cast<std::size_t>(offset), uniform);
  if (size == 0) {
    throw love::Exception("Size to copy must be greater than 0.");
  }

  const std::size_t uniformstride =
      uniform.info->dataSizePacked / static_cast<std::size_t>(uniform.info->count);
  const int count = static_cast<int>(size / uniformstride);
  const std::span<const std::byte> bytes =
      std::span(static_cast<const std::byte *>(data->getData()), data->getSize())
          .subspan(static_cast<std::size_t>(offset), size);

  if (type != Shader::UNIFORM_MATRIX || columnmajor) {
    std::memcpy(uniform.data, bytes.data(), size);
  } else {
    store_transposed(uniform, bytes, count);
  }

  if (colors && love::graphics::isGammaCorrect()) {
    const auto components = static_cast<std::size_t>(uniform.components);
    std::vector<float> floats(static_cast<std::size_t>(count) * components);
    std::memcpy(floats.data(), uniform.data, floats.size() * sizeof(float));
    linearize(floats, uniform.components, colors);
    store(uniform, floats);
  }

  shader.updateUniform(uniform.info, count);
}

// w_Shader_send (lines 443-456): the uniform +name+ from a Data, or from
// the values.
void shader_send(Shader &shader, const std::string &name, Rice::Array values) {
  require_main_thread(MODULE);
  const Rice::Array array = std::move(values);
  const Uniform uniform = uniform_of(uniform_info(shader, name));
  const Values given = ruby::elements(array);
  if (is_data(at(given, 0)) ||
      (uniform.info->baseType == Shader::UNIFORM_MATRIX && is_data(at(given, 1)))) {
    send_data(given, 0, shader, uniform, false);
  } else {
    send_values(given, 0, shader, uniform, name);
  }
}

// w_Shader_sendColors (lines 458-477), which returns true.
bool shader_send_color(Shader &shader, const std::string &name, Rice::Array values) {
  require_main_thread(MODULE);
  const Rice::Array array = std::move(values);
  const Uniform uniform = uniform_of(uniform_info(shader, name));
  if (uniform.info->baseType != Shader::UNIFORM_FLOAT || uniform.components < GAMMA_COMPONENTS) {
    throw love::Exception("Shader:sendColor can only be used with vec3 or vec4 uniforms.");
  }
  const Values given = ruby::elements(array);
  if (is_data(at(given, 0))) {
    send_data(given, 0, shader, uniform, true);
  } else {
    send_floats(given, 0, shader, uniform, true);
  }
  return true;
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_checkgraphicscreated, w_getShaderSource, w_newShader,
// and w_validateShader (vendor/love/src/modules/graphics/
// wrap_Graphics.cpp:56-61 and 1481-1717). Lota::Graphics::Shader reads the
// sources and the options table, as w_getShaderSource does, and passes
// the defines as pairs of Strings; these make the shader from them.

// luax_checkgraphicscreated (lines 56-61), which w_getShaderSource calls
// before it reads anything.
void check_graphics_created() {
  if (!graphics().isCreated()) {
    throw love::Exception("%s cannot function without a window.", MODULE);
  }
}

// The options w_getShaderSource reads (lines 1559-1604): the defines, each
// a name and a value, the debug name, and whether the "write" feature is
// on.
Shader::CompileOptions compile_options(const Rice::Array &defines, const std::string &debugname,
                                       bool write) {
  Shader::CompileOptions options;
  for (const Rice::Object &pair : ruby::elements(defines)) {
    const Values define = ruby::elements(Rice::Array(pair.value()));
    options.defines[Rice::detail::From_Ruby<std::string>().convert(define.at(0).value())] =
        Rice::detail::From_Ruby<std::string>().convert(define.at(1).value());
  }
  options.debugName = debugname;
  options.features[Shader::FEATURE_WRITE] = write;
  return options;
}

std::vector<std::string> sources_of(const Rice::Array &stages) {
  std::vector<std::string> sources;
  for (const Rice::Object &stage : ruby::elements(stages)) {
    sources.push_back(Rice::detail::From_Ruby<std::string>().convert(stage.value()));
  }
  return sources;
}

// w_newShader's shader (lines 1609-1645). Its one reference goes to the
// Ruby object; Lota::Graphics::Shader.new marks the deprecated uses
// LÖVE marks, and rewrites the message of a shader that does not compile,
// as LÖVE's _transformGLSLErrorMessages does.
Shader *new_shader(Rice::Array stages, const std::string &debugname, Rice::Array defines,
                   bool write) {
  const Rice::Array sources = std::move(stages);
  const Rice::Array pairs = std::move(defines);
  Graphics &instance = graphics();
  return instance.newShader(sources_of(sources), compile_options(pairs, debugname, write));
}

// w_newComputeShader's shader (lines 1647-1683): the compute stage of the
// first source, made as new_shader makes a shader.
Shader *new_compute_shader(Rice::Array stages, const std::string &debugname, Rice::Array defines,
                           bool write) {
  const Rice::Array sources = std::move(stages);
  const Rice::Array pairs = std::move(defines);
  Graphics &instance = graphics();
  return instance.newComputeShader(sources_of(sources).at(0),
                                   compile_options(pairs, debugname, write));
}

// w_validateShader (lines 1685-1717): whether the sources compile for the
// renderer +gles+ names, and the message they do not with.
Rice::Array validate_shader(bool gles, Rice::Array stages, const std::string &debugname,
                            Rice::Array defines, bool write) {
  const Rice::Array given = std::move(stages);
  const Rice::Array pairs = std::move(defines);
  Graphics &instance = graphics();
  const std::vector<std::string> sources = sources_of(given);
  const Shader::CompileOptions options = compile_options(pairs, debugname, write);
  bool success = true;
  std::string err;
  try {
    success = instance.validateShader(gles, sources, options, err);
  } catch (const love::Exception &e) {
    success = false;
    err = e.what();
  }

  Rice::Array results;
  results.push(success, false);
  if (!success) {
    results.push(Rice::String(err), false);
  }
  return results;
}

// w_Shader_getBufferFormat (wrap_Shader.cpp:517-550): the name, format, and
// array length of each member of the buffer +name+ the shader declares.
Rice::Array shader_buffer_format(Shader &shader, const std::string &name) {
  require_main_thread(MODULE);
  const std::vector<Buffer::DataDeclaration> *format = shader.getBufferFormat(name);
  if (format == nullptr) {
    throw love::Exception("Buffer '%s' does not exist in the Shader.", name.c_str());
  }
  Rice::Array members;
  for (const Buffer::DataDeclaration &member : *format) {
    const char *formatname = "unknown";
    love::graphics::getConstant(member.format, formatname);
    Rice::Array fields;
    fields.push(member.name, false);
    fields.push(std::string(formatname), false);
    fields.push(member.arrayLength, false);
    members.push(fields, false);
  }
  return members;
}

// w_dispatchThreadgroups (wrap_Graphics.cpp:3794-3802).
void dispatch_threadgroups(Shader *shader, long long x, std::optional<long long> y,
                           std::optional<long long> z) {
  graphics().dispatchThreadgroups(shader, static_cast<int>(x), static_cast<int>(y.value_or(1)),
                                  static_cast<int>(z.value_or(1)));
}

// w_dispatchIndirect (wrap_Graphics.cpp:3804-3811): the groups the
// element +argsindex+, counting from 1, of +argsbuffer+ counts.
void dispatch_indirect(Shader *shader, Buffer *argsbuffer, std::optional<long long> argsindex) {
  graphics().dispatchIndirect(shader, argsbuffer, static_cast<int>(argsindex.value_or(1)) - 1);
}

// SPDX-SnippetEnd

} // namespace

void define_shader(const Rice::Module &native) {
  // Its other methods are generated (ext/lota/native/generated/graphics.cpp).
  define_engine_class<Shader>(native, "Shader")
      .define_method("send_values", &shader_send, Rice::Arg("name"), Rice::Arg("values"))
      .define_method("send_color", &shader_send_color, Rice::Arg("name"), Rice::Arg("values"))
      .define_method("buffer_format", &shader_buffer_format, Rice::Arg("name"))
      .define_method(
          "deprecated_texture_functions?",
          [](const Shader &shader) { return shader.isUsingDeprecatedTextureFunctions(); })
      .define_method("deprecated_texture_uniform?",
                     [](const Shader &shader) { return shader.isUsingDeprecatedTextureUniform(); })
      .define_method("unset_vertex_input_locations", [](const Shader &shader) {
        return shader.getUnsetVertexInputLocationsString();
      });

  Rice::define_module_under(native, "Graphics")
      .define_singleton_function("check_created", &check_graphics_created)
      .define_singleton_function(
          "dispatch_threadgroups", &dispatch_threadgroups, Rice::Arg("shader"), Rice::Arg("x"),
          Rice::Arg("y") = std::optional<long long>(), Rice::Arg("z") = std::optional<long long>())
      .define_singleton_function("dispatch_indirect", &dispatch_indirect, Rice::Arg("shader"),
                                 Rice::Arg("argsbuffer"),
                                 Rice::Arg("argsindex") = std::optional<long long>())
      .define_singleton_function("new_shader", &new_shader, Rice::Arg("stages"),
                                 Rice::Arg("debugname"), Rice::Arg("defines"), Rice::Arg("write"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_compute_shader", &new_compute_shader, Rice::Arg("stages"),
                                 Rice::Arg("debugname"), Rice::Arg("defines"), Rice::Arg("write"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("validate_shader", &validate_shader, Rice::Arg("gles"),
                                 Rice::Arg("stages"), Rice::Arg("debugname"), Rice::Arg("defines"),
                                 Rice::Arg("write"));
}

} // namespace lota::native
