# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

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
  # Support in your home), then a folder named +Lota+, then the game's
  # identity, which is its folder's name until its conf.rb names another
  # (<tt>t.identity</tt>). A shipped game, which ADR 002's launcher fuses,
  # saves without the +Lota+ folder, where LÖVE's fused games save (ADR
  # 003, section 8). FileData carries bytes and a name into the engine.
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
    # marks the game not fused; ADR 002's launcher, which ships a game,
    # will mark it fused (Lota::Boot.new's +fused+).
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
    # its two values as one Array (ADR 001, rule 6).
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
    #   # => "/Users/you/Library/Application Support/Lota/asteroids"
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
    # becomes an Info (ADR 001, rule 10).
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
    # Returns an Array of LÖVE's two results (ADR 001, rule 4): the
    # contents as a String and how many bytes they are, or +nil+ and a
    # message String when the file cannot be read, so <tt>.first</tt> is
    # +nil+ exactly when Lua's first result is. The String is in Ruby's
    # default external encoding, as File.read's is, holding the file's
    # bytes as they are. LÖVE can also read into a FileData, given
    # <tt>"data"</tt> first; Lota binds that form later.
    #
    # === Examples
    #
    #   contents, size = Lota::Filesystem.read("savegame.dat")
    #   Lota::Filesystem.read("missing.txt") # => [nil, "Could not open file missing.txt. Does not exist."]
    def self.read(filename, size = nil)
      Native::Filesystem.read(filename, size || -1)
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
    # Returns an Array (ADR 001, rule 4): <tt>[true]</tt>, or +nil+ and a
    # message String when the file cannot be written, so
    # <tt>.first</tt> is truthy exactly when Lua's result is. LÖVE writes
    # +size+ bytes even past the end of +data+, reading memory beyond it;
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
      when FileData then Native::Filesystem.write_data(filename, data.native, size)
      else raise TypeError, "wrong argument type #{data.class} (expected String or Lota::Filesystem::FileData)"
      end
    end

    # The lines of a file, each a String without its line ending, as an
    # Enumerator, or each given to the block, matching
    # love.filesystem.lines (src/modules/filesystem/wrap_Filesystem.cpp,
    # w_lines), whose iterator for Lua's +for+ becomes an Enumerator (ADR
    # 001, rule 15).
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
    def self.lines(filename)
      reader = Native::Filesystem::Lines.new(filename)
      lines = Enumerator.new do |yielder|
        while (line = reader.next_line)
          yielder << line
        end
      end
      return lines unless block_given?

      lines.each { |line| yield line }
      nil
    end
  end
end
