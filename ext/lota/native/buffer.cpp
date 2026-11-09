// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/buffer.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "common/Color.h"
#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/int.h"
#include "graphics/Buffer.h"
#include "graphics/Graphics.h"
#include "graphics/Mesh.h"
#include "graphics/vertex.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace lota::native {

using love::graphics::Buffer;
using love::graphics::DataFormat;
using love::graphics::Graphics;
using love::graphics::Mesh;

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

// luax_checkgraphicscreated (wrap_Graphics.cpp:56-61): the module, once
// it has a window to draw in.
Graphics &created_graphics() {
  Graphics &instance = graphics();
  if (!instance.isCreated()) {
    throw love::Exception("%s cannot function without a window.", MODULE);
  }
  return instance;
}

// The values of a Lua table or of the stack, as Lota::Graphics passes
// them, the first at index 0.
using Values = std::vector<Rice::Object>;

// The value at +index+, or nil past the last, as Lua reads a table's
// missing element.
Rice::Object at(std::span<const Rice::Object> values, std::size_t index) {
  return index < values.size() ? values.subspan(index, 1).front() : ruby::nil();
}

[[noreturn]] void raise_expected(const Rice::Object &value, const char *expected) {
  ruby::raise_type_error("wrong argument type " + ruby::class_name(value) + " (expected " +
                         expected + ")");
}

// luaL_checknumber, of what Lota::Graphics passes.
double check_number(const Rice::Object &value) {
  if (!ruby::is_numeric(value)) {
    raise_expected(value, "Float");
  }
  return Rice::detail::From_Ruby<double>().convert(value.value());
}

// luaL_checkinteger, of what Lota::Graphics passes.
long long check_integer(const Rice::Object &value) {
  if (!ruby::is_numeric(value)) {
    raise_expected(value, "Integer");
  }
  return Rice::detail::From_Ruby<long long>().convert(value.value());
}

// luaL_optnumber.
double optional_number(const Rice::Object &value, double fallback) {
  return ruby::is_nil(value) ? fallback : check_number(value);
}

// luaL_optnumber's argument, or nothing when it is nil.
std::optional<double> optional_argument(const Rice::Object &value) {
  if (ruby::is_nil(value)) {
    return std::nullopt;
  }
  return check_number(value);
}

// luaL_checktype(L, idx, LUA_TTABLE), and the table's elements.
Values check_table(const Rice::Object &value) {
  if (!ruby::is_array(value)) {
    raise_expected(value, "Array");
  }
  return ruby::elements(Rice::Array(value.value()));
}

bool is_data(const Rice::Object &value) {
  return ruby::is_kind_of(value, Rice::Data_Type<love::Data>::klass());
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_writebufferdata and luax_readbufferdata, and the
// templates they call (vendor/love/src/modules/graphics/
// wrap_Buffer.cpp:32-212), and changed to read and push the numbers of a
// Ruby Array where LÖVE reads and pushes Lua's stack, to raise TypeError
// where LÖVE raises a Lua type error, and to write into a span, which
// raises where LÖVE's writes past the end of its memory.

// The value a component takes when the Lua table has none (line 32).
constexpr std::array<double, 4> DEFAULT_COMPONENTS = {0.0, 0.0, 0.0, 1.0};

// How a number becomes a component: writeData's cast, writeSNormData's
// and writeUNormData's scaling of a clamped number to the type's range,
// or writeDataRequired's cast of a number that must be there.
enum class Kind : std::uint8_t { Plain, SNorm, UNorm, Required };

// The numbers of a row from where a member's start.
struct Cursor {
  std::span<const Rice::Object> row;
  std::size_t start;
};

template <typename T, Kind K>
double component_number(const Rice::Object &value, std::size_t index) {
  [[maybe_unused]] constexpr auto maxval = static_cast<double>(std::numeric_limits<T>::max());
  if constexpr (K == Kind::Required) {
    return check_number(value);
  } else if constexpr (K == Kind::SNorm) {
    return std::min(std::max(optional_number(value, DEFAULT_COMPONENTS.at(index)), -1.0), 1.0) *
           maxval;
  } else if constexpr (K == Kind::UNorm) {
    return std::min(std::max(optional_number(value, 1.0), 0.0), 1.0) * maxval;
  } else {
    return optional_number(value, DEFAULT_COMPONENTS.at(index));
  }
}

// writeData, writeSNormData, writeUNormData, and writeDataRequired: the
// +components+ numbers of a row from its start, stored as T in +out+.
template <typename T, Kind K>
void write_components(const Cursor &cursor, std::size_t components, std::span<std::byte> out) {
  if (out.size() < components * sizeof(T)) {
    throw love::Exception("Buffer element is too small for its data format.");
  }
  for (std::size_t i = 0; i < components; i++) {
    const auto component =
        static_cast<T>(component_number<T, K>(at(cursor.row, cursor.start + i), i));
    std::memcpy(out.subspan(i * sizeof(T), sizeof(T)).data(), &component, sizeof(T));
  }
}

// How many numbers a data format takes (DataFormatInfo::components).
std::size_t components_of(DataFormat format) {
  return static_cast<std::size_t>(love::graphics::getDataFormatInfo(format).components);
}

// luax_writebufferdata (lines 80-131): the numbers of a row from a
// member's start, as the data format +format+ stores them. The number of
// components is the one DataFormatInfo gives, which the cases of LÖVE's
// switch spell out.
void write_member(DataFormat format, const Cursor &cursor, std::span<std::byte> out) {
  using enum DataFormat;
  const std::size_t components = components_of(format);
  switch (format) {
  case DATAFORMAT_FLOAT:
  case DATAFORMAT_FLOAT_VEC2:
  case DATAFORMAT_FLOAT_VEC3:
  case DATAFORMAT_FLOAT_VEC4:
    write_components<float, Kind::Plain>(cursor, components, out);
    break;

  case DATAFORMAT_FLOAT_MAT2X2:
  case DATAFORMAT_FLOAT_MAT2X3:
  case DATAFORMAT_FLOAT_MAT2X4:
  case DATAFORMAT_FLOAT_MAT3X2:
  case DATAFORMAT_FLOAT_MAT3X3:
  case DATAFORMAT_FLOAT_MAT3X4:
  case DATAFORMAT_FLOAT_MAT4X2:
  case DATAFORMAT_FLOAT_MAT4X3:
  case DATAFORMAT_FLOAT_MAT4X4:
    write_components<float, Kind::Required>(cursor, components, out);
    break;

  case DATAFORMAT_INT32:
  case DATAFORMAT_INT32_VEC2:
  case DATAFORMAT_INT32_VEC3:
  case DATAFORMAT_INT32_VEC4:
    write_components<love::int32, Kind::Plain>(cursor, components, out);
    break;

  case DATAFORMAT_UINT32:
  case DATAFORMAT_UINT32_VEC2:
  case DATAFORMAT_UINT32_VEC3:
  case DATAFORMAT_UINT32_VEC4:
    write_components<love::uint32, Kind::Plain>(cursor, components, out);
    break;

  case DATAFORMAT_SNORM8_VEC4:
    write_components<love::int8, Kind::SNorm>(cursor, components, out);
    break;
  case DATAFORMAT_UNORM8_VEC4:
    write_components<love::uint8, Kind::UNorm>(cursor, components, out);
    break;
  case DATAFORMAT_INT8_VEC4:
    write_components<love::int8, Kind::Plain>(cursor, components, out);
    break;
  case DATAFORMAT_UINT8_VEC4:
    write_components<love::uint8, Kind::Plain>(cursor, components, out);
    break;

  case DATAFORMAT_SNORM16_VEC2:
  case DATAFORMAT_SNORM16_VEC4:
    write_components<love::int16, Kind::SNorm>(cursor, components, out);
    break;

  case DATAFORMAT_UNORM16_VEC2:
  case DATAFORMAT_UNORM16_VEC4:
    write_components<love::uint16, Kind::UNorm>(cursor, components, out);
    break;

  case DATAFORMAT_INT16_VEC2:
  case DATAFORMAT_INT16_VEC4:
    write_components<love::int16, Kind::Plain>(cursor, components, out);
    break;

  case DATAFORMAT_UINT16:
  case DATAFORMAT_UINT16_VEC2:
  case DATAFORMAT_UINT16_VEC4:
    write_components<love::uint16, Kind::Plain>(cursor, components, out);
    break;

  default:
    break;
  }
}

// The number a stored component is, as readData, readSNormData, and
// readUNormData make it.
template <typename T, Kind K> double component_value(T component) {
  [[maybe_unused]] constexpr auto maxval = static_cast<double>(std::numeric_limits<T>::max());
  const auto number = static_cast<double>(component);
  if constexpr (K == Kind::SNorm) {
    return std::max(-1.0, number / maxval);
  } else if constexpr (K == Kind::UNorm) {
    return number / maxval;
  } else {
    return number;
  }
}

// readData, readSNormData, and readUNormData: +components+ numbers of type
// T from +in+, pushed on +out+. The C++ holds a plain integer format's
// numbers as integers, so they are Integers (rule 14 of
// doc/contributors/design/translation.md), as the rest are Floats.
template <typename T, Kind K>
void read_components(Rice::Array &out, std::size_t components, std::span<const std::byte> in) {
  if (in.size() < components * sizeof(T)) {
    throw love::Exception("Buffer element is too small for its data format.");
  }
  for (std::size_t i = 0; i < components; i++) {
    T component{};
    std::memcpy(&component, in.subspan(i * sizeof(T), sizeof(T)).data(), sizeof(T));
    if constexpr (K == Kind::Plain && std::is_integral_v<T>) {
      out.push(static_cast<long long>(component), false);
    } else {
      out.push(component_value<T, K>(component), false);
    }
  }
}

// luax_readbufferdata (lines 168-212): the numbers a data format stores
// at the start of +in+.
void read_member(DataFormat format, Rice::Array &out, std::span<const std::byte> in) {
  using enum DataFormat;
  const std::size_t components = components_of(format);
  switch (format) {
  case DATAFORMAT_FLOAT:
  case DATAFORMAT_FLOAT_VEC2:
  case DATAFORMAT_FLOAT_VEC3:
  case DATAFORMAT_FLOAT_VEC4:
    read_components<float, Kind::Plain>(out, components, in);
    break;

  case DATAFORMAT_INT32:
  case DATAFORMAT_INT32_VEC2:
  case DATAFORMAT_INT32_VEC3:
  case DATAFORMAT_INT32_VEC4:
    read_components<love::int32, Kind::Plain>(out, components, in);
    break;

  case DATAFORMAT_UINT32:
  case DATAFORMAT_UINT32_VEC2:
  case DATAFORMAT_UINT32_VEC3:
  case DATAFORMAT_UINT32_VEC4:
    read_components<love::uint32, Kind::Plain>(out, components, in);
    break;

  case DATAFORMAT_SNORM8_VEC4:
    read_components<love::int8, Kind::SNorm>(out, components, in);
    break;
  case DATAFORMAT_UNORM8_VEC4:
    read_components<love::uint8, Kind::UNorm>(out, components, in);
    break;
  case DATAFORMAT_INT8_VEC4:
    read_components<love::int8, Kind::Plain>(out, components, in);
    break;
  case DATAFORMAT_UINT8_VEC4:
    read_components<love::uint8, Kind::Plain>(out, components, in);
    break;

  case DATAFORMAT_SNORM16_VEC2:
  case DATAFORMAT_SNORM16_VEC4:
    read_components<love::int16, Kind::SNorm>(out, components, in);
    break;

  case DATAFORMAT_UNORM16_VEC2:
  case DATAFORMAT_UNORM16_VEC4:
    read_components<love::uint16, Kind::UNorm>(out, components, in);
    break;

  case DATAFORMAT_INT16_VEC2:
  case DATAFORMAT_INT16_VEC4:
    read_components<love::int16, Kind::Plain>(out, components, in);
    break;

  case DATAFORMAT_UINT16:
  case DATAFORMAT_UINT16_VEC2:
  case DATAFORMAT_UINT16_VEC4:
    read_components<love::uint16, Kind::Plain>(out, components, in);
    break;

  default:
    break;
  }
}

// How many numbers one element of a buffer or a vertex takes.
std::size_t component_count(const std::vector<Buffer::DataMember> &members) {
  std::size_t components = 0;
  for (const Buffer::DataMember &member : members) {
    components += static_cast<std::size_t>(member.info.components);
  }
  return components;
}

// The loop body LÖVE repeats in w_Buffer_setArrayData, luax_newbuffer,
// w_Mesh_setVertices, and newCustomMesh: every member of one element,
// written from the numbers of +row+, each member's after the last's.
void write_element(const std::vector<Buffer::DataMember> &members, const Values &row,
                   std::span<std::byte> element) {
  std::size_t start = 0;
  for (const Buffer::DataMember &member : members) {
    write_member(member.decl.format, Cursor{.row = row, .start = start},
                 element.subspan(member.offset));
    start += static_cast<std::size_t>(member.info.components);
  }
}

// The numbers of every member of the element +element+ holds, in order.
Rice::Array read_element(const std::vector<Buffer::DataMember> &members,
                         std::span<const std::byte> element) {
  Rice::Array numbers;
  for (const Buffer::DataMember &member : members) {
    read_member(member.decl.format, numbers, element.subspan(member.offset));
  }
  return numbers;
}

// The numbers of the element at +index+ of a table of tables, or of a
// flat table of +ncomponents+ numbers to each element.
Values element_row(const Values &table, bool tableoftables, std::size_t index,
                   std::size_t ncomponents) {
  if (tableoftables) {
    return check_table(at(table, index));
  }
  Values row;
  row.reserve(ncomponents);
  for (std::size_t component = 0; component < ncomponents; component++) {
    row.push_back(at(table, (index * ncomponents) + component));
  }
  return row;
}

// Writes the elements +first+ up to +last+ of +table+ to consecutive
// elements of +bytes+, the first at its start.
void write_elements(const std::vector<Buffer::DataMember> &members, const Values &table,
                    bool tableoftables, std::size_t first, std::size_t last, std::size_t stride,
                    std::span<std::byte> bytes) {
  const std::size_t ncomponents = component_count(members);
  for (std::size_t i = first; i < last; i++) {
    const Values row = element_row(table, tableoftables, i, ncomponents);
    write_element(members, row, bytes.subspan((i - first) * stride, stride));
  }
}

// luax_checkdatadeclaration's declarations (wrap_Graphics.cpp:1743-1793),
// which Lota::Graphics::Buffer reads from the Hashes it is given into
// Arrays of the name, the data format's name, the array length, and the
// binding location or nil.
std::vector<Buffer::DataDeclaration> declarations_of(const Rice::Array &entries) {
  std::vector<Buffer::DataDeclaration> declarations;
  for (const Rice::Object &entry : ruby::elements(entries)) {
    const Values fields = check_table(entry);
    const auto name = Rice::detail::From_Ruby<std::string>().convert(at(fields, 0).value());
    const auto format = Rice::detail::From_Ruby<std::string>().convert(at(fields, 1).value());
    Buffer::DataDeclaration declaration(name, DataFormat::DATAFORMAT_MAX_ENUM);
    if (!love::graphics::getConstant(format.c_str(), declaration.format)) {
      raise_enum_error("data format", love::graphics::getConstants(declaration.format), format);
    }
    declaration.arrayLength = Rice::detail::From_Ruby<int>().convert(at(fields, 2).value());
    if (!ruby::is_nil(at(fields, 3))) {
      declaration.bindingLocation = Rice::detail::From_Ruby<int>().convert(at(fields, 3).value());
    }
    declarations.push_back(declaration);
  }
  return declarations;
}

// The name of a data format, "unknown" for one LÖVE has no name for.
std::string format_name(DataFormat format) {
  const char *name = "unknown";
  love::graphics::getConstant(format, name);
  return name;
}

// w_Buffer_setArrayData (wrap_Buffer.cpp:214-343): the data, a Data or a
// table of elements or of numbers, from the element +source+ of it to the
// element +destination+ of the buffer, counting from 1, +count+ elements
// of them, which +arguments+ lists in that order, each nil when left out.
void buffer_set_array_data(Buffer &t, Rice::Array list) {
  require_main_thread(MODULE);
  const Rice::Array arguments = std::move(list);
  const Values given = ruby::elements(arguments);
  const Rice::Object data = at(given, 0);
  const std::optional<double> source = optional_argument(at(given, 1));
  const std::optional<double> destination = optional_argument(at(given, 2));
  const std::optional<double> count_given = optional_argument(at(given, 3));
  const int sourceindex = static_cast<int>(source.value_or(1.0)) - 1;
  const int destindex = static_cast<int>(destination.value_or(1.0)) - 1;

  if (sourceindex < 0) {
    throw love::Exception("Source start index must be at least 1.");
  }

  int count = -1;
  if (count_given.has_value()) {
    count = static_cast<int>(*count_given);
    if (count <= 0) {
      throw love::Exception("Element count must be greater than 0.");
    }
  }

  const std::size_t stride = t.getArrayStride();
  const int arraylength = static_cast<int>(t.getArrayLength());

  if (destindex >= arraylength || destindex < 0) {
    throw love::Exception("Invalid buffer start index (must be between 1 and %d)", arraylength);
  }
  const std::size_t bufferoffset = static_cast<std::size_t>(destindex) * stride;

  if (is_data(data)) {
    const auto *d = Rice::detail::From_Ruby<love::Data *>().convert(data.value());
    const int dataarraylength = static_cast<int>(d->getSize() / stride);

    if (sourceindex >= dataarraylength) {
      throw love::Exception("Invalid data start index (must be between 1 and %d)", dataarraylength);
    }

    const int maxcount = std::min(dataarraylength - sourceindex, arraylength - destindex);
    if (count < 0) {
      count = maxcount;
    }
    if (count > maxcount) {
      throw love::Exception("Too many array elements (expected at most %d, got %d)", maxcount,
                            count);
    }

    const std::size_t dataoffset = static_cast<std::size_t>(sourceindex) * stride;
    const std::size_t datasize =
        std::min(d->getSize() - dataoffset, static_cast<std::size_t>(count) * stride);
    const std::span<const std::byte> bytes(static_cast<const std::byte *>(d->getData()),
                                           d->getSize());
    static_cast<void>(t.fill(bufferoffset, datasize, bytes.subspan(dataoffset).data()));
    return;
  }

  const std::vector<Buffer::DataMember> &members = t.getDataMembers();
  const std::size_t ncomponents = component_count(members);

  const Values table = check_table(data);
  auto tablelen = static_cast<int>(table.size());
  const bool tableoftables = ruby::is_array(at(table, 0));

  if (!tableoftables) {
    if (tablelen % static_cast<int>(ncomponents) != 0) {
      throw love::Exception("Array length in flat array variant of Buffer:setArrayData must be a "
                            "multiple of the total number of components (%d)",
                            static_cast<int>(ncomponents));
    }
    tablelen /= static_cast<int>(ncomponents);
  }

  if (sourceindex >= tablelen) {
    throw love::Exception("Invalid data start index (must be between 1 and %d)", tablelen);
  }

  count = count >= 0 ? std::min(count, tablelen - sourceindex) : tablelen - sourceindex;

  if (destindex + count > arraylength) {
    throw love::Exception("Too many array elements (expected at most %d, got %d)",
                          arraylength - destindex, count);
  }

  const std::size_t mapped_size = static_cast<std::size_t>(count) * stride;
  const std::span<std::byte> mapped(
      static_cast<std::byte *>(t.map(Buffer::MAP_WRITE_INVALIDATE, bufferoffset, mapped_size)),
      mapped_size);

  // LÖVE counts from the start of the table up to the count, not from the
  // source index for the count, so a source index past the first leaves
  // the end of the mapped memory unwritten; Lota unmaps it if a number
  // is wrong, where LÖVE's error leaves it mapped.
  try {
    write_elements(members, table, tableoftables, static_cast<std::size_t>(sourceindex),
                   static_cast<std::size_t>(count), stride, mapped);
  } catch (...) {
    t.unmap(bufferoffset, mapped_size);
    throw;
  }
  t.unmap(bufferoffset, mapped_size);
}

// w_Buffer_getFormat (lines 384-421): the name, format, array length,
// location, offset, and size of each member.
Rice::Array buffer_format(const Buffer &t) {
  Rice::Array members;
  for (const Buffer::DataMember &member : t.getDataMembers()) {
    Rice::Array fields;
    fields.push(member.decl.name, false);
    fields.push(format_name(member.decl.format), false);
    fields.push(member.decl.arrayLength, false);
    fields.push(member.decl.bindingLocation, false);
    fields.push(member.offset, false);
    fields.push(member.size, false);
    members.push(fields, false);
  }
  return members;
}

// w_Buffer_clear (wrap_Buffer.cpp:345-361): the bytes from the offset of
// +range+ for its size, or the whole buffer when it is empty.
void buffer_clear(Buffer &t, Rice::Array list) {
  require_main_thread(MODULE);
  const Rice::Array range = std::move(list);
  const Values given = ruby::elements(range);
  std::size_t offset = 0;
  std::size_t size = t.getSize();
  if (!ruby::is_nil(at(given, 0))) {
    const double offsetp = check_number(at(given, 0));
    const double sizep = check_number(at(given, 1));
    if (offsetp < 0 || sizep < 0) {
      throw love::Exception("Offset and size parameters cannot be negative.");
    }
    offset = static_cast<std::size_t>(offsetp);
    size = static_cast<std::size_t>(sizep);
  }
  t.clear(offset, size);
}

// w_Buffer_isBufferType (lines 423-432).
bool buffer_is_buffer_type(const Buffer &t, const std::string &type) {
  require_main_thread(MODULE);
  love::graphics::BufferUsage bufferusage = love::graphics::BUFFERUSAGE_MAX_ENUM;
  if (!love::graphics::getConstant(type.c_str(), bufferusage)) {
    raise_enum_error("buffer type", love::graphics::getConstants(bufferusage), type);
  }
  const auto flag = static_cast<love::uint32>(1) << static_cast<love::uint32>(bufferusage);
  return (static_cast<love::uint32>(t.getUsageFlags()) & flag) != 0;
}

bool buffer_legacy_vertex_bindings(const Buffer &t) { return t.hasLegacyVertexBindings(); }

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_optdatausage, luax_optbuffersettings, luax_newbuffer,
// and w_newBuffer (vendor/love/src/modules/graphics/wrap_Graphics.cpp:
// 1716-1981), and changed to read the declarations and settings
// Lota::Graphics::Buffer passes where LÖVE reads Lua tables.

// luax_optdatausage (lines 1716-1724): the usage hint +name+ names, or
// +fallback+ for nil.
love::graphics::BufferDataUsage data_usage(const std::optional<std::string> &name,
                                           love::graphics::BufferDataUsage fallback) {
  love::graphics::BufferDataUsage usage = fallback;
  if (name.has_value() && !love::graphics::getConstant(name->c_str(), usage)) {
    raise_enum_error("usage hint", love::graphics::getConstants(usage), *name);
  }
  return usage;
}

// An optional name, or nothing when it is nil.
std::optional<std::string> optional_name(const Rice::Object &value) {
  if (ruby::is_nil(value)) {
    return std::nullopt;
  }
  return Rice::detail::From_Ruby<std::string>().convert(value.value());
}

// luax_newbuffer (lines 1845-1951): the buffer of declarations holding
// content, a Data, a table of elements or of numbers, or the number of
// elements, which start zeroed. +arguments+ lists the declarations, the
// content, the names of the uses it is for, and the settings table's
// +usage+ and +debugname+, each nil when left out.
Buffer *new_buffer(Rice::Array list) {
  const Rice::Array arguments = std::move(list);
  const Values given_arguments = ruby::elements(arguments);
  const Rice::Array formats(at(given_arguments, 0).value());
  const Rice::Object given = at(given_arguments, 1);
  const Rice::Array names(at(given_arguments, 2).value());
  const std::optional<std::string> usage = optional_name(at(given_arguments, 3));
  const std::optional<std::string> debugname = optional_name(at(given_arguments, 4));
  Graphics &instance = created_graphics();

  Buffer::Settings settings(0, love::graphics::BUFFERDATAUSAGE_DYNAMIC);
  for (const Rice::Object &name : ruby::elements(names)) {
    const auto text = Rice::detail::From_Ruby<std::string>().convert(name.value());
    love::graphics::BufferUsage bufferusage = love::graphics::BUFFERUSAGE_MAX_ENUM;
    if (!love::graphics::getConstant(text.c_str(), bufferusage)) {
      raise_enum_error("buffer type", love::graphics::getConstants(bufferusage), text);
    }
    settings.usageFlags = static_cast<love::graphics::BufferUsageFlags>(
        settings.usageFlags | (1U << static_cast<unsigned>(bufferusage)));
  }
  settings.dataUsage = data_usage(usage, settings.dataUsage);
  if (debugname.has_value()) {
    settings.debugName = *debugname;
  }

  const std::vector<Buffer::DataDeclaration> format = declarations_of(formats);
  std::size_t ncomponents = 0;
  for (const Buffer::DataDeclaration &decl : format) {
    ncomponents +=
        static_cast<std::size_t>(love::graphics::getDataFormatInfo(decl.format).components);
  }

  std::size_t arraylength = 0;
  std::size_t bytesize = 0;
  const void *initialdata = nullptr;
  Values table;
  bool tableoftables = false;

  if (is_data(given)) {
    const auto *data = Rice::detail::From_Ruby<love::Data *>().convert(given.value());
    initialdata = data->getData();
    bytesize = data->getSize();
  } else if (ruby::is_array(given)) {
    table = check_table(given);
    arraylength = table.size();
    tableoftables = ruby::is_array(at(table, 0));
    if (!tableoftables && ncomponents > 0) {
      if (arraylength % ncomponents != 0) {
        throw love::Exception(
            "Array length in flat array variant of love.graphics.newBuffer must be a multiple "
            "of the total number of components (%d)",
            static_cast<int>(ncomponents));
      }
      arraylength /= ncomponents;
    }
  } else {
    if (!ruby::is_numeric(given)) {
      raise_expected(given, "Integer");
    }
    const auto length = Rice::detail::From_Ruby<long long>().convert(given.value());
    if (length <= 0) {
      raise_argument_error("number of elements must be greater than 0");
    }
    arraylength = static_cast<std::size_t>(length);
    settings.zeroInitialize = true;
  }

  const love::StrongRef<Buffer> buffer(
      instance.newBuffer(settings, format, initialdata, bytesize, arraylength),
      love::Acquire::NORETAIN);

  if (ruby::is_array(given)) {
    const Buffer::Mapper mapper(*buffer);
    const std::span<std::byte> bytes(static_cast<std::byte *>(mapper.data), buffer->getSize());
    write_elements(buffer->getDataMembers(), table, tableoftables, 0, arraylength,
                   buffer->getArrayStride(), bytes);
  }

  buffer->retain();
  return buffer.get();
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from the functions of vendor/love/src/modules/graphics/
// wrap_Mesh.cpp, and changed as the buffer functions above are.

// The vertex data of +t+, as a span of its bytes.
std::span<std::byte> vertex_bytes(Mesh &t) {
  return {static_cast<std::byte *>(t.getVertexData()), t.getVertexCount() * t.getVertexStride()};
}

// w_Mesh_setVertices (lines 40-123): the data, a Data or a table of
// vertices, to the vertices from +start+, counting from 1, +count+ of
// them, which +arguments+ lists in that order, each nil when left out.
void mesh_set_vertices(Mesh &t, Rice::Array list) {
  require_main_thread(MODULE);
  const Rice::Array arguments = std::move(list);
  const Values given = ruby::elements(arguments);
  const Rice::Object data = at(given, 0);
  const std::optional<double> start = optional_argument(at(given, 1));
  const std::optional<double> count_given = optional_argument(at(given, 2));
  const int vertstart = static_cast<int>(start.value_or(1.0)) - 1;

  int vertcount = -1;
  if (count_given.has_value()) {
    vertcount = static_cast<int>(*count_given);
    if (vertcount <= 0) {
      throw love::Exception("Vertex count must be greater than 0.");
    }
  }

  const std::size_t stride = t.getVertexStride();
  const std::size_t byteoffset = static_cast<std::size_t>(vertstart) * stride;
  const int totalverts = static_cast<int>(t.getVertexCount());

  if (vertstart >= totalverts || vertstart < 0) {
    throw love::Exception("Invalid vertex start index (must be between 1 and %d)", totalverts);
  }

  if (is_data(data)) {
    const auto *d = Rice::detail::From_Ruby<love::Data *>().convert(data.value());

    vertcount = vertcount >= 0 ? vertcount : (totalverts - vertstart);
    if (vertstart + vertcount > totalverts) {
      throw love::Exception("Too many vertices (expected at most %d, got %d)",
                            totalverts - vertstart, vertcount);
    }

    const std::size_t datasize =
        std::min(d->getSize(), static_cast<std::size_t>(vertcount) * stride);
    std::memcpy(vertex_bytes(t).subspan(byteoffset).data(), d->getData(), datasize);

    t.setVertexDataModified(byteoffset, datasize);
    t.flush();
    return;
  }

  const Values table = check_table(data);
  const auto tablelen = static_cast<int>(table.size());

  vertcount = vertcount >= 0 ? std::min(vertcount, tablelen) : tablelen;
  if (vertstart + vertcount > totalverts) {
    throw love::Exception("Too many vertices (expected at most %d, got %d)", totalverts - vertstart,
                          vertcount);
  }

  const std::vector<Buffer::DataMember> &vertexformat = t.getVertexFormat();
  const std::span<std::byte> bytes = vertex_bytes(t);
  for (std::size_t i = 0; std::cmp_less(i, vertcount); i++) {
    write_element(vertexformat, check_table(at(table, i)),
                  bytes.subspan(byteoffset + (i * stride), stride));
  }

  t.setVertexDataModified(byteoffset, static_cast<std::size_t>(vertcount) * stride);
  t.flush();
}

// The bytes of the vertex +index+, counting from 1, and where they begin,
// after checkVertexDataOffset has checked the index and that the Mesh has
// vertex data of its own.
std::span<std::byte> vertex_at(Mesh &t, long long index, std::size_t *offset) {
  const std::size_t vertindex = static_cast<std::size_t>(index) - 1;
  auto *data = static_cast<std::byte *>(t.checkVertexDataOffset(vertindex, offset));
  return {data, t.getVertexStride()};
}

// w_Mesh_setVertex (lines 125-168): the numbers of +row+ to the vertex
// +index+, counting from 1.
void mesh_set_vertex(Mesh &t, long long index, Rice::Array row) {
  require_main_thread(MODULE);
  const Rice::Array numbers = std::move(row);
  std::size_t offset = 0;
  const std::span<std::byte> vertex = vertex_at(t, index, &offset);
  write_element(t.getVertexFormat(), ruby::elements(numbers), vertex);
  t.setVertexDataModified(offset, t.getVertexStride());
}

// w_Mesh_getVertex (lines 170-189): the numbers of the vertex +index+.
Rice::Array mesh_vertex(Mesh &t, long long index) {
  require_main_thread(MODULE);
  const std::span<std::byte> vertex = vertex_at(t, index, nullptr);
  return read_element(t.getVertexFormat(), vertex);
}

// The attribute +attribindex+, counting from 1, of the Mesh's vertex
// format (lines 197-203 and 221-227).
const Buffer::DataMember &attribute_at(const Mesh &t, long long attribindex) {
  const auto &vertexformat = t.getVertexFormat();
  const int index = static_cast<int>(attribindex) - 1;
  if (index < 0 || std::cmp_greater_equal(index, vertexformat.size())) {
    throw love::Exception("Invalid vertex attribute index: %d", index + 1);
  }
  return vertexformat.at(static_cast<std::size_t>(index));
}

// w_Mesh_setVertexAttribute (lines 191-213): the numbers of +arguments+
// after the first two to the attribute the second names of the vertex the
// first names, each counting from 1.
void mesh_set_vertex_attribute(Mesh &t, Rice::Array list) {
  require_main_thread(MODULE);
  const Rice::Array arguments = std::move(list);
  const Values given = ruby::elements(arguments);
  const Buffer::DataMember &member = attribute_at(t, check_integer(at(given, 1)));
  std::size_t offset = 0;
  const std::span<std::byte> vertex = vertex_at(t, check_integer(at(given, 0)), &offset);
  write_member(member.decl.format, Cursor{.row = given, .start = 2}, vertex.subspan(member.offset));
  t.setVertexDataModified(offset + member.offset, member.size);
}

// w_Mesh_getVertexAttribute (lines 215-233): the numbers of the attribute
// the second of +position+ names of the vertex the first names.
Rice::Array mesh_vertex_attribute(Mesh &t, Rice::Array list) {
  require_main_thread(MODULE);
  const Rice::Array position = std::move(list);
  const Values given = ruby::elements(position);
  const Buffer::DataMember &member = attribute_at(t, check_integer(at(given, 1)));
  const std::span<std::byte> vertex = vertex_at(t, check_integer(at(given, 0)), nullptr);
  Rice::Array numbers;
  read_member(member.decl.format, numbers, vertex.subspan(member.offset));
  return numbers;
}

// w_Mesh_getVertexFormat (lines 242-281): the name, location, format,
// array length, and offset of each attribute.
Rice::Array mesh_vertex_format(const Mesh &t) {
  require_main_thread(MODULE);
  Rice::Array members;
  for (const Buffer::DataMember &member : t.getVertexFormat()) {
    Rice::Array fields;
    fields.push(member.decl.name, false);
    fields.push(member.decl.bindingLocation, false);
    fields.push(format_name(member.decl.format), false);
    fields.push(member.decl.arrayLength, false);
    fields.push(member.offset, false);
    members.push(fields, false);
  }
  return members;
}

// An attribute named by a String, or by its binding location (lines
// 283-316, which tell them apart by lua_type).
bool names_attribute(const Rice::Object &attribute) { return ruby::is_string(attribute); }

int location_of(const Rice::Object &attribute) {
  if (!ruby::is_numeric(attribute)) {
    raise_expected(attribute, "Integer");
  }
  return Rice::detail::From_Ruby<int>().convert(attribute.value());
}

std::string name_of(const Rice::Object &attribute) {
  return Rice::detail::From_Ruby<std::string>().convert(attribute.value());
}

// w_Mesh_setAttributeEnabled (lines 283-298).
void mesh_set_attribute_enabled(Mesh &t, Rice::Object name, bool enable) {
  require_main_thread(MODULE);
  const Rice::Object attribute = std::move(name);
  if (names_attribute(attribute)) {
    t.setAttributeEnabled(name_of(attribute), enable);
  } else {
    t.setAttributeEnabled(location_of(attribute), enable);
  }
}

// w_Mesh_isAttributeEnabled (lines 300-316).
bool mesh_attribute_enabled(const Mesh &t, Rice::Object name) {
  require_main_thread(MODULE);
  const Rice::Object attribute = std::move(name);
  if (names_attribute(attribute)) {
    return t.isAttributeEnabled(name_of(attribute));
  }
  return t.isAttributeEnabled(location_of(attribute));
}

// w_Mesh_attachAttribute (lines 318-362): the attribute +attribute+ of
// this Mesh, from the attribute +attach+ of +source+, a Buffer or a Mesh
// with a vertex buffer of its own, from the element +startindex+ of it,
// counting from 1, advancing +step+.
void mesh_attach_attribute(Mesh &t, Rice::Object named, Rice::Object from,
                           const std::optional<std::string> &step_name, Rice::Object attach_as,
                           std::optional<long long> startindex) {
  require_main_thread(MODULE);
  const Rice::Object attribute = std::move(named);
  const Rice::Object source = std::move(from);
  const Rice::Object attach = std::move(attach_as);
  const bool by_name = names_attribute(attribute);
  const std::string name = by_name ? name_of(attribute) : std::string();
  const int location = by_name ? -1 : location_of(attribute);

  Buffer *buffer = nullptr;
  Mesh *mesh = nullptr;
  if (ruby::is_kind_of(source, Rice::Data_Type<Buffer>::klass())) {
    buffer = Rice::detail::From_Ruby<Buffer *>().convert(source.value());
  } else {
    if (!ruby::is_kind_of(source, Rice::Data_Type<Mesh>::klass())) {
      raise_expected(source, "Lota::Graphics::Mesh");
    }
    mesh = Rice::detail::From_Ruby<Mesh *>().convert(source.value());
    buffer = mesh->getVertexBuffer();
    if (buffer == nullptr) {
      throw love::Exception("Mesh does not have its own vertex buffer.");
    }
  }

  love::graphics::AttributeStep step = love::graphics::STEP_PER_VERTEX;
  if (step_name.has_value() && !love::graphics::getConstant(step_name->c_str(), step)) {
    raise_enum_error("vertex attribute step", love::graphics::getConstants(step), *step_name);
  }

  const int start = static_cast<int>(startindex.value_or(1)) - 1;
  if (by_name) {
    const std::string attachname = ruby::is_nil(attach) ? name : name_of(attach);
    t.attachAttribute(name, buffer, mesh, attachname, start, step);
  } else {
    const int attachlocation = ruby::is_nil(attach) ? location : location_of(attach);
    t.attachAttribute(location, buffer, mesh, attachlocation, start, step);
  }
}

// w_Mesh_setVertexMap with a table (lines 464-486): the indices, counting
// from 1.
void mesh_set_vertex_map(Mesh &t, Rice::Array indices) {
  require_main_thread(MODULE);
  const Rice::Array list = std::move(indices);
  std::vector<love::uint32> vertexmap;
  vertexmap.reserve(static_cast<std::size_t>(ruby::length(list)));
  for (const Rice::Object &index : ruby::elements(list)) {
    if (!ruby::is_numeric(index)) {
      raise_expected(index, "Integer");
    }
    vertexmap.push_back(
        static_cast<love::uint32>(Rice::detail::From_Ruby<long long>().convert(index.value()) - 1));
  }
  t.setVertexMap(vertexmap);
}

// w_Mesh_setVertexMap with a Data (lines 440-462): its bytes as indices
// of +type+, +count+ of them, all of them unless given.
void mesh_set_vertex_map_data(Mesh &t, const love::Data *data, const std::string &type,
                              std::optional<long long> count_given) {
  require_main_thread(MODULE);
  love::graphics::IndexDataType indextype{};
  if (!love::graphics::getConstant(type.c_str(), indextype)) {
    raise_enum_error("index data type", love::graphics::getConstants(indextype), type);
  }
  const std::size_t datatypesize = love::graphics::getIndexDataSize(indextype);
  const long long indexcount =
      count_given.value_or(static_cast<long long>(data->getSize() / datatypesize));
  if (indexcount < 1 || static_cast<std::size_t>(indexcount) * datatypesize > data->getSize()) {
    throw love::Exception("Invalid index count: %d", static_cast<int>(indexcount));
  }
  t.setVertexMap(indextype, data->getData(), static_cast<std::size_t>(indexcount) * datatypesize);
}

// w_Mesh_setVertexMap without a map (lines 434-438): the default order.
void mesh_clear_vertex_map(Mesh &t) {
  require_main_thread(MODULE);
  t.setVertexMap();
}

// w_Mesh_getVertexMap (lines 488-513): the indices, counting from 1, or
// nil without a map.
Rice::Object mesh_vertex_map(const Mesh &t) {
  require_main_thread(MODULE);
  std::vector<love::uint32> vertex_map;
  if (!t.getVertexMap(vertex_map)) {
    return ruby::nil();
  }
  Rice::Array indices;
  for (const love::uint32 index : vertex_map) {
    indices.push(static_cast<long long>(index) + 1, false);
  }
  return indices;
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_checkmeshdrawmode, newStandardMesh, newCustomMesh,
// luax_checkbufferattributetable, newMeshFromBuffers, and w_newMesh
// (vendor/love/src/modules/graphics/wrap_Graphics.cpp:1983-2320), and
// changed to read the vertices, formats, and attributes Lota::Graphics::Mesh
// passes where LÖVE reads Lua tables. Mesh.new chooses among the three
// forms as w_newMesh does.

// luax_checkmeshdrawmode (lines 1983-1992).
love::graphics::PrimitiveType mesh_draw_mode(const std::string &name) {
  love::graphics::PrimitiveType mode = love::graphics::PRIMITIVE_TRIANGLES;
  if (!love::graphics::getConstant(name.c_str(), mode)) {
    raise_enum_error("mesh draw mode", love::graphics::getConstants(mode), name);
  }
  return mode;
}

// The most a color component of a vertex stores (lines 2028-2031).
constexpr double COLOR_BYTE_MAX = 255.0;

// The places of the numbers of a standard vertex in its row (lines
// 2018-2031).
constexpr std::size_t FIELD_X = 0;
constexpr std::size_t FIELD_Y = 1;
constexpr std::size_t FIELD_S = 2;
constexpr std::size_t FIELD_T = 3;
constexpr std::size_t FIELD_RED = 4;
constexpr std::size_t FIELD_GREEN = 5;
constexpr std::size_t FIELD_BLUE = 6;
constexpr std::size_t FIELD_ALPHA = 7;

// A color component as a vertex stores it (lines 2028-2031).
love::uint8 color_byte(const Rice::Object &value) {
  return static_cast<love::uint8>(std::min(std::max(optional_number(value, 1.0), 0.0), 1.0) *
                                  COLOR_BYTE_MAX);
}

// newStandardMesh (lines 1994-2050): a Mesh of position, texture
// coordinates, and color, from a table of vertices of up to eight numbers
// or the number of vertices.
Mesh *new_standard_mesh(Rice::Object content, const std::string &mode,
                        const std::optional<std::string> &usage_name) {
  const Rice::Object given = std::move(content);
  Graphics &instance = created_graphics();
  const love::graphics::PrimitiveType drawmode = mesh_draw_mode(mode);
  const love::graphics::BufferDataUsage usage =
      data_usage(usage_name, love::graphics::BUFFERDATAUSAGE_DYNAMIC);
  const std::vector<Buffer::DataDeclaration> format = Mesh::getDefaultVertexFormat();

  if (ruby::is_array(given)) {
    std::vector<love::graphics::Vertex> vertices;
    for (const Rice::Object &entry : ruby::elements(Rice::Array(given.value()))) {
      if (!ruby::is_array(entry)) {
        ruby::raise_type_error("wrong argument type " + ruby::class_name(entry) +
                               " (expected table of tables)");
      }
      const Values row = check_table(entry);
      love::graphics::Vertex v{};
      v.x = static_cast<float>(check_number(at(row, FIELD_X)));
      v.y = static_cast<float>(check_number(at(row, FIELD_Y)));
      v.s = static_cast<float>(optional_number(at(row, FIELD_S), 0.0));
      v.t = static_cast<float>(optional_number(at(row, FIELD_T), 0.0));
      v.color.r = color_byte(at(row, FIELD_RED));
      v.color.g = color_byte(at(row, FIELD_GREEN));
      v.color.b = color_byte(at(row, FIELD_BLUE));
      v.color.a = color_byte(at(row, FIELD_ALPHA));
      vertices.push_back(v);
    }
    return instance.newMesh(format, vertices.data(),
                            vertices.size() * sizeof(love::graphics::Vertex), drawmode, usage);
  }

  if (!ruby::is_numeric(given)) {
    raise_expected(given, "Integer");
  }
  return instance.newMesh(format, Rice::detail::From_Ruby<int>().convert(given.value()), drawmode,
                          usage);
}

// newCustomMesh (lines 2052-2206): a Mesh of the vertex format
// (declarations_of), from a table of vertices, a Data, or the number of
// vertices, in a draw mode, with a usage hint or nil, which +arguments+
// lists in that order, the format first.
Mesh *new_custom_mesh(Rice::Array list) {
  const Rice::Array arguments = std::move(list);
  const Values given_arguments = ruby::elements(arguments);
  const Rice::Array formats(at(given_arguments, 0).value());
  const Rice::Object given = at(given_arguments, 1);
  const std::string mode =
      Rice::detail::From_Ruby<std::string>().convert(at(given_arguments, 2).value());
  const std::optional<std::string> usage_name = optional_name(at(given_arguments, 3));
  Graphics &instance = created_graphics();
  const love::graphics::PrimitiveType drawmode = mesh_draw_mode(mode);
  const love::graphics::BufferDataUsage usage =
      data_usage(usage_name, love::graphics::BUFFERDATAUSAGE_DYNAMIC);
  const std::vector<Buffer::DataDeclaration> vertexformat = declarations_of(formats);

  Mesh *created = nullptr;
  if (ruby::is_numeric(given)) {
    created = instance.newMesh(vertexformat, Rice::detail::From_Ruby<int>().convert(given.value()),
                               drawmode, usage);
  } else if (is_data(given)) {
    const auto *data = Rice::detail::From_Ruby<love::Data *>().convert(given.value());
    created = instance.newMesh(vertexformat, data->getData(), data->getSize(), drawmode, usage);
  } else {
    const Values vertices = check_table(given);
    if (!ruby::is_array(at(vertices, 0))) {
      raise_argument_error("expected table of tables");
    }
    created = instance.newMesh(vertexformat, static_cast<int>(vertices.size()), drawmode, usage);
    const love::StrongRef<Mesh> guard(created, love::Acquire::NORETAIN);
    const std::size_t stride = created->getVertexStride();
    write_elements(created->getVertexFormat(), vertices, true, 0, vertices.size(), stride,
                   vertex_bytes(*created));
    created->setVertexDataModified(0, stride * vertices.size());
    created->flush();
    created->retain();
  }
  return created;
}

// The places of an attribute's fields in the Array
// Lota::Graphics::Mesh passes (lines 2226-2274).
constexpr std::size_t ATTRIBUTE_BUFFER = 0;
constexpr std::size_t ATTRIBUTE_LOCATION = 1;
constexpr std::size_t ATTRIBUTE_NAME = 2;
constexpr std::size_t ATTRIBUTE_STEP = 3;
constexpr std::size_t ATTRIBUTE_LOCATION_IN_BUFFER = 4;
constexpr std::size_t ATTRIBUTE_NAME_IN_BUFFER = 5;
constexpr std::size_t ATTRIBUTE_START_INDEX = 6;

// luax_checkbufferattributetable (lines 2226-2274): the attribute of a
// Buffer an Array of its buffer, location, name, step, location in the
// buffer, name in the buffer, and start index, counting from 1, describes.
Mesh::BufferAttribute buffer_attribute(const Rice::Object &entry) {
  const Values fields = check_table(entry);
  Mesh::BufferAttribute attrib;
  attrib.step = love::graphics::STEP_PER_VERTEX;
  attrib.enabled = true;

  const Rice::Object buffer = at(fields, ATTRIBUTE_BUFFER);
  if (!ruby::is_kind_of(buffer, Rice::Data_Type<Buffer>::klass())) {
    raise_expected(buffer, "Lota::Graphics::Buffer");
  }
  attrib.buffer.set(Rice::detail::From_Ruby<Buffer *>().convert(buffer.value()));
  attrib.bindingLocation = location_of(at(fields, ATTRIBUTE_LOCATION));
  if (!ruby::is_nil(at(fields, ATTRIBUTE_NAME))) {
    attrib.name = name_of(at(fields, ATTRIBUTE_NAME));
  }
  if (!ruby::is_nil(at(fields, ATTRIBUTE_STEP))) {
    const std::string step = name_of(at(fields, ATTRIBUTE_STEP));
    if (!love::graphics::getConstant(step.c_str(), attrib.step)) {
      raise_enum_error("vertex attribute step", love::graphics::getConstants(attrib.step), step);
    }
  }
  attrib.bindingLocationInBuffer = ruby::is_nil(at(fields, ATTRIBUTE_LOCATION_IN_BUFFER))
                                       ? attrib.bindingLocation
                                       : location_of(at(fields, ATTRIBUTE_LOCATION_IN_BUFFER));
  attrib.nameInBuffer = ruby::is_nil(at(fields, ATTRIBUTE_NAME_IN_BUFFER))
                            ? attrib.name
                            : name_of(at(fields, ATTRIBUTE_NAME_IN_BUFFER));
  attrib.startArrayIndex = ruby::is_nil(at(fields, ATTRIBUTE_START_INDEX))
                               ? 0
                               : location_of(at(fields, ATTRIBUTE_START_INDEX)) - 1;
  return attrib;
}

// newMeshFromBuffers (lines 2276-2295): a Mesh of attributes of Buffers.
Mesh *new_mesh_from_buffers(Rice::Array attributes, const std::string &mode) {
  const Rice::Array entries = std::move(attributes);
  Graphics &instance = created_graphics();
  std::vector<Mesh::BufferAttribute> attribs;
  for (const Rice::Object &entry : ruby::elements(entries)) {
    attribs.push_back(buffer_attribute(entry));
  }
  return instance.newMesh(attribs, mesh_draw_mode(mode));
}

// w_Mesh_getAttachedAttributes (wrap_Mesh.cpp:374-416), which returns an
// empty table at the pinned commit: it sets each attribute's table into
// itself (lua_rawseti(L, -1, i + 1), line 412) rather than into the result.
Rice::Array mesh_attached_attributes(const Mesh & /*t*/) {
  require_main_thread(MODULE);
  return {};
}

bool mesh_legacy_vertex_bindings(const Mesh &t) {
  return t.getVertexBuffer() != nullptr && t.getVertexBuffer()->hasLegacyVertexBindings();
}

// SPDX-SnippetEnd

} // namespace

void define_buffer(const Rice::Module &native) {
  // Their other methods are generated (ext/lota/native/generated/graphics.cpp).
  define_engine_class<Buffer>(native, "Buffer")
      .define_method("set_array_data", &buffer_set_array_data, Rice::Arg("arguments"))
      .define_method("clear", &buffer_clear, Rice::Arg("range"))
      .define_method("buffer_type?", &buffer_is_buffer_type, Rice::Arg("usage"))
      .define_method("format", &buffer_format)
      .define_method("legacy_vertex_bindings?", &buffer_legacy_vertex_bindings);
  define_engine_class<Mesh>(native, "Mesh")
      .define_method("set_vertices", &mesh_set_vertices, Rice::Arg("arguments"))
      .define_method("set_vertex", &mesh_set_vertex, Rice::Arg("index"), Rice::Arg("row"))
      .define_method("vertex", &mesh_vertex, Rice::Arg("index"))
      .define_method("set_vertex_attribute", &mesh_set_vertex_attribute, Rice::Arg("arguments"))
      .define_method("vertex_attribute", &mesh_vertex_attribute, Rice::Arg("position"))
      .define_method("vertex_format", &mesh_vertex_format)
      .define_method("set_attribute_enabled", &mesh_set_attribute_enabled, Rice::Arg("attribute"),
                     Rice::Arg("enable"))
      .define_method("attribute_enabled?", &mesh_attribute_enabled, Rice::Arg("attribute"))
      .define_method("attach_attribute", &mesh_attach_attribute, Rice::Arg("attribute"),
                     Rice::Arg("source"), Rice::Arg("step") = std::optional<std::string>(),
                     Rice::Arg("attach") = Rice::Object(),
                     Rice::Arg("startindex") = std::optional<long long>())
      .define_method("set_vertex_map", &mesh_set_vertex_map, Rice::Arg("indices"))
      .define_method("set_vertex_map_data", &mesh_set_vertex_map_data, Rice::Arg("data"),
                     Rice::Arg("type"), Rice::Arg("count") = std::optional<long long>())
      .define_method("clear_vertex_map", &mesh_clear_vertex_map)
      .define_method("vertex_map", &mesh_vertex_map)
      .define_method("attached_attributes", &mesh_attached_attributes)
      .define_method("legacy_vertex_bindings?", &mesh_legacy_vertex_bindings);

  Rice::define_module_under(native, "Graphics")
      .define_singleton_function("new_buffer", &new_buffer, Rice::Arg("arguments"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function(
          "new_standard_mesh", &new_standard_mesh, Rice::Arg("content"), Rice::Arg("mode"),
          Rice::Arg("usage") = std::optional<std::string>(), Rice::Return().takeOwnership())
      .define_singleton_function("new_custom_mesh", &new_custom_mesh, Rice::Arg("arguments"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_mesh_from_buffers", &new_mesh_from_buffers,
                                 Rice::Arg("attributes"), Rice::Arg("mode"),
                                 Rice::Return().takeOwnership());
}

} // namespace lota::native
