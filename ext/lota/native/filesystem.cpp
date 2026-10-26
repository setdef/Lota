// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/filesystem.hpp"

#include "native/binding.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "filesystem/File.h"
#include "filesystem/FileData.h"
#include "filesystem/Filesystem.h"
#include "filesystem/physfs/Filesystem.h"

#include <cstring>
#include <memory>
#include <string>

namespace lota::native {

using love::filesystem::File;
using love::filesystem::FileData;
using love::filesystem::Filesystem;

namespace {

// luaopen_love_filesystem (vendor/love/src/modules/filesystem/
// wrap_Filesystem.cpp:1112-1134) creates the PhysicsFS filesystem module
// once; it then lives as long as the process, as LÖVE's lives until the
// game quits. boot.lua opens it first of all (boot.lua:46), then
// initializes it and sets the game's folder as its source; Lota::Boot does
// the same, through the generated init and set_source.
void open() {
  open_module<Filesystem, love::filesystem::physfs::Filesystem>(love::Module::M_FILESYSTEM);
}

// Whether the module is open.
bool is_open() {
  return love::Module::getInstance<Filesystem>(love::Module::M_FILESYSTEM) != nullptr;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from LÖVE's C++, as cited below, and changed to take its
// arguments from Rice instead of a lua_State.

// w_newFileData from a string and a name (vendor/love/src/modules/
// filesystem/wrap_Filesystem.cpp:428-463) calls Filesystem::newFileData,
// which copies the bytes into a new FileData (Filesystem.cpp:76-81). That
// function reads nothing of the filesystem module, so it is ported here
// rather than opening the module and its PhysicsFS state to reach it. The
// FileData's one reference goes to the Ruby wrapper.
FileData *new_file_data(const std::string &contents, const std::string &filename) {
  auto data = std::make_unique<FileData>(contents.size(), filename);
  std::memcpy(data->getData(), contents.data(), contents.size());
  return data.release();
}

// luax_getfiledata with a filename (wrap_Filesystem.cpp:308-379), as
// love.graphics.newFont and love.font's rasterizers read a font file by
// name: the module opens the file by its path in the game's source,
// without opening it for reading (File::MODE_CLOSED), then reads all of
// it. A file it cannot read raises the engine's message, as luaL_error
// does when luax_getfiledata is not asked for an I/O error; the File is
// released either way. The FileData's one reference goes to the Ruby
// wrapper.
FileData *file_data(const std::string &filename) {
  const auto *instance = love::Module::getInstance<Filesystem>(love::Module::M_FILESYSTEM);
  if (instance == nullptr) {
    throw love::Exception("Lota::Filesystem is not open.");
  }
  const love::StrongRef<File> file(instance->openFile(filename.c_str(), File::MODE_CLOSED),
                                   love::Acquire::NORETAIN);
  return file->read();
}

// SPDX-SnippetEnd

} // namespace

void define_filesystem(const Rice::Module &native) {
  define_engine_class<love::Data>(native, "Data");
  define_engine_class<FileData, love::Data>(native, "FileData");

  Rice::define_module_under(native, "Filesystem")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_file_data", &new_file_data, Rice::Arg("contents"),
                                 Rice::Arg("filename"), Rice::Return().takeOwnership())
      .define_singleton_function("file_data", &file_data, Rice::Arg("filename"),
                                 Rice::Return().takeOwnership());
}

} // namespace lota::native
