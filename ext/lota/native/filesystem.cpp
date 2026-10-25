// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/filesystem.hpp"

#include "native/binding.hpp"

#include "common/Data.h"
#include "filesystem/FileData.h"

#include <cstring>
#include <memory>
#include <string>

namespace lota::native {

using love::filesystem::FileData;

namespace {

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

// SPDX-SnippetEnd

} // namespace

void define_filesystem(const Rice::Module &native) {
  Rice::define_class_under<love::Data>(native, "Data");
  Rice::define_class_under<FileData, love::Data>(native, "FileData");

  Rice::define_module_under(native, "Filesystem")
      .define_singleton_function("new_file_data", &new_file_data, Rice::Arg("contents"),
                                 Rice::Arg("filename"), Rice::Return().takeOwnership());
}

} // namespace lota::native
