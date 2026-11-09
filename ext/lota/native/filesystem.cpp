// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/filesystem.hpp"

#include "native/binding.hpp"
#include "native/errors.hpp"

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/int.h"
#include "data/DataModule.h"
#include "filesystem/File.h"
#include "filesystem/FileData.h"
#include "filesystem/Filesystem.h"
#include "filesystem/physfs/Filesystem.h"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

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

// The filesystem module, as LÖVE's instance() macro reaches it
// (wrap_Filesystem.cpp:50), or a RuntimeError when it is not open.
love::filesystem::Filesystem *filesystem() {
  auto *opened =
      love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
  if (opened == nullptr) {
    throw love::Exception("Lota::Filesystem is not open.");
  }
  return opened;
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

// w_newFileData with one filename (wrap_Filesystem.cpp:430-439) reads it
// through luax_getfiledata asked for an I/O error (332-373): the module
// opens the file by its path without opening it for reading, then reads all
// of it, and a file it cannot read gives luax_ioError's nil and message in
// place of the FileData, as one Array either way (rule 4 of
// doc/contributors/design/translation.md). The FileData's one reference
// goes to the Ruby wrapper.
Rice::Array new_file_data_of_file(const std::string &filename) {
  const love::filesystem::Filesystem *const instance = filesystem();
  FileData *data = nullptr;
  try {
    const love::StrongRef<File> file(instance->openFile(filename.c_str(), File::MODE_CLOSED),
                                     love::Acquire::NORETAIN);
    data = file->read();
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }

  const love::StrongRef<FileData> held(data, love::Acquire::NORETAIN);
  Rice::Array results;
  results.push(data, false);
  return results;
}

// The largest integer a Lua number, a double, holds exactly, to which
// w_getInfo limits a size and a time (wrap_Filesystem.cpp:584-596).
constexpr love::int64 LARGEST_EXACT_DOUBLE = 0x20000000000000LL;

// w_getInfo (wrap_Filesystem.cpp:544-602): what the filesystem knows of
// +filepath+, as an Array of LÖVE's fields in the order it sets them
// (type, readonly, size, modtime), with nil for a size or time it leaves
// out because the filesystem could not tell, or nil when there is no such
// file, or none of the type +filtertype+ names. The table LÖVE fills in
// when given one is not bound: Lota::Filesystem.info makes a frozen Data
// of the fields (rule 28 of doc/contributors/design/translation.md).
Rice::Object info(const std::string &filepath, const std::optional<std::string> &filtertype) {
  using love::filesystem::Filesystem;
  Filesystem::Info info = {};

  Filesystem::FileType filter = Filesystem::FILETYPE_MAX_ENUM;
  if (filtertype.has_value() && !Filesystem::getConstant(filtertype->c_str(), filter)) {
    raise_enum_error("file type", Filesystem::getConstants(filter), *filtertype);
  }

  if (!filesystem()->getInfo(filepath.c_str(), info)) {
    return {};
  }
  if (filter != Filesystem::FILETYPE_MAX_ENUM && info.type != filter) {
    return {};
  }

  const char *typestr = nullptr;
  if (!Filesystem::getConstant(info.type, typestr)) {
    throw love::Exception("Unknown file type.");
  }

  Rice::Array fields;
  fields.push(std::string(typestr), false);
  fields.push(info.readonly, false);
  info.size = std::min<love::int64>(info.size, LARGEST_EXACT_DOUBLE);
  if (info.size >= 0) {
    fields.push(static_cast<long long>(info.size), false);
  } else {
    fields.push(Rice::Object(), false);
  }
  info.modtime = std::min<love::int64>(info.modtime, LARGEST_EXACT_DOUBLE);
  if (info.modtime >= 0) {
    fields.push(static_cast<long long>(info.modtime), false);
  } else {
    fields.push(Rice::Object(), false);
  }
  return fields;
}

// w_read (wrap_Filesystem.cpp:618-659): the first +size+ bytes of
// +filename+, or all of it when +size+ is negative, as a String, or as a
// FileData when +container+ is "data", and how many bytes it read, or
// luax_ioError's nil and message when it cannot read the file, as one Array
// either way (rule 4 of doc/contributors/design/translation.md). The
// container is checked first, before the file is touched, as
// luax_checkcontainertype is (the FileData's wrapper keeps its own
// reference).
Rice::Array read(const std::string &filename, long long size,
                 const std::optional<std::string> &container) {
  love::data::ContainerType ctype = love::data::CONTAINER_STRING;
  if (container.has_value() && !love::data::getConstant(container->c_str(), ctype)) {
    raise_enum_error("container type", love::data::getConstants(ctype), *container);
  }

  FileData *data = nullptr;
  try {
    if (size >= 0) {
      data = filesystem()->read(filename.c_str(), size);
    } else {
      data = filesystem()->read(filename.c_str());
    }
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }

  if (data == nullptr) {
    return io_error("File could not be read.");
  }

  // Ruby has a copy once it is pushed, so the FileData is released.
  const love::StrongRef<FileData> held(data, love::Acquire::NORETAIN);
  Rice::Array results;
  if (ctype == love::data::CONTAINER_DATA) {
    results.push(data, false);
  } else {
    results.push(std::string(static_cast<const char *>(data->getData()), data->getSize()), false);
  }
  results.push(static_cast<long long>(data->getSize()), false);
  return results;
}

// w_load up to its call into Lua (wrap_Filesystem.cpp:746-775): checks +mode+,
// LÖVE's load mode ("bt" when it is not given), before anything is read, then
// reads all of +filename+ through the filesystem, and returns the file's
// contents and the mode's name, which LÖVE passes on to luaL_loadbufferx, as
// one Array, or luax_ioError's nil and message when it cannot read the file
// (rule 4 of doc/contributors/design/translation.md). Lua compiles the chunk;
// Ruby compiles Lota's (Lota::Filesystem.load).
Rice::Array load(const std::string &filename, const std::optional<std::string> &mode) {
  using love::filesystem::Filesystem;
  Filesystem::LoadMode load_mode = Filesystem::LOADMODE_ANY;
  if (mode.has_value() && !Filesystem::getConstant(mode->c_str(), load_mode)) {
    raise_enum_error("load mode", Filesystem::getConstants(load_mode), *mode);
  }

  FileData *data = nullptr;
  try {
    data = filesystem()->read(filename.c_str());
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }

  const love::StrongRef<FileData> held(data, love::Acquire::NORETAIN);
  const char *mode_name = nullptr;
  Filesystem::getConstant(load_mode, mode_name);
  Rice::Array results;
  results.push(std::string(static_cast<const char *>(data->getData()), data->getSize()), false);
  results.push(std::string(mode_name), false);
  return results;
}

// The number of bytes to write of an input that holds +length+: +size+,
// or all of it when +size+ is not given. LÖVE writes +size+ bytes
// whatever +length+ is, reading past the input for a larger size; Lota
// writes at most +length+, since Ruby reads no memory past a String.
love::int64 write_length(std::size_t length, std::optional<long long> size) {
  return static_cast<love::int64>(std::clamp<long long>(
      size.value_or(static_cast<long long>(length)), 0, static_cast<long long>(length)));
}

// w_write_or_append (wrap_Filesystem.cpp:661-701): writes, or with
// File::MODE_APPEND appends, +size+ bytes of +input+, which holds
// +length+, to +filename+ in the save directory, and returns true, or
// luax_ioError's nil and message, as one Array either way (rule 4 of
// doc/contributors/design/translation.md).
Rice::Array write_or_append(const std::string &filename, const void *input, std::size_t length,
                            std::optional<long long> size, File::Mode mode) {
  const love::int64 len = write_length(length, size);
  try {
    if (mode == File::MODE_APPEND) {
      filesystem()->append(filename.c_str(), input, len);
    } else {
      filesystem()->write(filename.c_str(), input, len);
    }
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }

  Rice::Array results;
  results.push(true, false);
  return results;
}

// love.filesystem.write with a string (w_write).
Rice::Array write_string(const std::string &filename, const std::string &contents,
                         std::optional<long long> size) {
  return write_or_append(filename, contents.data(), contents.size(), size, File::MODE_WRITE);
}

// love.filesystem.write with a Data, whose bytes it writes.
Rice::Array write_data(const std::string &filename, const love::Data *data,
                       std::optional<long long> size) {
  return write_or_append(filename, data->getData(), data->getSize(), size, File::MODE_WRITE);
}

// love.filesystem.append with a string (w_append).
Rice::Array append_string(const std::string &filename, const std::string &contents,
                          std::optional<long long> size) {
  return write_or_append(filename, contents.data(), contents.size(), size, File::MODE_APPEND);
}

// love.filesystem.append with a Data, whose bytes it appends.
Rice::Array append_data(const std::string &filename, const love::Data *data,
                        std::optional<long long> size) {
  return write_or_append(filename, data->getData(), data->getSize(), size, File::MODE_APPEND);
}

// w_getDirectoryItems (wrap_Filesystem.cpp:708-725): the names in +dir+,
// in the order the filesystem gives them, as an Array where LÖVE fills a
// table.
Rice::Array directory_items(const std::string &dir) {
  std::vector<std::string> items;
  filesystem()->getDirectoryItems(dir.c_str(), items);

  Rice::Array names;
  for (const std::string &item : items) {
    names.push(item, false);
  }
  return names;
}

// w_getRequirePath and w_getCRequirePath (wrap_Filesystem.cpp:803-835):
// the path's elements, joined with semicolons.
std::string joined(const std::vector<std::string> &elements) {
  std::string path;
  bool separator = false;
  for (const std::string &element : elements) {
    if (separator) {
      path += ';';
    } else {
      separator = true;
    }
    path += element;
  }
  return path;
}

// w_setRequirePath and w_setCRequirePath (wrap_Filesystem.cpp:837-865):
// +elements+ cleared, then filled with +path+'s parts between semicolons.
void split_into(const std::string &path, std::vector<std::string> &elements) {
  elements.clear();
  std::stringstream stream;
  stream << path;
  std::string element;
  while (std::getline(stream, element, ';')) {
    elements.push_back(element);
  }
}

std::string require_path() { return joined(filesystem()->getRequirePath()); }

void set_require_path(const std::string &path) { split_into(path, filesystem()->getRequirePath()); }

std::string c_require_path() { return joined(filesystem()->getCRequirePath()); }

void set_c_require_path(const std::string &path) {
  split_into(path, filesystem()->getCRequirePath());
}

// w_mount with an archive's path (wrap_Filesystem.cpp:139-150): the
// archive, in the save directory or the game's source, mounted at
// +mountpoint+.
bool mount_archive(const std::string &archive, const std::string &mountpoint, bool append) {
  return filesystem()->mount(archive.c_str(), mountpoint.c_str(), append);
}

// w_mount with a Data (wrap_Filesystem.cpp:115-137): its bytes, an
// archive named +archive+, mounted at +mountpoint+. The filesystem keeps
// its own reference to the Data while it is mounted.
bool mount_data(love::Data *data, const std::string &archive, const std::string &mountpoint,
                bool append) {
  return filesystem()->mount(data, archive.c_str(), mountpoint.c_str(), append);
}

// w_unmount with an archive's path (wrap_Filesystem.cpp:206-209).
bool unmount_archive(const std::string &archive) { return filesystem()->unmount(archive.c_str()); }

// w_unmount with a Data (wrap_Filesystem.cpp:200-204).
bool unmount_data(love::Data *data) { return filesystem()->unmount(data); }

// w_File_read (wrap_File.cpp:110-145): the next +size+ bytes of +file+,
// or as many as the file holds when +size+ is negative, as LÖVE asks for
// the file's size then, as a String, or as a FileData when +container+
// is "data", and how many bytes they are, as one Array, or luax_ioError's
// nil and message (rule 4 of doc/contributors/design/translation.md). Ruby's
// wrapper keeps its own reference to a FileData.
Rice::Array file_read(File &file, const std::optional<std::string> &container, double size) {
  love::data::ContainerType ctype = love::data::CONTAINER_STRING;
  if (container.has_value() && !love::data::getConstant(container->c_str(), ctype)) {
    raise_enum_error("container type", love::data::getConstants(ctype), *container);
  }

  auto length = static_cast<love::int64>(size);
  FileData *data = nullptr;
  try {
    if (length < 0) {
      length = file.getSize();
    }
    data = file.read(length);
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }
  const love::StrongRef<FileData> held(data, love::Acquire::NORETAIN);
  Rice::Array results;
  if (ctype == love::data::CONTAINER_DATA) {
    results.push(data, false);
  } else {
    results.push(std::string(static_cast<const char *>(data->getData()), data->getSize()), false);
  }
  results.push(static_cast<long long>(data->getSize()), false);
  return results;
}

// w_File_getSize (wrap_File.cpp:51-73): +file+'s size, as an Array of
// the Integer, or of luax_ioError's nil and message when the engine
// cannot tell it or a Lua number could not hold it exactly (rule 4 of
// doc/contributors/design/translation.md).
Rice::Array file_size(File &file) {
  love::int64 size = -1;
  try {
    size = file.getSize();
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }

  // Push nil on failure or if size does not fit into a double precision floating-point number.
  if (size == -1) {
    return io_error("Could not determine file size.");
  }
  if (size >= LARGEST_EXACT_DOUBLE) {
    return io_error("Size is too large.");
  }
  Rice::Array results;
  results.push(static_cast<long long>(size), false);
  return results;
}

// w_File_tell (wrap_File.cpp:213-225): where in +file+ the next read or
// write is, as an Array of the Integer, or of luax_ioError's nil and
// message (rule 4 of doc/contributors/design/translation.md).
Rice::Array file_tell(File &file) {
  const love::int64 pos = file.tell();
  // Push nil on failure or if pos does not fit into a double precision floating-point number.
  if (pos == -1) {
    return io_error("Invalid position.");
  }
  if (pos >= LARGEST_EXACT_DOUBLE) {
    return io_error("Number is too large.");
  }
  Rice::Array results;
  results.push(static_cast<long long>(pos), false);
  return results;
}

// w_File_seek (wrap_File.cpp:227-239): moves +file+ to +pos+, and
// whether it could.
bool file_seek(File &file, double pos) {
  // Push false on negative and precision-problematic numbers.
  // Better fail than seek to an unknown position.
  if (pos < 0.0 || pos >= static_cast<double>(LARGEST_EXACT_DOUBLE)) {
    return false;
  }
  return file.seek(static_cast<love::int64>(pos));
}

// w_File_write (wrap_File.cpp:147-188): +size+ bytes of +input+, which
// holds +length+, written to +file+, and whether they were, or
// luax_ioError's nil and message, as one Array (rule 4 of
// doc/contributors/design/translation.md). Lota writes at most +length+, as
// love.filesystem.write does.
Rice::Array file_write(File &file, const void *input, std::size_t length,
                       std::optional<long long> size) {
  bool result = false;
  try {
    result = file.write(input, write_length(length, size));
  } catch (love::Exception &e) {
    return io_error("%s", e.what());
  }
  Rice::Array results;
  results.push(result, false);
  return results;
}

// File:write with a string.
Rice::Array file_write_string(File &file, const std::string &contents,
                              std::optional<long long> size) {
  return file_write(file, contents.data(), contents.size(), size);
}

// File:write with a Data, whose bytes it writes.
Rice::Array file_write_data(File &file, const love::Data *data, std::optional<long long> size) {
  return file_write(file, data->getData(), data->getSize(), size);
}

// The lines of a file, one at a time, as the iterators love.filesystem.lines
// and File:lines return give them (w_lines, wrap_Filesystem.cpp:727-744,
// w_File_lines, wrap_File.cpp:349-372, and w_File_lines_i, wrap_File.cpp:
// 241-347, whose upvalues are this class's members).
// Lota::Filesystem.lines and Lota::Filesystem::File#lines turn it into an
// Enumerator (rule 15 of doc/contributors/design/translation.md). The file is
// open for reading once it is made, and closes once the last line is read.
class Lines {
public:
  // Opens +filename+ in the game's filesystem for reading, or raises the
  // engine's error, as w_lines does through luax_catchexcept.
  explicit Lines(const std::string &filename)
      : file_(filesystem()->openFile(filename.c_str(), File::MODE_READ), love::Acquire::NORETAIN) {}

  // The lines of +file+, as w_File_lines reads them: a file already open
  // keeps the position its own reads and seeks leave it at, since each
  // read for the lines seeks to where the lines are and back again; a
  // file open to write or append is closed and opened to read, and one
  // that cannot be raises "Could not open file.", or the engine's error.
  static Lines *of_file(File &file) {
    auto lines = std::unique_ptr<Lines>(new Lines(file));
    return lines.release();
  }

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
      // If the user has changed the position, we need to seek back first
      // (wrap_File.cpp:276-286).
      love::int64 userpos = -1;
      if (seek_back_) {
        userpos = file_->tell();
        if (userpos != position_) {
          file_->seek(position_);
        }
      }
      read_until_newline();
      // Possibly seek back to the user position, but make sure to save
      // our target position too (wrap_File.cpp:304-311).
      if (seek_back_) {
        position_ = file_->tell();
        file_->seek(userpos);
      }
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
  // w_File_lines: whether the File was open, which makes the lines put
  // its position back after each read, then the File opened to read.
  explicit Lines(File &file) : file_(&file), seek_back_(file.getMode() != File::MODE_CLOSED) {
    if (file.getMode() == File::MODE_READ) {
      return;
    }
    if (file.getMode() != File::MODE_CLOSED) {
      file.close();
    }
    if (!file.open(File::MODE_READ)) {
      throw love::Exception("Could not open file.");
    }
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
  bool seek_back_ = false;
  love::int64 position_ = 0;
};

// SPDX-SnippetEnd

} // namespace

void define_filesystem(const Rice::Module &native) {
  define_engine_class<FileData, love::Data>(native, "FileData");
  auto file_class = define_engine_class<File>(native, "File");

  Rice::define_module_under(native, "Filesystem")
      .define_singleton_function("open", &open)
      .define_singleton_function("open?", &is_open)
      .define_singleton_function("new_file_data", &new_file_data, Rice::Arg("contents"),
                                 Rice::Arg("filename"), Rice::Return().takeOwnership())
      .define_singleton_function("file_data", &file_data, Rice::Arg("filename"),
                                 Rice::Return().takeOwnership())
      .define_singleton_function("new_file_data_of_file", &new_file_data_of_file,
                                 Rice::Arg("filename"))
      .define_singleton_function("info", &info, Rice::Arg("filepath"),
                                 Rice::Arg("filtertype") = std::optional<std::string>())
      .define_singleton_function("read", &read, Rice::Arg("filename"), Rice::Arg("size") = -1LL,
                                 Rice::Arg("container") = std::optional<std::string>())
      .define_singleton_function("load", &load, Rice::Arg("filename"),
                                 Rice::Arg("mode") = std::optional<std::string>())
      .define_singleton_function("write_string", &write_string, Rice::Arg("filename"),
                                 Rice::Arg("contents"),
                                 Rice::Arg("size") = std::optional<long long>())
      .define_singleton_function("write_data", &write_data, Rice::Arg("filename"),
                                 Rice::Arg("data"), Rice::Arg("size") = std::optional<long long>())
      .define_singleton_function("append_string", &append_string, Rice::Arg("filename"),
                                 Rice::Arg("contents"),
                                 Rice::Arg("size") = std::optional<long long>())
      .define_singleton_function("append_data", &append_data, Rice::Arg("filename"),
                                 Rice::Arg("data"), Rice::Arg("size") = std::optional<long long>())
      .define_singleton_function("directory_items", &directory_items, Rice::Arg("dir"))
      .define_singleton_function("require_path", &require_path)
      .define_singleton_function("set_require_path", &set_require_path, Rice::Arg("path"))
      .define_singleton_function("c_require_path", &c_require_path)
      .define_singleton_function("set_c_require_path", &set_c_require_path, Rice::Arg("path"))
      .define_singleton_function("mount_archive", &mount_archive, Rice::Arg("archive"),
                                 Rice::Arg("mountpoint"), Rice::Arg("append") = false)
      .define_singleton_function("mount_data", &mount_data, Rice::Arg("data"), Rice::Arg("archive"),
                                 Rice::Arg("mountpoint"), Rice::Arg("append") = false)
      .define_singleton_function("unmount_archive", &unmount_archive, Rice::Arg("archive"))
      .define_singleton_function("unmount_data", &unmount_data, Rice::Arg("data"));

  file_class.define_method("size", &file_size)
      .define_method("tell", &file_tell)
      .define_method("seek", &file_seek, Rice::Arg("pos"))
      .define_method("read", &file_read, Rice::Arg("container") = std::optional<std::string>(),
                     Rice::Arg("size") = -1.0)
      .define_method("write_string", &file_write_string, Rice::Arg("contents"),
                     Rice::Arg("size") = std::optional<long long>())
      .define_method("write_data", &file_write_data, Rice::Arg("data"),
                     Rice::Arg("size") = std::optional<long long>());

  Rice::define_class_under<Lines>(Rice::define_module_under(native, "Filesystem"), "Lines")
      .define_constructor(Rice::Constructor<Lines, const std::string &>(), Rice::Arg("filename"))
      .define_singleton_function("of_file", &Lines::of_file, Rice::Arg("file"),
                                 Rice::Return().takeOwnership())
      .define_method("next_line", &Lines::next_line);
}

} // namespace lota::native
