// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/audio.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "audio/Audio.h"
#include "audio/Source.h"
#include "audio/null/Audio.h"
#include "audio/openal/Audio.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "sound/Decoder.h"
#include "sound/SoundData.h"

#include <array>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <string>
#include <utility>

namespace lota::native {

namespace {

using love::audio::Audio;
using love::audio::Source;
using love::sound::Decoder;
using love::sound::SoundData;

template <typename T> T *module(love::Module::ModuleType type, const char *name) {
  auto *instance = love::Module::getInstance<T>(type);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", name);
  }
  return instance;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// Closes the audio module, as LÖVE's love.cpp closes every module when it
// closes its Lua state at exit (lua_close, love.cpp:291), which collects
// the module: OpenAL's Audio stops the thread that streams its Sources and
// closes the device (audio/openal/Audio.cpp:221-266). Lota's modules live
// as long as the process, but this one has a thread of its own, which
// would go on calling OpenAL Soft while the process exits and destroys
// OpenAL Soft's static mutexes, and std::terminate. So open() registers
// this with std::atexit, which runs it after Ruby has freed the game's
// Sources and before the static objects of the libraries loaded before
// it are destroyed.
void close() {
  if (auto *instance = love::Module::getInstance<Audio>(love::Module::M_AUDIO)) {
    instance->release();
  }
}

// luaopen_love_audio (vendor/love/src/modules/audio/wrap_Audio.cpp:
// 678-723): tries OpenAL first and falls back to LÖVE's null audio module,
// which plays nothing, printing why each attempt failed, as LÖVE prints
// with std::cout. Lota returns the lines instead, as an Array of Strings,
// for Lota::Boot to print with Ruby's own standard output, so they keep
// their place among what the game prints. Raises when neither opens, with
// LÖVE's message.
Rice::Array open() {
  Rice::Array lines;
  if (love::Module::getInstance<Audio>(love::Module::M_AUDIO) != nullptr) {
    return lines;
  }

  // Try OpenAL first.
  try {
    open_module<Audio, love::audio::openal::Audio>(love::Module::M_AUDIO);
  } catch (love::Exception &e) {
    lines.push(Rice::String(e.what()), false);
  }

  if (love::Module::getInstance<Audio>(love::Module::M_AUDIO) == nullptr) {
    // Fall back to nullaudio.
    try {
      open_module<Audio, love::audio::null::Audio>(love::Module::M_AUDIO);
    } catch (love::Exception &e) {
      lines.push(Rice::String(e.what()), false);
    }
  }

  if (love::Module::getInstance<Audio>(love::Module::M_AUDIO) == nullptr) {
    throw love::Exception("Could not open any audio module.");
  }
  static const bool closes_at_exit = std::atexit(&close) == 0;
  static_cast<void>(closes_at_exit);
  return lines;
}

bool is_open() { return love::Module::getInstance<Audio>(love::Module::M_AUDIO) != nullptr; }

// w_newSource's source type (wrap_Audio.cpp:53-60), which it reads for
// anything but a SoundData or a Decoder: a type's name, as LÖVE names it,
// or LÖVE's error for one it does not know or for a queueable source.
std::string source_type(const std::string &type) {
  Source::Type stype = Source::TYPE_STREAM;
  if (!Source::getConstant(type.c_str(), stype)) {
    raise_enum_error("source type", Source::getConstants(stype), type);
  }
  if (stype == Source::TYPE_QUEUE) {
    throw love::Exception("Cannot create queueable sources using love.audio.newSource. Use "
                          "love.audio.newQueueableSource instead.");
  }
  return type;
}

// w_newSource of a SoundData or a Decoder (wrap_Audio.cpp:83-101): a
// static Source of the SoundData's samples, or a streaming one that
// decodes as it plays. Lota::Audio::Source.new makes a filename or a
// FileData into one of them first, as luax_convobj does with love.sound's
// newDecoder and newSoundData. The Source's one reference goes to the Ruby
// wrapper.
Source *new_source_from_sound_data(SoundData *data) {
  return module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->newSource(data);
}

Source *new_source_from_decoder(Decoder *decoder) {
  return module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->newSource(decoder);
}

// Source:seek (wrap_Source.cpp:106-119): to +offset+ in seconds, or in the
// unit named, which may not be negative.
void source_seek(Source &t, double offset, const std::optional<std::string> &unit) {
  if (offset < 0) {
    raise_argument_error("can't seek to a negative position");
  }
  Source::Unit u = Source::UNIT_SECONDS;
  if (unit.has_value() && !Source::getConstant(unit->c_str(), u)) {
    raise_enum_error("time unit", Source::getConstants(u), *unit);
  }
  t.seek(offset, u);
}

// Source:tell and Source:getDuration (wrap_Source.cpp:121-145): where
// the Source plays, and how long its sound is, in seconds or in the unit
// named.
Source::Unit unit_of(const std::optional<std::string> &unit) {
  Source::Unit u = Source::UNIT_SECONDS;
  if (unit.has_value() && !Source::getConstant(unit->c_str(), u)) {
    raise_enum_error("time unit", Source::getConstants(u), *unit);
  }
  return u;
}

double source_tell(Source &t, const std::optional<std::string> &unit) {
  return t.tell(unit_of(unit));
}

double source_duration(Source &t, const std::optional<std::string> &unit) {
  return t.getDuration(unit_of(unit));
}

// The listener's orientation (wrap_Audio.cpp:244-268): the forward
// vector's x, y, and z, then the up vector's, six numbers each read as a
// float.
constexpr std::size_t orientation_size = 6;

void set_orientation(Rice::Array orientation) {
  const Rice::Array given = std::move(orientation);
  if (given.size() != static_cast<long>(orientation_size)) {
    ruby::raise_argument_error("wrong number of arguments (given " + std::to_string(given.size()) +
                               ", expected 6)");
  }
  std::array<float, orientation_size> v{};
  std::size_t index = 0;
  for (const auto item : given) {
    v.at(index++) = static_cast<float>(Rice::detail::From_Ruby<double>().convert(item.value()));
  }
  module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->setOrientation(v.data());
}

Rice::Array orientation() {
  std::array<float, orientation_size> v{};
  module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getOrientation(v.data());
  Rice::Array results;
  for (const float component : v) {
    results.push(static_cast<double>(component), false);
  }
  return results;
}

// w_getDistanceModel (wrap_Audio.cpp:324-331): the model's name, which
// every model LÖVE sets has.
std::string distance_model() {
  const Audio::DistanceModel model =
      module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getDistanceModel();
  const char *name = nullptr;
  Audio::getConstant(model, name);
  return name;
}

// w_play with one Source (wrap_Audio.cpp:153-166): whether it started.
bool play(Source &source) {
  return module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->play(&source);
}

// w_stop with no Source, which stops every one, or with one
// (wrap_Audio.cpp:168-182).
void stop() { module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->stop(); }

void stop_source(Source &source) { source.stop(); }

// SPDX-SnippetEnd

} // namespace

void define_audio(const Rice::Module &native) {
  define_engine_class<Source>(native, "Source")
      .define_method("seek", &source_seek, Rice::Arg("offset"),
                     Rice::Arg("unit") = std::optional<std::string>())
      .define_method("tell", &source_tell, Rice::Arg("unit") = std::optional<std::string>())
      .define_method("duration", &source_duration,
                     Rice::Arg("unit") = std::optional<std::string>());

  Rice::define_module_under(native, "Audio")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("source_type", &source_type, Rice::Arg("type"))
      .define_singleton_function("new_source_from_sound_data", &new_source_from_sound_data,
                                 Rice::Arg("data"), Rice::Return().takeOwnership())
      .define_singleton_function("new_source_from_decoder", &new_source_from_decoder,
                                 Rice::Arg("decoder"), Rice::Return().takeOwnership())
      .define_singleton_function("distance_model", &distance_model)
      .define_singleton_function("set_orientation", &set_orientation, Rice::Arg("orientation"))
      .define_singleton_function("orientation", &orientation)
      .define_singleton_function("play", &play, Rice::Arg("source"))
      .define_singleton_function("stop", &stop)
      .define_singleton_function("stop_source", &stop_source, Rice::Arg("source"));
}

} // namespace lota::native
