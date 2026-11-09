// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/audio.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/ruby.hpp"

#include "audio/Audio.h"
#include "audio/Effect.h"
#include "audio/Filter.h"
#include "audio/RecordingDevice.h"
#include "audio/Source.h"
#include "audio/null/Audio.h"
#include "audio/openal/Audio.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "sound/Decoder.h"
#include "sound/SoundData.h"

#ifdef LOVE_APPLE_USE_FRAMEWORKS
#ifdef LOVE_IOS
#include <OpenAL/alc.h>
#else
#include <OpenAL-Soft/alc.h>
#endif
#else
#include <alc.h>
#endif

#include <array>
#include <cstddef>
#include <cstdlib>
#include <iterator>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

namespace {

using love::audio::Audio;
using love::audio::Effect;
using love::audio::Filter;
using love::audio::RecordingDevice;
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
#ifdef _WIN32
  // On Windows std::atexit in a DLL registers with the DLL's own exit
  // table (mingw-w64's crtdll.c), which Windows runs at DLL_PROCESS_DETACH,
  // after ExitProcess has terminated every other thread, among them the
  // thread that streams Sources and OpenAL Soft's mixer, so closing the
  // device then waits for threads that no longer run, and the process
  // never exits. Ruby's VM runs ruby_vm_at_exit's functions as it passes
  // away (ruby_vm_destruct), after the game's objects are freed and before
  // the process exits, while those threads still run. On macOS and Linux
  // exit() runs the atexit functions before any thread ends, so the close
  // stays there.
  static const bool closes_at_exit = (ruby_vm_at_exit([](ruby_vm_t *) { close(); }), true);
#else
  static const bool closes_at_exit = std::atexit(&close) == 0;
#endif
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

// love._requestRecordingPermission (vendor/love/src/modules/love/
// love.cpp:468-474), which boot.lua calls with t.audio.mic before the
// audio module opens (boot.lua:342-344): whether opening a recording
// device asks the system for the microphone, which only Android does.
void set_request_recording_permission(bool request) {
  love::audio::setRequestRecordingPermission(request);
}

// w_pause with no Source (wrap_Audio.cpp:184-198): pauses every Source
// playing, and returns those it paused, as an Array where LÖVE fills a
// table.
Rice::Array pause() {
  const std::vector<Source *> sources =
      module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->pause();
  Rice::Array paused;
  for (Source *source : sources) {
    paused.push(source, false);
  }
  return paused;
}

// w_pause with one Source (wrap_Audio.cpp:205-208).
void pause_source(Source &source) { source.pause(); }

// The names of a list LÖVE fills a table with in a loop, as an Array.
Rice::Array names_of(const std::vector<std::string> &list) {
  Rice::Array names;
  for (const std::string &name : list) {
    names.push(name, false);
  }
  return names;
}

// Whether +device+ is the one LÖVE invents when nothing can record: with
// no default capture device, Audio::getRecordingDevices opens one to read
// its name, checks that with alGetError where alcCaptureOpenDevice sets
// an ALC error, and lists a device named "" although its own comment says
// to return an empty list (openal/Audio.cpp:573-591; upstream/009.md).
// Only a device with an empty name, while OpenAL lists no capture device
// to open, is that one.
bool invented_recording_device(RecordingDevice &device) {
  if (*device.getName() != '\0') {
    return false;
  }
  const ALCchar *capture = alcGetString(nullptr, ALC_CAPTURE_DEVICE_SPECIFIER);
  return capture == nullptr || *capture == '\0';
}

// w_getRecordingDevices (wrap_Audio.cpp:333-346): the recording devices,
// as an Array where LÖVE fills a table, without the one it invents.
Rice::Array recording_devices() {
  const std::vector<RecordingDevice *> &devices =
      module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getRecordingDevices();
  Rice::Array list;
  for (RecordingDevice *device : devices) {
    if (invented_recording_device(*device)) {
      continue;
    }
    list.push(device, false);
  }
  return list;
}

// w_getActiveEffects (wrap_Audio.cpp:511-523).
Rice::Array active_effects() {
  std::vector<std::string> list;
  module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getActiveEffects(list);
  return names_of(list);
}

// w_getPlaybackDevices (wrap_Audio.cpp:593-607).
Rice::Array playback_devices() {
  std::vector<std::string> list;
  module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getPlaybackDevices(list);
  return names_of(list);
}

// w_getOutputSpatializationFilters (wrap_Audio.cpp:564-576).
Rice::Array output_spatialization_filters() {
  std::vector<std::string> filters;
  module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getOutputSpatializationFilters(filters);
  return names_of(filters);
}

// The name Lua's lua_typename gives the value Lua would hold for +value+,
// for luax_effecterror's message: a Symbol is a name, as a string is in
// Lua (rule 9 of doc/contributors/design/translation.md), and an Array or a
// Hash a table.
const char *lua_type_name(const Rice::Object &value) {
  if (ruby::is_nil(value)) {
    return "nil";
  }
  if (ruby::is_boolean(value)) {
    return "boolean";
  }
  if (ruby::is_numeric(value)) {
    return "number";
  }
  if (ruby::is_string(value) || ruby::is_symbol(value)) {
    return "string";
  }
  if (ruby::is_array(value) || ruby::is_hash(value)) {
    return "table";
  }
  return "userdata";
}

// The text of +value+, a String or a Symbol's name, or nullptr for any
// other value, as lua_tostring gives only for a string.
std::optional<std::string> text_of(const Rice::Object &value) {
  if (ruby::is_symbol(value)) {
    return ruby::symbol_name(value);
  }
  if (ruby::is_string(value)) {
    return Rice::detail::From_Ruby<std::string>().convert(value.value());
  }
  return std::nullopt;
}

// The value of the setting named +key+ in +settings+, an Array of
// [name, value] pairs, or nil when it has none, as lua_rawget reads a key.
Rice::Object setting(const Rice::Array &settings, const std::string &key) {
  for (long index = 0; index < ruby::length(settings); ++index) {
    const Rice::Array pair(ruby::entry(settings, index));
    if (text_of(ruby::entry(pair, 0)) == key) {
      return ruby::entry(pair, 1);
    }
  }
  return ruby::nil();
}

// Raises luax_effecterror's message (wrap_Audio.cpp:395) for the setting
// +keystr+ of +typestr+, whose +value+ is not the +expected+ type.
[[noreturn]] void raise_effect_error(const std::string &typestr, const std::string &keystr,
                                     const char *expected, const Rice::Object &value) {
  throw love::Exception("Bad parameter type for %s %s: %s expected, got %s", typestr.c_str(),
                        keystr.c_str(), expected, lua_type_name(value));
}

// The name of the type +settings+ gives under +paramstr+, its "type",
// which must be there, as w_setEffect and setFilterReadFilter read it
// first (wrap_Audio.cpp:360-372, wrap_Source.cpp:363-371).
std::string type_setting(const Rice::Array &settings, const std::string &paramstr,
                         const char *missing) {
  const Rice::Object value = setting(settings, paramstr);
  if (ruby::is_nil(value)) {
    throw love::Exception("%s", missing);
  }
  const std::optional<std::string> typestr = text_of(value);
  if (!typestr.has_value()) {
    ruby::raise_type_error("wrong argument type " + ruby::class_name(value) + " (expected Symbol)");
  }
  return *typestr;
}

// The settings of an Effect, read from +settings+ as w_setEffect reads
// its table (wrap_Audio.cpp:356-445): the type, then each other setting,
// a number, a boolean, or a waveform's name by its parameter's type. A
// setting the type does not have raises "Invalid '...' Effect parameter".
std::map<Effect::Parameter, float> effect_settings(const Rice::Array &settings) {
  const char *paramstr = nullptr;
  Effect::getConstant(Effect::EFFECT_TYPE, paramstr, Effect::TYPE_BASIC);
  const std::string typestr = type_setting(settings, paramstr, "Effect type not specificed.");
  Effect::Type type = Effect::TYPE_MAX_ENUM;
  if (!Effect::getConstant(typestr.c_str(), type)) {
    raise_enum_error("effect type", Effect::getConstants(type), typestr);
  }

  std::map<Effect::Parameter, float> params;
  params[Effect::EFFECT_TYPE] = static_cast<float>(static_cast<int>(type));

  // Iterate over the whole table, reading valid parameters and erroring on invalid ones
  for (long index = 0; index < ruby::length(settings); ++index) {
    const Rice::Array pair(ruby::entry(settings, index));
    const std::string keystr = text_of(ruby::entry(pair, 0)).value_or("");
    const Rice::Object value = ruby::entry(pair, 1);
    Effect::Parameter param = Effect::EFFECT_TYPE;

    if (!Effect::getConstant(keystr.c_str(), param, type) &&
        !Effect::getConstant(keystr.c_str(), param, Effect::TYPE_BASIC)) {
      throw love::Exception("Invalid '%s' Effect parameter: %s", typestr.c_str(), keystr.c_str());
    }
    switch (Effect::getParameterType(param)) {
    case Effect::PARAM_FLOAT:
      if (!ruby::is_numeric(value)) {
        raise_effect_error(typestr, keystr, "number", value);
      }
      params[param] = static_cast<float>(Rice::detail::From_Ruby<double>().convert(value.value()));
      break;
    case Effect::PARAM_BOOL:
      if (!ruby::is_boolean(value)) {
        raise_effect_error(typestr, keystr, "boolean", value);
      }
      params[param] = ruby::is_true(value) ? 1.0F : 0.0F;
      break;
    case Effect::PARAM_WAVEFORM: {
      const std::optional<std::string> paramstr = text_of(value);
      if (!paramstr.has_value()) {
        raise_effect_error(typestr, keystr, "string", value);
      }
      Effect::Waveform waveform = Effect::WAVE_MAX_ENUM;
      if (!Effect::getConstant(paramstr->c_str(), waveform)) {
        raise_enum_error("waveform type", *paramstr);
      }
      params[param] = static_cast<float>(static_cast<int>(waveform));
      break;
    }
    case Effect::PARAM_TYPE:
    case Effect::PARAM_MAX_ENUM:
      break;
    }
  }
  return params;
}

// The value above which w_getEffect pushes a boolean parameter, which
// it holds as a float, as true (wrap_Audio.cpp:480-482).
constexpr float BOOLEAN_THRESHOLD = 0.5F;

// w_setEffect (wrap_Audio.cpp:349-447): sets the effect +namestr+ to
// +settings+, an Array of [name, value] pairs that Lota::Audio.set_effect
// makes of its keywords (rule 10 of doc/contributors/design/translation.md), or
// unsets it when +settings+ is nil, and returns whether it could.
bool set_effect(const std::string &namestr, Rice::Object given) {
  const Rice::Object settings = std::move(given);
  auto *audio = module<Audio>(love::Module::M_AUDIO, "Lota::Audio");
  if (ruby::is_nil(settings)) {
    return audio->unsetEffect(namestr.c_str());
  }
  std::map<Effect::Parameter, float> params = effect_settings(Rice::Array(settings));
  return audio->setEffect(namestr.c_str(), params);
}

// w_getEffect (wrap_Audio.cpp:449-509): the settings of the effect
// +namestr+ as an Array of [name, value] pairs, which
// Lota::Audio.effect makes a frozen record (rule 28 of
// doc/contributors/design/translation.md), or nil when there is no such effect.
Rice::Object effect(const std::string &namestr) {
  std::map<Effect::Parameter, float> params;
  if (!module<Audio>(love::Module::M_AUDIO, "Lota::Audio")->getEffect(namestr.c_str(), params)) {
    return ruby::nil();
  }

  const char *keystr = nullptr;
  const char *valstr = nullptr;
  const auto type = static_cast<Effect::Type>(static_cast<int>(params[Effect::EFFECT_TYPE]));

  Rice::Array settings;
  for (const auto &p : params) {
    if (!Effect::getConstant(p.first, keystr, type)) {
      Effect::getConstant(p.first, keystr, Effect::TYPE_BASIC);
    }
    Rice::Array pair;
    pair.push(std::string(keystr), false);
    switch (Effect::getParameterType(p.first)) {
    case Effect::PARAM_FLOAT:
      pair.push(static_cast<double>(p.second), false);
      break;
    case Effect::PARAM_BOOL:
      pair.push(p.second > BOOLEAN_THRESHOLD, false);
      break;
    case Effect::PARAM_WAVEFORM:
      Effect::getConstant(static_cast<Effect::Waveform>(static_cast<int>(p.second)), valstr);
      pair.push(std::string(valstr), false);
      break;
    case Effect::PARAM_TYPE:
      Effect::getConstant(static_cast<Effect::Type>(static_cast<int>(p.second)), valstr);
      pair.push(std::string(valstr), false);
      break;
    case Effect::PARAM_MAX_ENUM:
      continue;
    }
    settings.push(pair, false);
  }
  return settings;
}

// setFilterReadFilter (wrap_Source.cpp:355-406): the settings of a
// Filter, read from +settings+ as an Effect's are, each a number.
std::map<Filter::Parameter, float> filter_settings(const Rice::Array &settings) {
  const char *paramstr = nullptr;
  Filter::getConstant(Filter::FILTER_TYPE, paramstr, Filter::TYPE_BASIC);
  const std::string typestr = type_setting(settings, paramstr, "Filter type not specificed.");
  Filter::Type type = Filter::TYPE_MAX_ENUM;
  if (!Filter::getConstant(typestr.c_str(), type)) {
    raise_enum_error("filter type", Filter::getConstants(type), typestr);
  }

  std::map<Filter::Parameter, float> params;
  params[Filter::FILTER_TYPE] = static_cast<float>(static_cast<int>(type));

  for (long index = 0; index < ruby::length(settings); ++index) {
    const Rice::Array pair(ruby::entry(settings, index));
    const std::string keystr = text_of(ruby::entry(pair, 0)).value_or("");
    const Rice::Object value = ruby::entry(pair, 1);
    Filter::Parameter param = Filter::FILTER_TYPE;

    if (!Filter::getConstant(keystr.c_str(), param, type) &&
        !Filter::getConstant(keystr.c_str(), param, Filter::TYPE_BASIC)) {
      throw love::Exception("Invalid '%s' Effect parameter: %s", typestr.c_str(), keystr.c_str());
    }
    switch (Filter::getParameterType(param)) {
    case Filter::PARAM_FLOAT:
      if (!ruby::is_numeric(value)) {
        raise_effect_error(typestr, keystr, "number", value);
      }
      params[param] = static_cast<float>(Rice::detail::From_Ruby<double>().convert(value.value()));
      break;
    case Filter::PARAM_TYPE:
    case Filter::PARAM_MAX_ENUM:
      break;
    }
  }
  return params;
}

// getFilterWriteFilter (wrap_Source.cpp:408-441): +params+ as an Array of
// [name, value] pairs.
Rice::Array filter_pairs(std::map<Filter::Parameter, float> &params) {
  const char *keystr = nullptr;
  const char *valstr = nullptr;
  const auto type = static_cast<Filter::Type>(static_cast<int>(params[Filter::FILTER_TYPE]));

  Rice::Array settings;
  for (const auto &p : params) {
    if (!Filter::getConstant(p.first, keystr, type)) {
      Filter::getConstant(p.first, keystr, Filter::TYPE_BASIC);
    }
    Rice::Array pair;
    pair.push(std::string(keystr), false);
    switch (Filter::getParameterType(p.first)) {
    case Filter::PARAM_FLOAT:
      pair.push(static_cast<double>(p.second), false);
      break;
    case Filter::PARAM_TYPE:
      Filter::getConstant(static_cast<Filter::Type>(static_cast<int>(p.second)), valstr);
      pair.push(std::string(valstr), false);
      break;
    case Filter::PARAM_MAX_ENUM:
      continue;
    }
    settings.push(pair, false);
  }
  return settings;
}

// w_Source_setFilter (wrap_Source.cpp:443-455): sets +source+'s filter
// to +settings+, or removes it when +settings+ is nil, and returns
// whether it could.
bool source_set_filter(Source &source, Rice::Object given) {
  const Rice::Object settings = std::move(given);
  if (ruby::is_nil(settings)) {
    return source.setFilter();
  }
  return source.setFilter(filter_settings(Rice::Array(settings)));
}

// w_Source_getFilter (wrap_Source.cpp:457-468): +source+'s filter as
// pairs, or nil when it has none.
Rice::Object source_filter(Source &source) {
  std::map<Filter::Parameter, float> params;
  if (!source.getFilter(params)) {
    return ruby::nil();
  }
  return filter_pairs(params);
}

// w_Source_setEffect (wrap_Source.cpp:470-492): with +enabled+ false,
// unsets the effect +namestr+ on +source+; otherwise sets it, through the
// filter +settings+ when they are given, and returns whether it could.
bool source_set_effect(Source &source, const std::string &namestr, bool enabled,
                       Rice::Object given) {
  const Rice::Object settings = std::move(given);
  if (!enabled) {
    return source.unsetEffect(namestr.c_str());
  }
  if (ruby::is_nil(settings)) {
    return source.setEffect(namestr.c_str());
  }
  return source.setEffect(namestr.c_str(), filter_settings(Rice::Array(settings)));
}

// w_Source_getEffect (wrap_Source.cpp:494-516): whether +source+ has the
// effect +namestr+, and its filter's settings as pairs when it has one,
// as one Array (rule 4 of doc/contributors/design/translation.md).
Rice::Array source_effect(Source &source, const std::string &namestr) {
  std::map<Filter::Parameter, float> params;
  Rice::Array results;
  if (!source.getEffect(namestr.c_str(), params)) {
    results.push(false, false);
    return results;
  }
  results.push(true, false);
  // No filter associated, return nil as second argument
  if (params.empty()) {
    return results;
  }
  // Return filter settings as second argument
  results.push(filter_pairs(params), false);
  return results;
}

// w_Source_getActiveEffects (wrap_Source.cpp:518-532).
Rice::Array source_active_effects(Source &source) {
  std::vector<std::string> list;
  source.getActiveEffects(list);
  return names_of(list);
}

// w_Source_queue with a SoundData (wrap_Source.cpp:540-566): queues the
// +length+ bytes of +data+ from +offset+, or all of them, on +source+,
// and returns whether it could. Lota::Audio::Source#queue reads the
// offset and length from its arguments as w_Source_queue counts them.
bool source_queue(Source &source, SoundData &data, double offset, std::optional<double> length) {
  const auto start = static_cast<int>(offset);
  const auto size = static_cast<std::size_t>(length.value_or(static_cast<double>(data.getSize())));
  if (start < 0 || size > data.getSize() - static_cast<std::size_t>(start)) {
    throw love::Exception("Data region out of bounds.");
  }
  return source.queue(std::next(static_cast<unsigned char *>(data.getData()), start), size,
                      data.getSampleRate(), data.getBitDepth(), data.getChannelCount());
}

// w_RecordingDevice_start (wrap_RecordingDevice.cpp:35-57): starts
// recording, with the device's own settings when +samples+ is not given,
// and LÖVE's defaults for each setting after it left out, and returns
// whether it started.
bool recording_start(RecordingDevice &d, std::optional<int> samples, std::optional<int> samplerate,
                     std::optional<int> bitdepth, std::optional<int> channels) {
  if (!samples.has_value()) {
    return d.start(d.getMaxSamples(), d.getSampleRate(), d.getBitDepth(), d.getChannelCount());
  }
  // RecordingDevice declares its defaults in its class and defines them
  // nowhere, so they are copied here, as luaL_optinteger copies them,
  // rather than bound to value_or's reference, which would need a
  // definition to link against where the compiler does not inline them.
  constexpr int default_rate = RecordingDevice::DEFAULT_SAMPLE_RATE;
  constexpr int default_depth = RecordingDevice::DEFAULT_BIT_DEPTH;
  constexpr int default_channels = RecordingDevice::DEFAULT_CHANNELS;
  return d.start(*samples, samplerate.value_or(default_rate), bitdepth.value_or(default_depth),
                 channels.value_or(default_channels));
}

// SPDX-SnippetEnd

} // namespace

void define_audio(const Rice::Module &native) {
  define_engine_class<Source>(native, "Source")
      .define_method("seek", &source_seek, Rice::Arg("offset"),
                     Rice::Arg("unit") = std::optional<std::string>())
      .define_method("tell", &source_tell, Rice::Arg("unit") = std::optional<std::string>())
      .define_method("duration", &source_duration, Rice::Arg("unit") = std::optional<std::string>())
      .define_method("set_filter", &source_set_filter, Rice::Arg("settings"))
      .define_method("filter", &source_filter)
      .define_method("set_effect", &source_set_effect, Rice::Arg("name"), Rice::Arg("enabled"),
                     Rice::Arg("settings"))
      .define_method("effect", &source_effect, Rice::Arg("name"))
      .define_method("active_effects", &source_active_effects)
      .define_method("queue", &source_queue, Rice::Arg("data"), Rice::Arg("offset"),
                     Rice::Arg("length") = std::optional<double>());

  define_engine_class<RecordingDevice>(native, "RecordingDevice")
      .define_method("start", &recording_start, Rice::Arg("samples") = std::optional<int>(),
                     Rice::Arg("samplerate") = std::optional<int>(),
                     Rice::Arg("bitdepth") = std::optional<int>(),
                     Rice::Arg("channels") = std::optional<int>());

  Rice::define_module_under(native, "Audio")
      .define_singleton_function("set_request_recording_permission",
                                 &set_request_recording_permission, Rice::Arg("request"))
      .define_singleton_function("pause", &pause)
      .define_singleton_function("pause_source", &pause_source, Rice::Arg("source"))
      .define_singleton_function("recording_devices", &recording_devices)
      .define_singleton_function("active_effects", &active_effects)
      .define_singleton_function("playback_devices", &playback_devices)
      .define_singleton_function("output_spatialization_filters", &output_spatialization_filters)
      .define_singleton_function("set_effect", &set_effect, Rice::Arg("name"),
                                 Rice::Arg("settings"))
      .define_singleton_function("effect", &effect, Rice::Arg("name"))
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
