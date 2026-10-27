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

#include <cstddef>
#include <cstring>
#include <memory>
#include <optional>
#include <string>

namespace lota::native {

using love::filesystem::File;
using love::filesystem::FileData;

namespace {

// luaopen_love_filesystem (vendor/love/src/modules/filesystem/
// wrap_Filesystem.cpp:1112-1134) creates the PhysicsFS filesystem module
// once; it then lives as long as the process, as LÖVE's lives until the
// game quits. boot.lua opens it first of all (boot.lua:46), then
// initializes it and sets the game's folder as its source; Lota::Boot does
// the same, through the generated init and set_source.
void open() {
  open_module<love::filesystem::Filesystem, love::filesystem::physfs::Filesystem>(
      love::Module::M_FILESYSTEM);
}

// Whether the module is open.
bool is_open() {
  return love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM) !=
         nullptr;
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
  const auto *instance =
      love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
  if (instance == nullptr) {
    throw love::Exception("Lota::Filesystem is not open.");
  }
  const love::StrongRef<File> file(instance->openFile(filename.c_str(), File::MODE_CLOSED),
                                   love::Acquire::NORETAIN);
  return file->read();
}

// The lines of a file, one at a time, as the iterator love.filesystem.lines
// returns gives them (w_lines, wrap_Filesystem.cpp:727-744, and
// w_File_lines_i, wrap_File.cpp:241-347, whose upvalues are this class's
// members). Lota::Filesystem.lines turns it into an Enumerator (ADR 001,
// rule 15). The file opens for reading when it is made, as w_lines opens
// it, and closes once the last line is read.
class Lines {
public:
  // Opens +filename+ in the game's filesystem for reading, or raises the
  // engine's error, as w_lines does through luax_catchexcept.
  explicit Lines(const std::string &filename)
      : file_(instance()->openFile(filename.c_str(), File::MODE_READ), love::Acquire::NORETAIN) {}

  // The next line, without its '\n' and a '\r' before it, or nil once
  // the file is read. LÖVE reads a kilobyte at a time until the buffer
  // holds a whole line or the file ends; the last line ends at the end of
  // the file, and an empty last line is no line at all.
  std::optional<std::string> next_line() {
    if (file_->getMode() != File::MODE_READ) {
      throw love::Exception("File needs to stay in read mode.");
    }

    std::size_t end = buffer_.find('\n', offset_);
    if (end == std::string::npos && !file_->isEOF()) {
      buffer_.erase(0, offset_);
      offset_ = 0;
      read_until_newline();
      end = buffer_.find('\n');
    }

    const std::size_t start = offset_;
    if (end == std::string::npos) {
      end = buffer_.size() - 1;
    }
    offset_ = end + 1;

    if (start == buffer_.size()) {
      file_->close();
      return std::nullopt;
    }

    // end is the last character of the line, inclusive, as in LÖVE.
    std::size_t last = end;
    if (last + 1 > start && buffer_.at(last) == '\n') {
      --last;
    }
    if (last + 1 > start && buffer_.at(last) == '\r') {
      --last;
    }
    return buffer_.substr(start, last + 1 - start);
  }

private:
  static love::filesystem::Filesystem *instance() {
    auto *opened =
        love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
    if (opened == nullptr) {
      throw love::Exception("Lota::Filesystem is not open.");
    }
    return opened;
  }

  // Keep reading until newline or EOF (wrap_File.cpp:290-302).
  void read_until_newline() {
    constexpr int readbufsize = 1024;
    std::string readbuf(readbufsize, '\0');
    while (!file_->isEOF()) {
      const auto read = static_cast<int>(file_->read(readbuf.data(), readbufsize));
      if (read < 0) {
        throw love::Exception("Could not read from file.");
      }
      buffer_.append(readbuf, 0, static_cast<std::size_t>(read));
      if (readbuf.find('\n') < static_cast<std::size_t>(read)) {
        break;
      }
    }
  }

  love::StrongRef<File> file_;
  std::string buffer_;
  std::size_t offset_ = 0;
};

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

  Rice::define_class_under<Lines>(Rice::define_module_under(native, "Filesystem"), "Lines")
      .define_constructor(Rice::Constructor<Lines, const std::string &>(), Rice::Arg("filename"))
      .define_method("next_line", &Lines::next_line);
}

} // namespace lota::native
