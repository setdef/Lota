// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/audio.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "audio/Audio.h"
#include "audio/Source.h"
#include "audio/null/Audio.h"
#include "audio/openal/Audio.h"
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

#include <cstdlib>
#include <memory>
#include <string>
#include <utility>

#include <dlfcn.h>

namespace lota::native {

namespace {

using love::audio::Audio;
using love::audio::Source;
using love::sound::Decoder;
using love::sound::SoundData;

// Whether OpenAL Soft is loaded. Lota's bundle links its framework weakly,
// so that a copy of the bundle without the framework still loads (the
// precompiled gem carries none yet; ext/lota/licenses.rb says why), and
// then its functions are absent rather than callable.
bool openal_loaded() { return dlsym(RTLD_DEFAULT, "alcOpenDevice") != nullptr; }

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
// LÖVE's message. Without OpenAL Soft loaded, the first attempt fails at
// once.
Rice::Array open() {
  Rice::Array lines;
  if (love::Module::getInstance<Audio>(love::Module::M_AUDIO) != nullptr) {
    return lines;
  }

  // Try OpenAL first.
  if (!openal_loaded()) {
    lines.push(Rice::String("Could not load OpenAL Soft."), false);
  } else {
    try {
      open_module<Audio, love::audio::openal::Audio>(love::Module::M_AUDIO);
    } catch (love::Exception &e) {
      lines.push(Rice::String(e.what()), false);
    }
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

// w_newDecoder with a filename, a buffer size, and a stream type
// (vendor/love/src/modules/sound/wrap_Sound.cpp:35-83), as w_newSource
// calls it through luax_convobj: "memory" reads the whole file into a
// DataStream, and "file" decodes from the open file as the Source plays.
Decoder *new_decoder(const std::string &filename, Decoder::StreamSource source) {
  auto *sound = module<love::sound::Sound>(love::Module::M_SOUND, "Lota::Sound");
  const auto *filesystem =
      module<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM, "Lota::Filesystem");
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
  return sound->newDecoder(stream.get(), Decoder::DEFAULT_BUFFER_SIZE);
}

// w_newSource with a filename and a source type (wrap_Audio.cpp:47-102): a
// static Source decodes the whole file into SoundData first, and a
// streaming one decodes from the file as it plays. The Source's one
// reference goes to the Ruby wrapper. The type comes as a Ruby String, so
// the two arguments cannot be passed in each other's place.
Source *new_source(const std::string &filename, Rice::Object source_type) {
  const std::string type = Rice::String(std::move(source_type)).str();
  Source::Type stype = Source::TYPE_STREAM;
  if (!Source::getConstant(type.c_str(), stype)) {
    raise_enum_error("source type", Source::getConstants(stype), type);
  }
  if (stype == Source::TYPE_QUEUE) {
    throw love::Exception("Cannot create queueable sources using love.audio.newSource. Use "
                          "love.audio.newQueueableSource instead.");
  }

  auto *audio = module<Audio>(love::Module::M_AUDIO, "Lota::Audio");
  if (love::Module::getInstance<love::sound::Sound>(love::Module::M_SOUND) == nullptr) {
    throw love::Exception("Could not find love.sound!");
  }
  const love::StrongRef<Decoder> decoder(new_decoder(filename, (stype == Source::TYPE_STATIC)
                                                                   ? Decoder::STREAM_MEMORY
                                                                   : Decoder::STREAM_FILE),
                                         love::Acquire::NORETAIN);
  if (stype == Source::TYPE_STATIC) {
    auto *sound = module<love::sound::Sound>(love::Module::M_SOUND, "Lota::Sound");
    const love::StrongRef<SoundData> data(sound->newSoundData(decoder.get()),
                                          love::Acquire::NORETAIN);
    return audio->newSource(data.get());
  }
  return audio->newSource(decoder.get());
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
  define_engine_class<Source>(native, "Source");

  Rice::define_module_under(native, "Audio")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_source", &new_source, Rice::Arg("filename"),
                                 Rice::Arg("type"), Rice::Return().takeOwnership())
      .define_singleton_function("play", &play, Rice::Arg("source"))
      .define_singleton_function("stop", &stop)
      .define_singleton_function("stop_source", &stop_source, Rice::Arg("source"));
}

} // namespace lota::native
