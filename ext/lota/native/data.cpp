// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/data.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/int.h"
#include "data/DataModule.h"
#include "thread/threads.h"

#include <cstddef>
#include <cstring>
#include <optional>
#include <span>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace lota::native {

namespace {

using love::data::DataModule;

// luaopen_love_data (vendor/love/src/modules/data/wrap_DataModule.cpp:
// 445-464) creates the module once; it then lives as long as the process,
// as LÖVE's lives until the game quits.
void open() { open_module<DataModule, DataModule>(love::Module::M_DATA); }

// Whether the module is open, as a game asks with "if love.data".
bool is_open() { return love::Module::getInstance<DataModule>(love::Module::M_DATA) != nullptr; }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w_Data_getString (vendor/love/src/modules/data/wrap_Data.cpp:40-59):
// +size+ of the Data's bytes from +offset+, or every one from +offset+ on.
// LÖVE reads both as Lua numbers and truncates them to int64s.
std::string data_string(const love::Data &data, double offset_number,
                        std::optional<double> size_number) {
  const auto offset = static_cast<love::int64>(offset_number);
  const auto total = static_cast<love::int64>(data.getSize());
  const love::int64 size =
      size_number.has_value() ? static_cast<love::int64>(*size_number) : total - offset;

  if (size <= 0) {
    throw love::Exception("Invalid size parameter (must be greater than 0)");
  }

  if (offset < 0 || offset + size > total) {
    throw love::Exception("The given offset and size parameters don't fit within the Data's size.");
  }

  const std::span<const char> bytes(static_cast<const char *>(data.getData()), data.getSize());
  const std::span<const char> part =
      bytes.subspan(static_cast<std::size_t>(offset), static_cast<std::size_t>(size));
  return {part.begin(), part.end()};
}

// w_Data_performAtomic (wrap_Data.cpp:82-100), with +call+ the block, as
// a Proc, and then its arguments, which Lota::Data#perform_atomic gathers
// into one Array: calls the block with the arguments while it holds the
// Data's lock, and returns what the block returns. A Ruby error the block
// raises leaves the lock on its way out, as Lua's pcall does there, and
// goes on.
Rice::Object perform_atomic(love::Data &data, Rice::Array call_given) {
  const Rice::Array call = std::move(call_given);
  const std::vector<Rice::Object> given = ruby::elements(call);
  Rice::Object block = given.empty() ? ruby::nil() : given.front();
  Rice::Array arguments;
  for (std::size_t i = 1; i < given.size(); i++) {
    arguments.push(given.at(i), false);
  }
  if (block.is_nil()) {
    ruby::raise_argument_error("no block given");
  }
  const love::thread::Lock lock(data.getMutex());
  return block.vcall("call", arguments);
}

// w_Data_getT (wrap_Data.cpp:102-121), which getFloat, getDouble,
// getInt8 to getInt32, and getUInt8 to getUInt32 call with their C types: +count+ values
// of type T from byte +offset+, as an Array, since it returns several (ADR
// 001, rule 4): Integers for the integer types and Floats for float and
// double (rule 14), where LÖVE pushes each as a Lua number. Offset and
// count are read as LÖVE reads them, a Lua number truncated to an int64
// and an int.
template <typename T>
Rice::Array data_values(const love::Data &data, double offset_number,
                        std::optional<int> count_given) {
  const int count = count_given.value_or(1);
  const auto offset = static_cast<love::int64>(offset_number);

  if (count <= 0) {
    throw love::Exception("Invalid count parameter (must be greater than 0)");
  }

  if (offset < 0 || static_cast<std::size_t>(offset) + (sizeof(T) * count) > data.getSize()) {
    throw love::Exception(
        "The given offset and count parameters don't fit within the Data's size.");
  }

  const std::span<const std::byte> bytes(static_cast<const std::byte *>(data.getData()),
                                         data.getSize());
  Rice::Array results;
  for (int i = 0; i < count; i++) {
    T value{};
    std::memcpy(&value,
                bytes.subspan(static_cast<std::size_t>(offset) + (sizeof(T) * i), sizeof(T)).data(),
                sizeof(T));
    if constexpr (std::is_integral_v<T>) {
      results.push(static_cast<long long>(value), false);
    } else {
      results.push(static_cast<double>(value), false);
    }
  }
  return results;
}

// SPDX-SnippetEnd

} // namespace

void define_data(const Rice::Module &native) {
  // Its size is generated (ext/lota/native/generated/data.cpp). Data is
  // also love.data's module, as Lota::Data is (ADR 001, section 7), so it
  // opens and answers whether it is open.
  define_engine_class<love::Data>(native, "Data")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_method("string", &data_string, Rice::Arg("offset") = 0.0,
                     Rice::Arg("size") = std::optional<double>())
      .define_method("perform_atomic", &perform_atomic, Rice::Arg("call"))
      .define_method("float", &data_values<float>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("double", &data_values<double>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("int8", &data_values<love::int8>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("int16", &data_values<love::int16>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("int32", &data_values<love::int32>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("uint8", &data_values<love::uint8>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("uint16", &data_values<love::uint16>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>())
      .define_method("uint32", &data_values<love::uint32>, Rice::Arg("offset"),
                     Rice::Arg("count") = std::optional<int>());
}

} // namespace lota::native
