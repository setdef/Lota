// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/video.hpp"

#include "native/binding.hpp"

#include "audio/Source.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h"
#include "filesystem/File.h"
#include "filesystem/Filesystem.h"
#include "graphics/Graphics.h"
#include "graphics/Video.h"
#include "video/Video.h"
#include "video/VideoStream.h"
#include "video/theora/Video.h"

#include <memory>
#include <optional>
#include <string>

namespace lota::native {

using love::filesystem::File;
using love::video::VideoStream;

namespace {

constexpr const char *VIDEO = "Lota::Video";
constexpr const char *GRAPHICS = "Lota::Graphics";

// The video module, as LÖVE's instance() macro reaches it
// (vendor/love/src/modules/video/wrap_Video.cpp:33), on any thread, as
// LÖVE's thread module allows love.video on every thread, or an error
// where LÖVE would find none.
love::video::Video &video() {
  auto *instance = love::Module::getInstance<love::video::Video>(love::Module::M_VIDEO);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", VIDEO);
  }
  return *instance;
}

// The graphics module, on the main thread only (ADR 007).
love::graphics::Graphics &graphics() {
  require_main_thread(GRAPHICS);
  auto *instance = love::Module::getInstance<love::graphics::Graphics>(love::Module::M_GRAPHICS);
  if (instance == nullptr) {
    throw love::Exception("%s is not open.", GRAPHICS);
  }
  return *instance;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// luaopen_love_video (wrap_Video.cpp:66-84) creates the Theora video
// module once, whose worker thread decodes every stream's frames; it then
// lives as long as the process, as LÖVE's lives until the game quits.
void open() { open_module<love::video::Video, love::video::theora::Video>(love::Module::M_VIDEO); }

// Whether the module is open, as a game asks with "if love.video".
bool is_open() {
  return love::Module::getInstance<love::video::Video>(love::Module::M_VIDEO) != nullptr;
}

// w_newVideoStream (wrap_Video.cpp:35-52) once luax_getfile has its File:
// opens the File for reading unless it is open, and makes a stream of it,
// which the module's worker thread decodes. LÖVE cannot ask whether an
// open File is open for reading. Its one reference goes to the Ruby
// wrapper.
VideoStream *new_stream(File &file) {
  if (!file.isOpen() && !file.open(File::MODE_READ)) {
    throw love::Exception("File is not open and cannot be opened");
  }
  return video().newVideoStream(&file);
}

// w_newVideoStream with a filename, which luax_getfile
// (filesystem/wrap_Filesystem.cpp:308-330) makes a closed File of; the
// stream keeps its own reference to it, so this one is released.
VideoStream *new_video_stream(const std::string &filename) {
  const auto *filesystem =
      love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
  if (filesystem == nullptr) {
    throw love::Exception("Lota::Filesystem is not open.");
  }
  const love::StrongRef<File> file(filesystem->openFile(filename.c_str(), File::MODE_CLOSED),
                                   love::Acquire::NORETAIN);
  return new_stream(*file);
}

// w_newVideoStream with a File, which luax_getfile retains for the call.
VideoStream *new_video_stream_from_file(File &file) { return new_stream(file); }

// w_VideoStream_setSync (wrap_VideoStream.cpp:35-60), in the three forms
// it tells apart by the type of its argument. With a Source, the stream
// follows the Source's position and playback.
void set_sync_to_source(VideoStream &stream, love::audio::Source &source) {
  const love::StrongRef<VideoStream::FrameSync> sync(
      std::make_unique<VideoStream::SourceSync>(&source).release(), love::Acquire::NORETAIN);
  stream.setSync(sync.get());
}

// With another VideoStream, the stream shares that stream's sync.
void set_sync_to_stream(VideoStream &stream, const VideoStream &other) {
  stream.setSync(other.getSync());
}

// With nil, the stream keeps time itself again, from where its sync is
// and playing or paused as it was.
void set_sync_to_delta(VideoStream &stream) {
  const love::StrongRef<VideoStream::DeltaSync> sync(
      std::make_unique<VideoStream::DeltaSync>().release(), love::Acquire::NORETAIN);
  sync->copyState(stream.getSync());
  stream.setSync(sync.get());
}

// w_newVideo (graphics/wrap_Graphics.cpp:2349-2364) with a VideoStream: a
// Video that draws its frames at +dpiscale+, once luax_checkgraphicscreated
// (lines 56-61) finds a window. Its one reference goes to the Ruby
// wrapper.
love::graphics::Video *new_video(VideoStream &stream, double dpiscale) {
  love::graphics::Graphics &instance = graphics();
  if (!instance.isCreated()) {
    throw love::Exception("%s cannot function without a window.", GRAPHICS);
  }
  return instance.newVideo(&stream, static_cast<float>(dpiscale));
}

// w_Video_setSource (graphics/wrap_Video.cpp:56-67), which LÖVE names
// _setSource for wrap_Video.lua's setSource to call: the Source the Video
// plays and stops with, or none.
void set_source(love::graphics::Video &video, std::optional<love::audio::Source *> source) {
  require_main_thread(GRAPHICS);
  if (!source.has_value()) {
    video.setSource(nullptr);
  } else {
    video.setSource(required(source, "source"));
  }
}

// SPDX-SnippetEnd

} // namespace

void define_video(const Rice::Module &native) {
  // Their other methods are generated (ext/lota/native/generated/video.cpp
  // and graphics.cpp).
  define_engine_class<VideoStream>(native, "VideoStream")
      .define_method("set_sync_to_source", &set_sync_to_source, Rice::Arg("source"))
      .define_method("set_sync_to_stream", &set_sync_to_stream, Rice::Arg("other"))
      .define_method("set_sync_to_delta", &set_sync_to_delta);

  Rice::define_module_under(native, "Video")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_video_stream", &new_video_stream, Rice::Arg("filename"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_video_stream_from_file", &new_video_stream_from_file,
                                 Rice::Arg("file"), Rice::Return().takeOwnership());

  define_engine_class<love::graphics::Video>(Rice::define_module_under(native, "Graphics"), "Video")
      .define_method("set_source", &set_source,
                     Rice::Arg("source") = std::optional<love::audio::Source *>());
  Rice::define_module_under(native, "Graphics")
      .define_singleton_function("new_video", &new_video, Rice::Arg("stream"),
                                 Rice::Arg("dpiscale"), Rice::Return().takeOwnership());
}

} // namespace lota::native
