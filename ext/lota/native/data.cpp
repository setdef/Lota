// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/data.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/luajit.hpp"
#include "native/ruby.hpp"
#include "native/signal.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h"
#include "common/int.h"
#include "data/ByteData.h"
#include "data/CompressedData.h"
#include "data/Compressor.h"
#include "data/DataModule.h"
#include "data/DataView.h"
#include "data/HashFunction.h"

#include <algorithm>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <map>
#include <optional>
#include <span>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace lota::native {

namespace {

using love::data::ByteData;
using love::data::CompressedData;
using love::data::Compressor;
using love::data::ContainerType;
using love::data::DataModule;
using love::data::DataView;
using love::data::EncodeFormat;
using love::data::HashFunction;

// luaopen_love_data (vendor/love/src/modules/data/wrap_DataModule.cpp:
// 445-464) creates the module once; it then lives as long as the process,
// as LÖVE's lives until the game quits.
void open() { open_module<DataModule, DataModule>(love::Module::M_DATA); }

// Whether the module is open, as a game asks with "if love.data".
bool is_open() { return love::Module::getInstance<DataModule>(love::Module::M_DATA) != nullptr; }

// The module, as LÖVE's instance() macro reaches it (wrap_DataModule.cpp:
// 44), on any thread.
DataModule *instance() {
  auto *module = love::Module::getInstance<DataModule>(love::Module::M_DATA);
  if (module == nullptr) {
    throw love::Exception("Lota::Data is not open.");
  }
  return module;
}

// The bytes of +source+, a String or a Data, which Lota::Data passes on as
// it is given or as the Data's native object: a String's own bytes, as
// luaL_checklstring reads them, or the Data's, as luax_checktype<Data>
// does. Neither is copied; each lives as long as the argument does.
std::span<const char> bytes_of(const Rice::Object &source) {
  if (ruby::is_string(source)) {
    const Rice::String string(source.value());
    return {string.c_str(), string.length()};
  }
  const love::Data *data = Rice::detail::From_Ruby<love::Data *>().convert(source.value());
  if (data == nullptr) {
    ruby::raise_type_error("wrong argument type nil (expected String or Lota::Data)");
  }
  return {static_cast<const char *>(data->getData()), data->getSize()};
}

// The Ruby String of +size+ bytes at +bytes+, or an empty one for none.
Rice::Object string_of(const char *bytes, std::size_t size) {
  return {Rice::detail::To_Ruby<std::string>().convert(
      bytes == nullptr ? std::string() : std::string(bytes, size))};
}

// The wrapper of +data+, a Data the engine made, which it adopts.
Rice::Object adopted(love::Data *data) { return {Rice::detail::wrap_engine_object(data, true)}; }

// The wrapper of +data+, a ByteData the engine made, which it adopts, made
// as LÖVE pushes the ByteData its container "data" holds, with
// luax_pushtype(L, Data::type, data) (vendor/love/src/modules/data/
// wrap_DataModule.cpp:191, 238, 287, 345, 374, and 390): an object of
// LÖVE's root type Data, Lota::Native's class Data, which answers Data's
// methods and type and not ByteData's. luax_pushtype gives an object that
// already has a Proxy that one, as wrap_engine_object does.
Rice::Object adopted_as_data(love::Data *data) {
  return {Rice::detail::wrap_engine_object_as<love::Data>(data, true)};
}

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

// w_Data_getPointer (wrap_Data.cpp:61-66): the address of the Data's
// bytes, which LÖVE pushes as a lightuserdata, as an Integer, which
// Lota::Data#pointer and #ffi_pointer make a Fiddle::Pointer.
std::uintptr_t data_pointer(const love::Data &data) {
  return std::bit_cast<std::uintptr_t>(data.getData());
}

// The Data each Ruby thread holds with perform_atomic, in every Ractor,
// and how many times: while one thread holds a Data, every other that
// asks for it waits, without its GVL (Signal).
//
// LÖVE holds the Data's own mutex while performAtomic's function runs
// (wrap_Data.cpp:88). Lota does not hold it while Ruby runs. A thread
// that waited for it would wait with its GVL held: another Ruby thread of
// its Ractor, the one holding the Data, could never run to let it go, and
// a collection, which waits for every Ractor that holds its GVL, could
// never start, so a block that collected garbage would stop both for
// good. So perform_atomic keeps out every other perform_atomic of the
// Data, as LÖVE's does, and the mutex stays LÖVE's, for the engine's C++
// that takes it (GraphicsReadback.cpp:189, ImageRasterizer.cpp:95,
// BMFontRasterizer.cpp:350, and native/texture.cpp's copy of a texture's
// pixels into an ImageData), which a block no longer keeps out. LÖVE's other
// Data methods take no lock, so a block keeps them out in neither.
class Holds {
public:
  static Holds &instance() {
    static Holds holds;
    return holds;
  }

  void hold(const love::Data *data) {
    const ruby::ThreadId me = ruby::current_thread();
    while (true) {
      std::uint64_t seen = 0;
      {
        const auto lock = signal_.lock();
        Held &held = held_[data];
        if (held.owner == ruby::no_thread() || held.owner == me) {
          held.owner = me;
          held.depth++;
          return;
        }
        seen = signal_.count();
      }
      signal_.wait(seen, std::nullopt);
    }
  }

  void release(const love::Data *data) noexcept {
    const auto lock = signal_.lock();
    const auto found = held_.find(data);
    if (found == held_.end() || --found->second.depth > 0) {
      return;
    }
    held_.erase(found);
    signal_.changed();
  }

private:
  // The Ruby thread that holds a Data, which it compares by identity
  // alone, and how many times.
  struct Held {
    ruby::ThreadId owner = ruby::no_thread();
    int depth = 0;
  };

  Signal signal_;
  std::map<const love::Data *, Held> held_;
};

// Holds a Data for as long as it lives (Holds).
class Hold {
public:
  explicit Hold(const love::Data &data) : data_(&data) { Holds::instance().hold(data_); }
  Hold(const Hold &) = delete;
  Hold(Hold &&) = delete;
  Hold &operator=(const Hold &) = delete;
  Hold &operator=(Hold &&) = delete;
  ~Hold() { Holds::instance().release(data_); }

private:
  const love::Data *data_;
};

// w_Data_performAtomic (wrap_Data.cpp:82-100), with +call+ the block, as
// a Proc, and then its arguments, which Lota::Data#perform_atomic gathers
// into one Array: calls the block with the arguments while it holds the
// Data (Holds), and returns what the block returns. A Ruby error the block
// raises lets the Data go on its way out, as Lua's pcall does there, and
// goes on.
Rice::Object perform_atomic(const love::Data &data, Rice::Array call_given) {
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
  const Hold hold(data);
  return block.vcall("call", arguments);
}

// w_Data_getT (wrap_Data.cpp:102-121), which getFloat, getDouble,
// getInt8 to getInt32, and getUInt8 to getUInt32 call with their C types: +count+ values
// of type T from byte +offset+, as an Array, since it returns several (rule 4
// of doc/contributors/design/translation.md): Integers for the integer types
// and Floats for float and double (rule 14), where LÖVE pushes each as a Lua
// number. Offset and count are read as LÖVE reads them, a Lua number truncated
// to an int64 and an int.
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

// luax_checkcontainertype (wrap_DataModule.cpp:46-53): "data" or
// "string", the kind of value a love.data function returns.
ContainerType container_of(const std::string &name) {
  ContainerType ctype = love::data::CONTAINER_STRING;
  if (!love::data::getConstant(name.c_str(), ctype)) {
    raise_enum_error("container type", love::data::getConstants(ctype), name);
  }
  return ctype;
}

// The compressed data format +name+, as w_compress and w_decompress read
// it (wrap_DataModule.cpp:123-124 and 169-170).
Compressor::Format compressor_format_of(const std::string &name) {
  Compressor::Format format = Compressor::FORMAT_LZ4;
  if (!Compressor::getConstant(name.c_str(), format)) {
    raise_enum_error("compressed data format", Compressor::getConstants(format), name);
  }
  return format;
}

// The encode format +name+, which w_encode and w_decode call their
// "encode format" and "decode format" (wrap_DataModule.cpp:209-210 and
// 260-261), as +kind+ names it.
EncodeFormat encode_format_of(const char *kind, const std::string &name) {
  EncodeFormat format = love::data::ENCODE_BASE64;
  if (!love::data::getConstant(name.c_str(), format)) {
    raise_enum_error(kind, love::data::getConstants(format), name);
  }
  return format;
}

// The bytes the engine returns from new[] (wrap_DataModule.cpp:187-198,
// 230-249, and 279-298), which a ByteData takes over, as LÖVE's
// newByteData(bytes, size, true) does: that ByteData, pushed as a Data,
// for the container "data", or a String of its bytes, after which it is
// released and frees them, as LÖVE frees them with delete[] once it has
// pushed them. Where the engine returns none, an empty String, or a Data
// of no bytes, which the engine refuses.
Rice::Object result_of(ContainerType ctype, char *bytes, std::size_t size) {
  if (bytes == nullptr) {
    return ctype == love::data::CONTAINER_DATA ? adopted_as_data(instance()->newByteData(0))
                                               : string_of(nullptr, 0);
  }
  ByteData *data = instance()->newByteData(bytes, size, true);
  if (ctype == love::data::CONTAINER_DATA) {
    return adopted_as_data(data);
  }
  const love::StrongRef<ByteData> held(data, love::Acquire::NORETAIN);
  return string_of(static_cast<const char *>(data->getData()), data->getSize());
}

// luax_checkcontainertype, as w_pack calls it before it packs
// (wrap_DataModule.cpp:378): raises for a name that is not a container
// type.
void check_container(const std::string &container) { static_cast<void>(container_of(container)); }

// w_newByteData with a Data (wrap_DataModule.cpp:77-96): a copy of +size+
// of its bytes from +offset+, every byte from +offset+ on by default.
ByteData *new_byte_data_of_data(const love::Data *data, std::optional<love::int64> offset_given,
                                std::optional<love::int64> size_given) {
  if (data->getSize() > static_cast<std::size_t>(std::numeric_limits<love::int64>::max())) {
    throw love::Exception("Data's size is too large!");
  }
  const love::int64 offset = offset_given.value_or(0);
  if (offset < 0) {
    throw love::Exception("Offset argument must not be negative.");
  }
  const love::int64 size =
      size_given.value_or(static_cast<love::int64>(data->getSize()) - offset_given.value_or(0));
  if (size <= 0) {
    throw love::Exception("Size argument must be greater than zero.");
  }
  if (static_cast<std::size_t>(offset + size) > data->getSize()) {
    throw love::Exception("Offset and size arguments must fit within the given Data's size.");
  }
  const std::span<const char> bytes(static_cast<const char *>(data->getData()), data->getSize());
  return instance()->newByteData(bytes.subspan(static_cast<std::size_t>(offset)).data(),
                                 static_cast<std::size_t>(size));
}

// w_newByteData with a string (wrap_DataModule.cpp:97-102): a copy of its
// bytes.
ByteData *new_byte_data_of_string(const std::string &bytes) {
  return instance()->newByteData(bytes.data(), bytes.size());
}

// w_newByteData with a size (wrap_DataModule.cpp:103-109): that many
// bytes, each zero.
ByteData *new_byte_data_of_size(love::int64 size) {
  if (size <= 0) {
    throw love::Exception("Data size must be a positive number.");
  }
  return instance()->newByteData(static_cast<std::size_t>(size));
}

// w_newDataView (wrap_DataModule.cpp:55-71): a view of +size+ of
// +data+'s bytes from +offset+, every byte from +offset+ on by default.
DataView *new_data_view(love::Data *data, love::int64 offset,
                        std::optional<love::int64> size_given) {
  const love::int64 size = size_given.value_or(static_cast<love::int64>(data->getSize()) - offset);
  if (offset < 0 || size < 0) {
    throw love::Exception("DataView offset and size must not be negative.");
  }
  return instance()->newDataView(data, static_cast<std::size_t>(offset),
                                 static_cast<std::size_t>(size));
}

// w_compress (wrap_DataModule.cpp:116-149): +source+, a String or a Data,
// compressed at +level+, -1 for the format's default, as a CompressedData
// or its bytes as a String.
Rice::Object compress(const std::string &format_name, int level, const std::string &container,
                      Rice::Object source_given) {
  const Rice::Object source = std::move(source_given);
  const ContainerType ctype = container_of(container);
  const Compressor::Format format = compressor_format_of(format_name);
  const std::span<const char> raw = bytes_of(source);
  CompressedData *cdata = love::data::compress(format, raw.data(), raw.size(), level);
  if (ctype == love::data::CONTAINER_DATA) {
    return adopted(cdata);
  }
  const love::StrongRef<CompressedData> held(cdata, love::Acquire::NORETAIN);
  return string_of(static_cast<const char *>(cdata->getData()), cdata->getSize());
}

// w_decompress with a CompressedData (wrap_DataModule.cpp:151-163).
Rice::Object decompress_compressed_data(const std::string &container, CompressedData *data) {
  const ContainerType ctype = container_of(container);
  std::size_t rawsize = data->getDecompressedSize();
  return result_of(ctype, love::data::decompress(data, rawsize), rawsize);
}

// w_decompress with a format and a String or a Data (wrap_DataModule.cpp:
// 151-156 and 164-185).
Rice::Object decompress(const std::string &format_name, Rice::Object source_given,
                        const std::string &container) {
  const Rice::Object source = std::move(source_given);
  const ContainerType ctype = container_of(container);
  const Compressor::Format format = compressor_format_of(format_name);
  const std::span<const char> compressed = bytes_of(source);
  std::size_t rawsize = 0;
  char *rawbytes = love::data::decompress(format, compressed.data(), compressed.size(), rawsize);
  return result_of(ctype, rawbytes, rawsize);
}

// w_encode (wrap_DataModule.cpp:203-252): +source+, a String or a Data,
// in base64 or hex, base64 broken into lines of +linelen+ characters, or
// none for 0.
Rice::Object encode(const std::string &format_name, love::int64 linelen,
                    const std::string &container, Rice::Object source_given) {
  const Rice::Object source = std::move(source_given);
  const ContainerType ctype = container_of(container);
  const EncodeFormat format = encode_format_of("encode format", format_name);
  const std::span<const char> src = bytes_of(source);
  std::size_t dstlen = 0;
  char *dst =
      love::data::encode(format, src.data(), src.size(), dstlen, static_cast<std::size_t>(linelen));
  return result_of(ctype, dst, dstlen);
}

// w_decode (wrap_DataModule.cpp:254-301): the bytes +source+ encodes.
Rice::Object decode(const std::string &format_name, Rice::Object source_given,
                    const std::string &container) {
  const Rice::Object source = std::move(source_given);
  const ContainerType ctype = container_of(container);
  const EncodeFormat format = encode_format_of("decode format", format_name);
  const std::span<const char> src = bytes_of(source);
  std::size_t dstlen = 0;
  char *dst = love::data::decode(format, src.data(), src.size(), dstlen);
  return result_of(ctype, dst, dstlen);
}

// w_hash (wrap_DataModule.cpp:303-352), from where it has read its
// arguments: +source+, a String or a Data, hashed with the function
// +function_name+, as a Data for the container "data", pushed as w_hash
// pushes it, or as a String. The source comes between the two names, so
// that they cannot be swapped by mistake.
Rice::Object hash_bytes(const std::string &container, Rice::Object source_given,
                        const std::string &function_name) {
  const Rice::Object source = std::move(source_given);
  const ContainerType ctype = container_of(container);
  HashFunction::Function function = HashFunction::FUNCTION_MD5;
  if (!HashFunction::getConstant(function_name.c_str(), function)) {
    raise_enum_error("hash function", HashFunction::getConstants(function), function_name);
  }
  const std::span<const char> raw = bytes_of(source);
  HashFunction::Value hashvalue{};
  love::data::hash(function, raw.data(), raw.size(), hashvalue);
  const std::span<const char> digest = std::span(hashvalue.data).first(hashvalue.size);
  if (ctype == love::data::CONTAINER_DATA) {
    ByteData *data = instance()->newByteData(digest.size());
    std::memcpy(data->getData(), digest.data(), digest.size());
    return adopted_as_data(data);
  }
  return string_of(digest.data(), digest.size());
}

// Whether +name+ is one of LÖVE's hash functions, as w_hash asks of its
// first argument when it is no container type (wrap_DataModule.cpp:
// 311-320), for the variant LÖVE deprecated.
bool is_hash_function(const std::string &name) {
  HashFunction::Function function = HashFunction::FUNCTION_MD5;
  return HashFunction::getConstant(name.c_str(), function);
}

// w_pack with the container "data" (wrap_DataModule.cpp:378-394): the
// bytes Lota::Data.pack packed, in a new ByteData pushed as a Data.
Rice::Object new_data_of_string(const std::string &bytes) {
  return adopted_as_data(instance()->newByteData(bytes.data(), bytes.size()));
}

// w_ByteData_setString (wrap_ByteData.cpp:47-64): copies as many of
// +string+'s bytes as fit in the Data to byte +offset_number+, which LÖVE
// reads as a Lua number and truncates to an int64.
void set_string(ByteData &data, const std::string &string, double offset_number) {
  const std::size_t size = std::min(string.size(), data.getSize());
  if (size == 0) {
    return;
  }
  const auto offset = static_cast<love::int64>(offset_number);
  if (offset < 0 ||
      offset + static_cast<love::int64>(size) > static_cast<love::int64>(data.getSize())) {
    throw love::Exception("The given string offset and size don't fit within the Data's size.");
  }
  const std::span<char> bytes(static_cast<char *>(data.getData()), data.getSize());
  std::memcpy(bytes.subspan(static_cast<std::size_t>(offset)).data(), string.data(), size);
}

// The C cast w_ByteData_setT makes of each Lua number, (T)
// luaL_checknumber (wrap_ByteData.cpp:85 and 92). C++ leaves a cast of a
// number outside the type's range undefined; on Apple silicon the
// compiler makes it the processor's own conversion, FCVTZS to a 32-bit
// integer of which a narrower type keeps the low bits, or FCVTZU for a
// uint32, the conversions LuaJIT's FFI makes (native/luajit.hpp), so Lota
// converts as those do.
template <typename T> T converted(double number) {
  if constexpr (std::is_floating_point_v<T>) {
    return static_cast<T>(number);
  } else if constexpr (std::is_same_v<T, love::uint32>) {
    return luajit::to_uint32(number);
  } else {
    return static_cast<T>(luajit::to_int32(number));
  }
}

// w_ByteData_setT (wrap_ByteData.cpp:66-96), which setFloat, setDouble,
// setInt8 to setInt32, and setUInt8 to setUInt32 call with their C types:
// writes each of +values+ as a T from byte +offset_number+ on, at least
// one, as LÖVE counts a table or the arguments after the offset. A value
// that is missing or not a number raises TypeError, where
// luaL_checknumber raises its error.
template <typename T>
void set_values(ByteData &data, double offset_number, Rice::Array values_given) {
  const Rice::Array values = std::move(values_given);
  const auto offset = static_cast<love::int64>(offset_number);
  const long count = std::max(1L, ruby::length(values));
  if (offset < 0 ||
      static_cast<std::size_t>(offset) + (sizeof(T) * static_cast<std::size_t>(count)) >
          data.getSize()) {
    throw love::Exception(
        "The given offset and value parameters don't fit within the Data's size.");
  }
  const std::span<std::byte> bytes(static_cast<std::byte *>(data.getData()), data.getSize());
  for (long i = 0; i < count; i++) {
    const T value =
        converted<T>(Rice::detail::From_Ruby<double>().convert(ruby::entry(values, i).value()));
    const std::size_t at =
        static_cast<std::size_t>(offset) + (sizeof(T) * static_cast<std::size_t>(i));
    std::memcpy(bytes.subspan(at, sizeof(T)).data(), &value, sizeof(T));
  }
}

// SPDX-SnippetEnd

} // namespace

void define_data(const Rice::Module &native) {
  // love.data's module, which Lota::Data is too
  // (doc/contributors/design/translation.md): it opens, answers whether it is
  // open, and holds love.data's functions. LÖVE's root type Data is its class
  // Data, as the generator puts a class named for its own module under that
  // module once the module has functions of its own
  // (tasks/bindings/generator.rb, home).
  const Rice::Module data_module =
      Rice::define_module_under(native, "Data")
          .define_singleton_function("open", &open)
          .define_singleton_function("open?", &is_open)
          .define_singleton_function(
              "new_byte_data_of_data", &new_byte_data_of_data, Rice::Arg("data"),
              Rice::Arg("offset") = std::optional<love::int64>(),
              Rice::Arg("size") = std::optional<love::int64>(), Rice::Return().takeOwnership())
          .define_singleton_function("new_byte_data_of_string", &new_byte_data_of_string,
                                     Rice::Arg("bytes"), Rice::Return().takeOwnership())
          .define_singleton_function("new_byte_data_of_size", &new_byte_data_of_size,
                                     Rice::Arg("size"), Rice::Return().takeOwnership())
          .define_singleton_function(
              "new_data_view", &new_data_view, Rice::Arg("data"), Rice::Arg("offset"),
              Rice::Arg("size") = std::optional<love::int64>(), Rice::Return().takeOwnership())
          .define_singleton_function("compress", &compress, Rice::Arg("format"), Rice::Arg("level"),
                                     Rice::Arg("container"), Rice::Arg("source"))
          .define_singleton_function("decompress_compressed_data", &decompress_compressed_data,
                                     Rice::Arg("container"), Rice::Arg("data"))
          .define_singleton_function("decompress", &decompress, Rice::Arg("format"),
                                     Rice::Arg("source"), Rice::Arg("container"))
          .define_singleton_function("encode", &encode, Rice::Arg("format"), Rice::Arg("linelen"),
                                     Rice::Arg("container"), Rice::Arg("source"))
          .define_singleton_function("decode", &decode, Rice::Arg("format"), Rice::Arg("source"),
                                     Rice::Arg("container"))
          .define_singleton_function("check_container", &check_container, Rice::Arg("container"))
          .define_singleton_function("hash_bytes", &hash_bytes, Rice::Arg("container"),
                                     Rice::Arg("source"), Rice::Arg("function"))
          .define_singleton_function("hash_function?", &is_hash_function, Rice::Arg("name"))
          .define_singleton_function("new_data_of_string", &new_data_of_string, Rice::Arg("bytes"));
  // Its size is generated (ext/lota/native/generated/data.cpp).
  define_engine_class<love::Data>(data_module, "Data")
      .define_method("string", &data_string, Rice::Arg("offset") = 0.0,
                     Rice::Arg("size") = std::optional<double>())
      .define_method("pointer", &data_pointer)
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
  // Their clones, and CompressedData's format, are generated.
  define_engine_class<ByteData, love::Data>(native, "ByteData")
      .define_method("set_string", &set_string, Rice::Arg("string"), Rice::Arg("offset") = 0.0)
      .define_method("set_float", &set_values<float>, Rice::Arg("offset"), Rice::Arg("values"))
      .define_method("set_double", &set_values<double>, Rice::Arg("offset"), Rice::Arg("values"))
      .define_method("set_int8", &set_values<love::int8>, Rice::Arg("offset"), Rice::Arg("values"))
      .define_method("set_uint8", &set_values<love::uint8>, Rice::Arg("offset"),
                     Rice::Arg("values"))
      .define_method("set_int16", &set_values<love::int16>, Rice::Arg("offset"),
                     Rice::Arg("values"))
      .define_method("set_uint16", &set_values<love::uint16>, Rice::Arg("offset"),
                     Rice::Arg("values"))
      .define_method("set_int32", &set_values<love::int32>, Rice::Arg("offset"),
                     Rice::Arg("values"))
      .define_method("set_uint32", &set_values<love::uint32>, Rice::Arg("offset"),
                     Rice::Arg("values"));
  define_engine_class<CompressedData, love::Data>(native, "CompressedData");
  define_engine_class<DataView, love::Data>(native, "DataView");
}

} // namespace lota::native
