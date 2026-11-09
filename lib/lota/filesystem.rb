# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "filesystem/file"
require_relative "filesystem/file_data"
require_relative "filesystem/info"

module Lota
  # Files and the bytes read from them, translated from love.filesystem.
  #
  # A game reads its images, sounds, and fonts from its own folder, and
  # keeps what it saves, such as its settings or a saved game, in a folder
  # of its own that the player cannot lose by moving the game. LÖVE's
  # filesystem gives a game both through one set of names: a file is found
  # in the save directory first, if the game saved one there, and in the
  # game's folder otherwise, and every file the game writes goes to the
  # save directory.
  #
  # Lota::Filesystem is that filesystem. The save directory is the
  # system's application data folder (on macOS, Library/Application
  # Support in your home; on Linux, +XDG_DATA_HOME+, or .local/share in
  # your home without it), then a folder named +Lota+, or on Linux +lota+,
  # as LÖVE names its own +LOVE+ and +love+, then the game's identity,
  # which is its folder's name until its conf.rb names another
  # (<tt>t.identity</tt>). A shipped game, which <tt>lota fuse</tt> fuses,
  # saves without Lota's folder, where LÖVE's fused games save
  # (doc/contributors/design/game.md). FileData carries bytes and a name into
  # the engine.
  #
  # === Example
  #
  #   # conf.rb
  #   def Lota.conf(t)
  #     t.identity = "asteroids"
  #   end
  #
  #   # main.rb
  #   def Lota.load
  #     Lota::Filesystem.save_directory # => ".../Application Support/Lota/asteroids"
  #     Lota::Filesystem.lines("scores.txt").each { |line| puts line }
  #   end
  module Filesystem
    # Whether the game is fused into an application of its own, as a
    # shipped game is, matching love.filesystem.isFused
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_isFused). A game
    # <tt>lota run</tt> runs is not.
    #
    # === Example
    #
    #   Lota::Filesystem.fused? # => false
    def self.fused?
      Native::Filesystem.fused?
    end

    # Marks the game fused, or not, matching love.filesystem.setFused
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_setFused).
    #
    # [fused] Whether it is: any value, true unless +false+ or +nil+.
    #
    # Only the first call counts, as in LÖVE, and Lota::Boot makes it
    # before the game's code runs, so a game cannot change it: it is how
    # the program that starts a game says what it is. <tt>lota run</tt>
    # marks the game not fused; the entry script <tt>lota fuse</tt> writes,
    # which ships a game, marks it fused (Lota::Boot.new's +fused+).
    #
    # === Example
    #
    #   Lota::Filesystem.fused = true
    def self.fused=(fused)
      Native::Filesystem.set_fused(fused ? true : false)
    end

    # The name of the game's save directory, matching
    # love.filesystem.getIdentity
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getIdentity).
    #
    # It is the game's folder's name, or what its conf.rb sets
    # (<tt>t.identity</tt>), as Lota::Boot sets it.
    #
    # === Example
    #
    #   Lota::Filesystem.identity # => "asteroids"
    def self.identity
      Native::Filesystem.identity
    end

    # Names the game's save directory, matching
    # love.filesystem.setIdentity
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_setIdentity), with
    # its two values as one Array (rule 6 of
    # doc/contributors/design/translation.md).
    #
    # [identity] The String name, or an Array of the name and whether the
    #   save directory is searched after the game's folder rather than
    #   before it, which is +false+ when left out.
    #
    # The directory is made the first time the game writes to it. Raises
    # RuntimeError (<tt>"Could not set write directory."</tt>) for an
    # empty name, or while a file in the old save directory is open, as
    # in LÖVE.
    #
    # === Examples
    #
    #   Lota::Filesystem.identity = "asteroids"
    #   Lota::Filesystem.identity = "asteroids", true
    def self.identity=(identity)
      name, append = identity.is_a?(Array) ? identity : [identity, false]
      Native::Filesystem.set_identity(name, append || false)
    end

    # The full path of the game's save directory, matching
    # love.filesystem.getSaveDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getSaveDirectory).
    # The directory may not exist yet: it is made the first time the game
    # writes to it.
    #
    # === Example
    #
    #   Lota::Filesystem.save_directory
    #   # => "/Users/you/Library/Application Support/Lota/asteroids" on macOS
    #   # => "/home/you/.local/share/lota/asteroids" on Linux
    def self.save_directory
      Native::Filesystem.save_directory
    end

    # Makes a directory, and any directories above it, in the save
    # directory, matching love.filesystem.createDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_createDirectory).
    #
    # [name] String path of the directory, inside the save directory.
    #
    # Returns +true+ when it made the directory or it already existed, and
    # +false+ when it could not.
    #
    # === Example
    #
    #   Lota::Filesystem.create_directory("replays/2026") # => true
    def self.create_directory(name)
      Native::Filesystem.create_directory(name)
    end

    # Deletes a file, or an empty directory, from the save directory,
    # matching love.filesystem.remove
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_remove).
    #
    # [name] String path of what to delete, inside the save directory.
    #
    # Returns +true+ when it deleted it, and +false+ when it could not,
    # as when there is no such file or the directory is not empty. A file
    # in the game's folder is never deleted.
    #
    # === Example
    #
    #   Lota::Filesystem.remove("savegame.dat") # => true
    def self.remove(name)
      Native::Filesystem.remove(name)
    end

    # What the filesystem knows of a file or directory, as a frozen Info,
    # or +nil+ when there is none, matching love.filesystem.getInfo
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getInfo), whose table
    # becomes an Info (rule 10 of doc/contributors/design/translation.md).
    #
    # [path] String path, found in the save directory or the game's
    #   folder.
    # [filtertype] +:file+, +:directory+, +:symlink+, or +:other+: when
    #   given, a path of another type is as if there were none.
    #
    # LÖVE also fills in a table the caller passes, to save making a new
    # one; an Info is frozen, so Lota makes a new one each time and takes
    # no table. Raises ArgumentError for an unknown +filtertype+.
    #
    # === Examples
    #
    #   Lota::Filesystem.info("settings.txt")&.size # => 18
    #   Lota::Filesystem.info("replays", :directory) # => nil, if replays is a file
    def self.info(path, filtertype = nil)
      fields = Native::Filesystem.info(path, filtertype && EnumName.of(filtertype))
      return nil unless fields

      type, readonly, size, modtime = fields
      Info.new(type: type.to_sym, readonly:, size:, modtime:)
    end

    # Reads a file, matching love.filesystem.read
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_read).
    #
    # [filename] String path of the file, found in the save directory or
    #   the game's folder.
    # [size] Integer most bytes to read; the whole file when +nil+, left
    #   out, or negative.
    #
    # Returns an Array of LÖVE's two results (rule 4 of
    # doc/contributors/design/translation.md): the contents as a String and how
    # many bytes they are, or +nil+ and a message String when the file cannot be
    # read, so <tt>.first</tt> is +nil+ exactly when Lua's first result is. The
    # String is in Ruby's default external encoding, as File.read's is, holding
    # the file's bytes as they are. LÖVE can also read into a FileData, given
    # <tt>"data"</tt> first; Lota binds that form later.
    #
    # === Examples
    #
    #   contents, size = Lota::Filesystem.read("savegame.dat")
    #   Lota::Filesystem.read("missing.txt") # => [nil, "Could not open file missing.txt. Does not exist."]
    def self.read(filename, size = nil)
      Native::Filesystem.read(filename, size || -1)
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # Loads a file of Ruby code without running it. A game keeps levels,
    # mods, or settings as code in its save directory or in an archive it
    # mounts, where +require+, which searches $LOAD_PATH, never looks.
    # load reads the file through the filesystem, from the save
    # directory, the game's folder, or anything mounted, compiles it at
    # once, and returns an Array (ADR 001, rule 4) of a Proc that runs the
    # code each time it is called, or of +nil+ and LÖVE's message when the
    # file cannot be read. It matches love.filesystem.load
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_load), which loads a
    # file of Lua.
    #
    # [name] String path of the file, which backtraces name, as LÖVE
    #   names a chunk after its file.
    # [mode] LÖVE's load mode: +:t+ for text, +:b+ for binary, or +:bt+
    #   for either, which it is when +nil+ or left out (ADR 001, rule 9).
    #
    # The code runs at Ruby's top level, as a file Ruby loads does, so the
    # classes and methods it defines are the program's, and the Proc
    # returns the value of its last expression. A Lua chunk takes the
    # arguments it is called with as <tt>...</tt>, as a Ruby file takes
    # its own as ARGV, so while the Proc runs ARGV holds the arguments it
    # was called with, and afterward the program's own again.
    #
    # Ruby code is text, so +:b+, which LuaJIT gives only binary chunks,
    # refuses every file it can read, with LuaJIT's message for a chunk of
    # the wrong mode. Raises SyntaxError, with LÖVE's message, for code
    # that does not compile, or in that mode, and ArgumentError for a mode
    # LÖVE does not know, before it reads the file.
    #
    # === Examples
    #
    #   Lota::Filesystem.write("level.rb", "ARGV.first * 2")
    #   level, = Lota::Filesystem.load("level.rb")
    #   level.call(21) # => 42
    #   Lota::Filesystem.load("missing.rb") # => [nil, "Could not open file missing.rb. Does not exist."]
    def self.load(name, mode = nil)
      source, mode_name = Native::Filesystem.load(name, mode && EnumName.of(mode))
      return [nil, mode_name] unless source

      # w_load raises luaL_error's message for a chunk Lua refuses as a
      # syntax error (wrap_Filesystem.cpp:796-797).
      raise SyntaxError, "Syntax error: #{WRONG_MODE}\n" unless mode_name.include?("t")

      [chunk(compile(source, name))]
    end

    # +source+ compiled as the file +name+, or LÖVE's SyntaxError
    # (wrap_Filesystem.cpp:796-797) with Ruby's message. Ruby reads a file
    # of code as UTF-8 unless a magic comment says otherwise. :nodoc:
    private_class_method def self.compile(source, name)
      RubyVM::InstructionSequence.compile(source.force_encoding(Encoding::UTF_8), name)
    rescue SyntaxError => e
      raise SyntaxError, "Syntax error: #{e.message}\n"
    end

    # SPDX-SnippetEnd

    # A Proc that runs +code+ at the top level with ARGV holding the
    # Proc's arguments, and gives the program's ARGV back after. :nodoc:
    private_class_method def self.chunk(code)
      lambda do |*arguments|
        argv = ARGV.dup
        ARGV.replace(arguments)
        begin
          code.eval
        ensure
          ARGV.replace(argv)
        end
      end
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2005-2026 Mike Pall
    # SPDX-License-Identifier: MIT

    # LuaJIT's message for a chunk its load mode refuses (v2.1,
    # src/lj_errmsg.h:115, raised by cpparser in src/lj_load.c:36-48). :nodoc:
    WRONG_MODE = "attempt to load chunk with wrong mode"

    # SPDX-SnippetEnd

    # Opens +filename+ in +mode+, matching love.filesystem.openFile
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_openFile), and
    # returns an Array of the Lota::Filesystem::File (rule 4 of
    # doc/contributors/design/translation.md), or of +nil+ and LÖVE's message
    # when it cannot be opened.
    #
    # [filename] The file's name, in the game's folder or its save
    #   directory, which a file opened to write or append is in.
    # [mode] +:r+ to read, +:w+ to write, +:a+ to append, or +:c+ to leave
    #   it closed (rule 9 of doc/contributors/design/translation.md).
    #
    # Raises ArgumentError for a mode LÖVE does not know.
    #
    # === Example
    #
    #   file, message = Lota::Filesystem.open_file("save.dat", :r)
    def self.open_file(filename, mode)
      opened(Native::Filesystem.open_file(filename, EnumName.of(mode)))
    end

    # Opens the file at +path+ on the computer, outside the game's folder
    # and its save directory, in +mode+, matching
    # love.filesystem.openNativeFile
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_openNativeFile), and
    # returns an Array of the Lota::Filesystem::File (ADR 001, rule 4), or
    # of +nil+ and LÖVE's message when it cannot be opened.
    #
    # [path] The file's full path, as the operating system names it.
    # [mode] +:r+ to read, +:w+ to write, +:a+ to append, or +:c+ to leave
    #   it closed (ADR 001, rule 9).
    #
    # Raises ArgumentError for a mode LÖVE does not know.
    #
    # === Example
    #
    #   file, message = Lota::Filesystem.open_native_file("/tmp/log.txt", :w)
    def self.open_native_file(path, mode)
      opened(Native::Filesystem.open_native_file(path, EnumName.of(mode)))
    end

    # +results+, as Native::Filesystem.open_file and open_native_file give
    # them, as their Ruby methods return them: the Lota::Filesystem::File,
    # or +nil+ and LÖVE's message. :nodoc:
    private_class_method def self.opened(results)
      native = results.first
      native.is_a?(Native::File) ? [File.__send__(:from_native, native)] : [nil, results.last.to_s]
    end

    # Writes a file in the save directory, replacing any file of the
    # name, matching love.filesystem.write
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_write).
    #
    # [filename] String path of the file, inside the save directory.
    # [data] String of the bytes to write, or a Lota::Filesystem::FileData,
    #   whose bytes it writes.
    # [size] Integer number of bytes of +data+ to write; all of them when
    #   +nil+ or left out.
    #
    # Returns an Array (rule 4 of doc/contributors/design/translation.md):
    # <tt>[true]</tt>, or +nil+ and a message String when the file cannot be
    # written, so <tt>.first</tt> is truthy exactly when Lua's result is. LÖVE
    # writes +size+ bytes even past the end of +data+, reading memory beyond it;
    # Lota writes no more than +data+ holds. Raises TypeError for +data+
    # that is neither.
    #
    # === Examples
    #
    #   Lota::Filesystem.write("settings.txt", "10\n6") # => [true]
    #   ok, message = Lota::Filesystem.write("", "x") # => [nil, "Could not open file . ..."]
    def self.write(filename, data, size = nil)
      case data
      when String then Native::Filesystem.write_string(filename, data, size)
      when FileData then Native::Filesystem.write_data(filename, data.__send__(:native), size)
      else raise TypeError, "wrong argument type #{data.class} (expected String or Lota::Filesystem::FileData)"
      end
    end

    # The lines of a file, each a String without its line ending, as an
    # Enumerator, or each given to the block, matching
    # love.filesystem.lines (src/modules/filesystem/wrap_Filesystem.cpp,
    # w_lines), whose iterator for Lua's +for+ becomes an Enumerator (rule 15 of
    # doc/contributors/design/translation.md).
    #
    # [filename] String path of the file, found in the save directory or
    # the game's folder.
    #
    # The file opens when you call this, as in LÖVE, and closes once its
    # last line is read, so the lines can be read only once: reading them
    # again raises RuntimeError (<tt>"File needs to stay in read
    # mode."</tt>), as calling LÖVE's iterator after its last line does.
    # A line ends
    # at "\n", and a "\r" before it is taken off too; text after the last
    # "\n" is a last line of its own. With a block, it returns +nil+.
    # Raises RuntimeError with the engine's message when the file cannot
    # be opened.
    #
    # === Examples
    #
    #   Lota::Filesystem.lines("settings.txt").to_a # => ["10", "6"]
    #
    #   Lota::Filesystem.lines("level1.txt") do |row|
    #     @rows << row
    #   end
    def self.lines(filename, &block)
      reader = Native::Filesystem::Lines.new(filename)
      return enumerate_lines(reader) unless block

      enumerate_lines(reader, &block)
    end

    # The lines +reader+ reads, as an Enumerator, or each given to the
    # block, after which it returns +nil+. :nodoc:
    private_class_method def self.enumerate_lines(reader)
      lines = Enumerator.new do |yielder|
        while (line = reader.next_line)
          yielder << line
        end
      end
      return lines unless block_given?

      lines.each { |line| yield line }
      nil
    end

    # Adds to the end of a file in the save directory, making it if there
    # is none, matching love.filesystem.append
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_append).
    #
    # [filename] String path of the file, inside the save directory.
    # [data] String of the bytes to add, or a Lota::Filesystem::FileData,
    #   whose bytes it adds.
    # [size] Integer number of bytes of +data+ to add; all of them when
    #   +nil+ or left out.
    #
    # Returns an Array (rule 4 of doc/contributors/design/translation.md),
    # <tt>[true]</tt>, or +nil+ and a message String when the file cannot be
    # written, as Lota::Filesystem.write does. Lota adds no more than +data+
    # holds. Raises TypeError for +data+ that is neither.
    #
    # === Example
    #
    #   Lota::Filesystem.append("log.txt", "level 2\n") # => [true]
    def self.append(filename, data, size = nil)
      case data
      when String then Native::Filesystem.append_string(filename, data, size)
      when FileData then Native::Filesystem.append_data(filename, data.__send__(:native), size)
      else raise TypeError, "wrong argument type #{data.class} (expected String or Lota::Filesystem::FileData)"
      end
    end

    # The names of the files and directories in a directory, as an Array
    # of Strings, matching love.filesystem.getDirectoryItems
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getDirectoryItems),
    # whose table becomes an Array.
    #
    # [dir] String path of the directory, in the save directory, the
    #   game's folder, or anything mounted, all of which it lists
    #   together.
    #
    # The names are only names, without +dir+ before them. A directory
    # that does not exist has no items.
    #
    # === Example
    #
    #   Lota::Filesystem.directory_items("levels") # => ["1.txt", "2.txt"]
    def self.directory_items(dir)
      Native::Filesystem.directory_items(dir)
    end

    # The directory a file is found in, matching
    # love.filesystem.getRealDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getRealDirectory), as
    # an Array (rule 4 of doc/contributors/design/translation.md) of the full
    # path of the save directory, the game's folder, or the archive it is in, or
    # of +nil+ and LÖVE's message when there is no such file.
    #
    # [filename] String path of the file.
    #
    # === Example
    #
    #   Lota::Filesystem.real_directory("settings.txt").first # => ".../Lota/asteroids"
    def self.real_directory(filename)
      Native::Filesystem.real_directory(filename)
    end

    # Whether +path+ names a file or directory the filesystem can find,
    # matching love.filesystem.exists
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_exists). Its name
    # keeps LÖVE's, as it is neither +is+ nor +has+ (rule 13 of
    # doc/contributors/design/translation.md).
    #
    # === Example
    #
    #   Lota::Filesystem.exists("settings.txt") # => true
    def self.exists(path)
      Native::Filesystem.exists(path)
    end

    # Mounts an archive or a folder, so that its files can be read as if
    # they were at +mountpoint+, matching love.filesystem.mount
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_mount), and returns
    # whether it could.
    #
    # The forms:
    #
    # [<tt>mount(archive, mountpoint, append = false)</tt>] +archive+ is
    #   the String path of a zip file or folder in the save directory or
    #   the game's folder.
    # [<tt>mount(data, archivename, mountpoint, append = false)</tt>]
    #   +data+ is any Lota::Data holding a zip file, mounted under the
    #   name +archivename+, which unmount takes.
    # [<tt>mount(file_data, mountpoint, append = false)</tt>] a
    #   Lota::Filesystem::FileData, mounted under its own filename.
    #
    # [append] Whether its files are found after the ones already mounted
    #   rather than before them.
    #
    # Mounts last until unmount, so they take no block
    # (doc/contributors/design/translation.md). LÖVE also mounts a NativeFile,
    # which Lota does not bind yet.
    #
    # === Examples
    #
    #   Lota::Filesystem.mount("dlc.zip", "dlc") # => true
    #   Lota::Filesystem.mount(data, "dlc.zip", "dlc")
    def self.mount(archive, *rest)
      case archive
      when String then Native::Filesystem.mount_archive(archive, string!(rest[0]), boolean!(rest[1]))
      when FileData
        return mount_data(archive, archive.filename, rest[0], rest[1]) unless rest[1].is_a?(String)

        mount_data(archive, string!(rest[0]), rest[1], rest[2])
      else mount_data(archive, string!(rest[0]), rest[1], rest[2])
      end
    end

    # Mounts +data+ as the archive +archivename+ at +mountpoint+. :nodoc:
    private_class_method def self.mount_data(data, archivename, mountpoint, append)
      Native::Filesystem.mount_data(data.__send__(:native), archivename, string!(mountpoint), boolean!(append))
    end

    # +value+, a String, or a TypeError, as luaL_checkstring raises for
    # anything else. :nodoc:
    private_class_method def self.string!(value)
      return value if value.is_a?(String)

      raise TypeError, "wrong argument type #{value.class} (expected String)"
    end

    # +value+, or +false+ for +nil+, as luax_optboolean reads a boolean
    # left out, or a TypeError for anything else. :nodoc:
    private_class_method def self.boolean!(value)
      case value
      when true, false then value
      when nil then false
      else raise TypeError, "wrong argument type #{value.class} (expected true or false)"
      end
    end

    # Unmounts what mount mounted, matching love.filesystem.unmount
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_unmount), and returns
    # whether it was mounted.
    #
    # [archive] The String path mount was given, or the Lota::Data it
    #   mounted.
    #
    # === Example
    #
    #   Lota::Filesystem.unmount("dlc.zip") # => true
    def self.unmount(archive)
      case archive
      when String then Native::Filesystem.unmount_archive(archive)
      else Native::Filesystem.unmount_data(archive.__send__(:native))
      end
    end

    # Mounts a folder or archive anywhere on the computer, given its full
    # path, matching love.filesystem.mountFullPath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_mountFullPath), and
    # returns whether it could.
    #
    # [fullpath] String full path of the folder or archive.
    # [mountpoint] String path its files are found at.
    # [permissions] +:read+, or +:readwrite+ to write to it too; +:read+
    #   when +nil+ or left out.
    # [append] Whether its files are found after the ones already mounted.
    #
    # Raises ArgumentError for permissions LÖVE does not know.
    #
    # === Example
    #
    #   Lota::Filesystem.mount_full_path("/Users/you/mods", "mods", :read) # => true
    def self.mount_full_path(fullpath, mountpoint, permissions = nil, append = false)
      Native::Filesystem.mount_full_path(fullpath, mountpoint, permissions && EnumName.of(permissions), append)
    end

    # Unmounts what mount_full_path mounted, matching
    # love.filesystem.unmountFullPath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_unmountFullPath), and
    # returns whether it was mounted.
    #
    # === Example
    #
    #   Lota::Filesystem.unmount_full_path("/Users/you/mods") # => true
    def self.unmount_full_path(fullpath)
      Native::Filesystem.unmount_full_path(fullpath)
    end

    # Mounts one of the system's folders, matching
    # love.filesystem.mountCommonPath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_mountCommonPath), and
    # returns whether it could.
    #
    # [commonpath] +:appsavedir+, +:appdocuments+, +:userhome+,
    #   +:userappdata+, +:userdesktop+, or +:userdocuments+.
    # [mountpoint] String path its files are found at.
    # [permissions] +:read+ or +:readwrite+; +:read+ when +nil+ or left
    #   out.
    # [append] Whether its files are found after the ones already mounted.
    #
    # A folder of the game's own (+:appsavedir+ and +:appdocuments+) is
    # made if it does not exist. A folder already mounted is not mounted
    # again, and returns +false+. Raises ArgumentError for a common path
    # or permissions LÖVE does not know.
    #
    # === Example
    #
    #   Lota::Filesystem.mount_common_path(:userdocuments, "documents", :read) # => true
    def self.mount_common_path(commonpath, mountpoint, permissions = nil, append = false)
      Native::Filesystem.mount_common_path(EnumName.of(commonpath), mountpoint, permissions && EnumName.of(permissions),
        append)
    end

    # Unmounts what mount_common_path mounted, matching
    # love.filesystem.unmountCommonPath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_unmountCommonPath),
    # and returns whether it was mounted. Raises ArgumentError for a
    # common path LÖVE does not know.
    #
    # === Example
    #
    #   Lota::Filesystem.unmount_common_path(:userdocuments) # => true
    def self.unmount_common_path(commonpath)
      Native::Filesystem.unmount_common_path(EnumName.of(commonpath))
    end

    # The full path of one of the system's folders, matching
    # love.filesystem.getFullCommonPath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getFullCommonPath).
    #
    # [commonpath] +:appsavedir+, +:appdocuments+, +:userhome+,
    #   +:userappdata+, +:userdesktop+, or +:userdocuments+.
    #
    # Raises ArgumentError for a common path LÖVE does not know.
    #
    # === Example
    #
    #   Lota::Filesystem.full_common_path(:userhome) # => "/Users/you"
    def self.full_common_path(commonpath)
      Native::Filesystem.full_common_path(EnumName.of(commonpath))
    end

    # The game's folder, or the archive it runs from, matching
    # love.filesystem.getSource
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getSource), as
    # Lota::Boot sets it.
    #
    # === Example
    #
    #   Lota::Filesystem.source # => "/Users/you/games/asteroids"
    def self.source
      Native::Filesystem.source
    end

    # The folder the game's folder is in, matching
    # love.filesystem.getSourceBaseDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getSourceBaseDirectory).
    #
    # === Example
    #
    #   Lota::Filesystem.source_base_directory # => "/Users/you/games"
    def self.source_base_directory
      Native::Filesystem.source_base_directory
    end

    # The folder the game was started in, matching
    # love.filesystem.getWorkingDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getWorkingDirectory).
    #
    # === Example
    #
    #   Lota::Filesystem.working_directory # => "/Users/you"
    def self.working_directory
      Native::Filesystem.working_directory
    end

    # The player's home folder, matching love.filesystem.getUserDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getUserDirectory).
    #
    # === Example
    #
    #   Lota::Filesystem.user_directory # => "/Users/you/"
    def self.user_directory
      Native::Filesystem.user_directory
    end

    # The system's application data folder, which holds the save
    # directory's folder, matching love.filesystem.getAppdataDirectory
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getAppdataDirectory).
    #
    # === Example
    #
    #   Lota::Filesystem.appdata_directory # => "/Users/you/Library/Application Support"
    def self.appdata_directory
      Native::Filesystem.appdata_directory
    end

    # The full path of the program running the game, matching
    # love.filesystem.getExecutablePath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getExecutablePath):
    # under <tt>lota run</tt>, Ruby's.
    #
    # === Example
    #
    #   Lota::Filesystem.executable_path # => "/usr/local/bin/ruby"
    def self.executable_path
      Native::Filesystem.executable_path
    end

    # +path+, a path on the computer, made absolute and without +.+ and
    # +..+, matching love.filesystem.canonicalizeRealPath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_canonicalizeRealPath).
    #
    # === Example
    #
    #   Lota::Filesystem.canonicalize_real_path("/Users/you/../you") # => "/Users/you"
    def self.canonicalize_real_path(path)
      Native::Filesystem.canonicalize_real_path(path)
    end

    # Whether the filesystem follows symbolic links, matching
    # love.filesystem.areSymlinksEnabled
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_areSymlinksEnabled).
    #
    # === Example
    #
    #   Lota::Filesystem.symlinks_enabled? # => true
    def self.symlinks_enabled?
      Native::Filesystem.symlinks_enabled?
    end

    # Sets whether the filesystem follows symbolic links, matching
    # love.filesystem.setSymlinksEnabled
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_setSymlinksEnabled).
    #
    # === Example
    #
    #   Lota::Filesystem.symlinks_enabled = false
    def self.symlinks_enabled=(enable)
      Native::Filesystem.set_symlinks_enabled(enable)
    end

    # Where LÖVE's +require+ looks for Lua modules in the game's
    # filesystem, matching love.filesystem.getRequirePath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getRequirePath): its
    # patterns joined by semicolons, each +?+ standing for a module's
    # name. Ruby's +require+ searches $LOAD_PATH instead
    # (doc/contributors/design/game.md), so Lota keeps the path as LÖVE does and
    # reads nothing with it.
    #
    # === Example
    #
    #   Lota::Filesystem.require_path # => "?.lua;?/init.lua"
    def self.require_path
      Native::Filesystem.require_path
    end

    # Sets the patterns require_path gives, matching
    # love.filesystem.setRequirePath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_setRequirePath).
    #
    # [path] String of patterns, separated by semicolons.
    #
    # === Example
    #
    #   Lota::Filesystem.require_path = "?.lua;lib/?.lua"
    def self.require_path=(path)
      Native::Filesystem.set_require_path(path)
    end

    # Where LÖVE's +require+ looks for C libraries in the game's
    # filesystem, matching love.filesystem.getCRequirePath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getCRequirePath):
    # its patterns joined by semicolons, each +??+ standing for a
    # library's file name. Ruby loads extensions through $LOAD_PATH, so
    # Lota keeps the path as LÖVE does and reads nothing with it.
    #
    # === Example
    #
    #   Lota::Filesystem.c_require_path # => "??"
    def self.c_require_path
      Native::Filesystem.c_require_path
    end

    # Sets the patterns c_require_path gives, matching
    # love.filesystem.setCRequirePath
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_setCRequirePath).
    #
    # === Example
    #
    #   Lota::Filesystem.c_require_path = "lib/??"
    def self.c_require_path=(path)
      Native::Filesystem.set_c_require_path(path)
    end
  end
end
