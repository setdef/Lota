// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/sound.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Stream.h"
#include "data/DataStream.h"
#include "filesystem/File.h"
#include "filesystem/FileData.h"
#include "filesystem/Filesystem.h"
#include "sound/Decoder.h"
#include "sound/Sound.h"
#include "sound/SoundData.h"
#include "sound/lullaby/Sound.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

using love::sound::Decoder;
using love::sound::Sound;
using love::sound::SoundData;

namespace {

// The bits in a byte, a sample of 16 bits, and the sample's size in bytes.
constexpr int bits_per_byte = 8;
constexpr int sixteen_bits = 16;

// The sound module, as LÖVE's instance() macro reaches it
// (wrap_Sound.cpp:34), or an error where LÖVE would find none.
Sound *sound() {
  auto *instance = love::Module::getInstance<Sound>(love::Module::M_SOUND);
  if (instance == nullptr) {
    throw love::Exception("Lota::Sound is not open.");
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

// w_newDecoder with a filename (vendor/love/src/modules/sound/
// wrap_Sound.cpp:35-83): "file" decodes from the open file, and "memory"
// reads the whole file into a DataStream first. The Stream's reference is
// released once the Decoder holds its own.
love::sound::Decoder *new_decoder(const std::string &filename, int buffer_size,
                                  Decoder::StreamSource source) {
  const auto *filesystem =
      love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
  if (filesystem == nullptr) {
    throw love::Exception("Lota::Filesystem is not open.");
  }
  const love::StrongRef<love::filesystem::File> file(
      filesystem->openFile(filename.c_str(), love::filesystem::File::MODE_CLOSED),
      love::Acquire::NORETAIN);
  love::StrongRef<love::Stream> stream;
  if (source == Decoder::STREAM_FILE) {
    file->open(love::filesystem::File::MODE_READ);
    stream.set(file.get());
  } else {
    const love::StrongRef<love::filesystem::FileData> data(file->read(), love::Acquire::NORETAIN);
    stream.set(std::make_unique<love::data::DataStream>(data.get()).release(),
               love::Acquire::NORETAIN);
  }
  return sound()->newDecoder(stream.get(), buffer_size);
}

namespace {

// w_newDecoder with a filename and the stream type as a String, which
// names one of Decoder's StreamSource constants ("memory" or "file"), or
// nil for "file" (wrap_Sound.cpp:42-46). Its one reference goes to the Ruby
// wrapper.
Decoder *new_decoder_from_file(const std::string &filename, int buffer_size,
                               std::optional<std::string> type) {
  Decoder::StreamSource source = Decoder::STREAM_FILE;
  if (type.has_value() && !Decoder::getConstant(type->c_str(), source)) {
    raise_enum_error("stream type", Decoder::getConstants(source), *type);
  }
  return new_decoder(filename, buffer_size, source);
}

// w_newDecoder with Data (wrap_Sound.cpp:64-68): decodes from a
// DataStream over it, as from a FileData.
Decoder *new_decoder_from_data(love::Data *data, int buffer_size) {
  const love::StrongRef<love::Stream> stream(
      std::make_unique<love::data::DataStream>(data).release(), love::Acquire::NORETAIN);
  return sound()->newDecoder(stream.get(), buffer_size);
}

// w_newSoundData with a sample count, a sample rate, a bit depth, and a
// channel count (wrap_Sound.cpp:89-97): silence, which the caller fills.
SoundData *new_sound_data(int samples, int sample_rate, int bit_depth, int channels) {
  return sound()->newSoundData(samples, sample_rate, bit_depth, channels);
}

// w_newSoundData with a Decoder (wrap_Sound.cpp:98-108), which decodes
// everything it has left into the SoundData.
SoundData *new_sound_data_from_decoder(Decoder &decoder) { return sound()->newSoundData(&decoder); }

// w_Decoder_decode (wrap_Decoder.cpp:75-96): the next chunk the Decoder
// decodes, as a new SoundData of the Decoder's format, or nullptr, which
// Ruby receives as nil, once it has decoded everything.
SoundData *decode(Decoder &decoder) {
  const int decoded = decoder.decode();
  if (decoded <= 0) {
    return nullptr;
  }
  return sound()->newSoundData(
      decoder.getBuffer(),
      decoded / (decoder.getBitDepth() / bits_per_byte * decoder.getChannelCount()),
      decoder.getSampleRate(), decoder.getBitDepth(), decoder.getChannelCount());
}

// w_SoundData_slice (wrap_SoundData.cpp:137-147): a new SoundData of
// +length+ sample frames from +start+, or of every frame from +start+ on
// when +length+ is -1.
SoundData *slice(const SoundData &data, int start, int length) { return data.slice(start, length); }

// LuaJIT's conversion of a Lua number to a C integer type narrower than 64
// bits, which LÖVE's FFI code below assigns samples through: to a 32-bit
// integer first, of which the narrower type keeps the low bits (LuaJIT
// 2.1, lj_cconv.c, lj_cconv_ct_ct, CCX(I, F)). On Apple silicon the first
// step is the processor's own conversion (FCVTZS), which saturates a number
// out of range and makes NaN 0; C++ leaves both undefined, so they are
// written out here.
std::int32_t lua_to_int32(double number) {
  if (std::isnan(number)) {
    return 0;
  }
  if (number >= static_cast<double>(std::numeric_limits<std::int32_t>::max())) {
    return std::numeric_limits<std::int32_t>::max();
  }
  if (number <= static_cast<double>(std::numeric_limits<std::int32_t>::min())) {
    return std::numeric_limits<std::int32_t>::min();
  }
  return static_cast<std::int32_t>(number);
}

// The largest value of a 16-bit and of an 8-bit sample, as
// wrap_SoundData.lua's typemaxvals (line 46) holds them.
constexpr double int16_max = 0x7FFF;
constexpr double int8_max = 0x7F;
constexpr double uint8_middle = 128;

// The position of sample +i+ of +channel+ (from 1), or of sample +i+
// counting every channel's, in +data+'s samples, as SoundData:getSample
// and setSample find it in wrap_SoundData.lua (lines 85-97 and 117-129):
// +i+ rounded down, then checked against the samples there are. +action+
// is "get" or "set", for LÖVE's messages.
std::size_t sample_position(const SoundData &data, double i, std::optional<double> channel,
                            const char *action) {
  i = std::floor(i);
  const int channels = data.getChannelCount();
  if (channel.has_value()) {
    if (*channel < 1 || *channel > channels) {
      throw love::Exception("Attempt to %s sample from out-of-range channel!", action);
    }
    i = (i * channels) + (*channel - 1);
  }
  const int bytedepth = data.getBitDepth() / bits_per_byte;
  // Lua's not (i >= 0 and i < size / bytedepth), which NaN fails too.
  if (std::isnan(i) || i < 0 || i >= static_cast<double>(data.getSize()) / bytedepth) {
    throw love::Exception("Attempt to %s out-of-range sample!", action);
  }
  return static_cast<std::size_t>(i);
}

// SoundData:getSample, in the FFI code LÖVE runs under LuaJIT, which
// replaces w_SoundData_getSample (wrap_SoundData.lua:79-105): sample +i+,
// counting every channel's samples, or sample +i+ of +channel+, from -1 to
// 1, divided in double precision, where SoundData::getSample divides in a
// float.
double get_sample(const SoundData &data, double i, std::optional<double> channel) {
  const std::size_t position = sample_position(data, i, channel, "get");
  const std::span<const std::byte> bytes(static_cast<const std::byte *>(data.getData()),
                                         data.getSize());
  if (data.getBitDepth() == sixteen_bits) {
    // 16-bit data is stored as signed values internally.
    std::int16_t sample = 0;
    std::memcpy(&sample, bytes.subspan(position * sizeof sample, sizeof sample).data(),
                sizeof sample);
    return sample / int16_max;
  }
  // 8-bit data is stored as unsigned values internally.
  std::uint8_t sample = 0;
  std::memcpy(&sample, bytes.subspan(position, sizeof sample).data(), sizeof sample);
  return (sample - uint8_middle) / int8_max;
}

// SoundData:setSample, in the FFI code LÖVE runs under LuaJIT, which
// replaces w_SoundData_setSample (wrap_SoundData.lua:107-140), from the
// Array Lota::Sound::SoundData#sample= is given, of two or three numbers:
// sets sample +i+, counting every channel's, to a sample, or, given a
// channel and then a sample, sample +i+ of that channel. A 16-bit sample is
// the sample times 32767 in double precision, and an 8-bit one the sample
// times 127, plus 128, made a float, as LÖVE's FFI code assigns them. The
// numbers come as one Array, as they come to the writer, so no two can be
// passed in each other's place.
void set_sample(SoundData &data, Rice::Array arguments) {
  const Rice::Array array = std::move(arguments);
  std::vector<double> given;
  for (const auto item : array) {
    given.push_back(Rice::detail::From_Ruby<double>().convert(item.value()));
  }
  const auto number = [&given](std::size_t index) { return given.at(index); };
  const double i = number(0);
  std::optional<double> channel;
  double value = number(1);
  if (given.size() > 2) {
    channel = value;
    value = number(2);
  }
  const std::size_t position = sample_position(data, i, channel, "set");
  const std::span<std::byte> bytes(static_cast<std::byte *>(data.getData()), data.getSize());
  if (data.getBitDepth() == sixteen_bits) {
    // 16-bit data is stored as signed values internally.
    const auto stored = static_cast<std::int16_t>(lua_to_int32(value * int16_max));
    std::memcpy(bytes.subspan(position * sizeof stored, sizeof stored).data(), &stored,
                sizeof stored);
  } else {
    // 8-bit data is stored as unsigned values internally. The float cast
    // is needed to make values end up the same as in the C++ version of
    // this method.
    const auto narrowed =
        static_cast<double>(static_cast<float>((value * int8_max) + uint8_middle));
    const auto stored = static_cast<std::uint8_t>(lua_to_int32(narrowed));
    std::memcpy(bytes.subspan(position, sizeof stored).data(), &stored, sizeof stored);
  }
}

// luaopen_love_sound (wrap_Sound.cpp:128-150) creates the lullaby sound
// module once, as boot.lua requires love.sound before love.audio
// (boot.lua:348-368).
void open() { open_module<Sound, love::sound::lullaby::Sound>(love::Module::M_SOUND); }

bool is_open() { return love::Module::getInstance<Sound>(love::Module::M_SOUND) != nullptr; }

// SPDX-SnippetEnd

} // namespace

void define_sound(const Rice::Module &native) {
  // Their other methods are generated (ext/lota/native/generated/sound.cpp).
  define_engine_class<Decoder>(native, "Decoder")
      .define_method("decode", &decode, Rice::Return().takeOwnership());
  define_engine_class<SoundData, love::Data>(native, "SoundData")
      .define_method("slice", &slice, Rice::Arg("start"), Rice::Arg("length") = -1,
                     Rice::Return().takeOwnership())
      .define_method("sample", &get_sample, Rice::Arg("i"),
                     Rice::Arg("channel") = std::optional<double>())
      .define_method("set_sample", &set_sample, Rice::Arg("arguments"));

  Rice::define_module_under(native, "Sound")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function(
          "new_decoder", &new_decoder_from_file, Rice::Arg("filename"), Rice::Arg("buffer_size"),
          Rice::Arg("type") = std::optional<std::string>(), Rice::Return().takeOwnership())
      .define_singleton_function("new_decoder_from_data", &new_decoder_from_data, Rice::Arg("data"),
                                 Rice::Arg("buffer_size"), Rice::Return().takeOwnership())
      .define_singleton_function("new_sound_data", &new_sound_data, Rice::Arg("samples"),
                                 Rice::Arg("sample_rate"), Rice::Arg("bit_depth"),
                                 Rice::Arg("channels"), Rice::Return().takeOwnership())
      .define_singleton_function("new_sound_data_from_decoder", &new_sound_data_from_decoder,
                                 Rice::Arg("decoder"), Rice::Return().takeOwnership());
}

} // namespace lota::native
