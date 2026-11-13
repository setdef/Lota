# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"

module Lota
  # A game in one file: its folder, zipped, which <tt>lota run</tt> plays
  # as <tt>love game.love</tt> plays a LÖVE game (ADR 016).
  #
  # LÖVE reads a <tt>.love</tt> in place, through PhysFS. Ruby loads code
  # only from real files, and a game's Ruby should behave as it does from
  # its folder: +require+, +require_relative+, +__dir__+, +File+, and its
  # error messages. So Lota unpacks the whole archive, through the same
  # PhysFS that mounts it as the game's source, into a folder of a cache,
  # and the game's Ruby runs from there, while Lota::Filesystem still
  # reads the archive, as LÖVE's filesystem does.
  #
  # The folder is named for the first 16 hexadecimal digits of the
  # archive's SHA-256, so an archive that changes unpacks anew, and one
  # that does not is unpacked once. The unpack is written to a folder of
  # its own and renamed into place once it holds every file, with a
  # record of what it holds, so a folder some other unpack left half
  # written, or something has since emptied, is never played: it is
  # unpacked again.
  #
  # Before it writes anything, it refuses an archive with an entry it
  # cannot unpack safely, naming the entry: one that would land outside
  # the folder, or match another but for case, or that Windows cannot
  # name, or that is native code, which LÖVE cannot load from a
  # <tt>.love</tt> either, or a symbolic link, or one whose path is
  # longer than Windows allows where long paths are not enabled.
  #
  # === Example
  #
  #   # With the game's source set to the archive, as Lota::Boot sets it.
  #   archive = Lota::Archive.new("games/pong.lota")
  #   archive.unpack(Lota::Archive.cache_directory("Linux", ENV, Dir.home))
  #   # => "/home/you/.cache/lota/games/9f86d081884c7d65/game"
  class Archive
    # Raised for an archive Lota will not unpack, with a message that
    # names the archive and the entry.
    class Refused < RuntimeError; end

    # Names of native code a game might load, which a <tt>.lota</tt> may
    # not hold: LÖVE's require loads a C module only from a real folder,
    # never from inside a <tt>.love</tt> (wrap_Filesystem.cpp:1004-1011).
    NATIVE = /\.(?:so|bundle|dll|dylib)(?:\.[0-9]+)*\z/i

    # Characters Windows forbids in a file's name: the reserved ones and
    # every control character
    # (https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file).
    # A backslash is Windows' separator, so a name holding one would land
    # in another folder there.
    FORBIDDEN = /[<>:"|?*\\\x00-\x1f]/

    # Names Windows reserves for devices, alone or before an extension.
    RESERVED = /\A(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|\z)/i

    # The longest path Windows opens a file at where long paths are not
    # enabled: MAX_PATH less its terminating null.
    FILE_PATH_LIMIT = 259

    # The longest path Windows makes a folder at where long paths are not
    # enabled, which must leave room for an 8.3 name in it
    # (CreateDirectoryW).
    FOLDER_PATH_LIMIT = 247

    # The file in an unpacked folder that records what the folder holds,
    # written before the folder is renamed into place.
    RECORD = "unpacked"

    # What the record's first line starts with.
    RECORD_HEADER = "lota-archive 1"

    # The archive's path, as an absolute path.
    attr_reader :path

    # The folder of the cache, under the system's folder for caches, that
    # Lota unpacks archives in, for the system named +os+ as
    # Lota::System.os names it, the environment +env+, and the home folder
    # +home+: XDG_CACHE_HOME when it is an absolute path, as the XDG Base
    # Directory Specification asks, or <tt>.cache</tt> in the home, on Linux;
    # the home's Library/Caches on macOS; and the local application data
    # folder on Windows.
    #
    # === Example
    #
    #   Lota::Archive.cache_directory("OS X", ENV, "/Users/you")
    #   # => "/Users/you/Library/Caches/Lota/games"
    def self.cache_directory(os, env, home)
      root = case os
      when "Windows" then File.join((env["LOCALAPPDATA"] || File.join(home, "AppData/Local")).tr("\\", "/"), "Lota/Cache")
      when "OS X" then File.join(home, "Library/Caches/Lota")
      else
        xdg = env["XDG_CACHE_HOME"]
        File.join(xdg&.start_with?("/") ? xdg : File.join(home, ".cache"), "lota")
      end
      File.join(root, "games")
    end

    # Prepares to unpack the archive at +path+.
    def initialize(path)
      @path = File.expand_path(path)
    end

    # Unpacks the archive into a folder in +cache+, unless an earlier
    # unpack left it there whole, and returns the folder the game's files
    # are in. Reads the archive through Lota::Filesystem, whose source it
    # must be, as Lota::Boot makes it. Raises Refused, writing nothing, for
    # an archive with an entry it will not unpack.
    #
    # [cache] String path of the cache's folder (Archive.cache_directory).
    # [windows] Whether the files land on Windows, where the names and
    #   path lengths Windows refuses are checked. An archive with a name
    #   Windows cannot hold is refused everywhere, so that a game that plays
    #   on one system plays on every one.
    def unpack(cache, windows: Gem.win_platform?)
      digest = Digest::SHA256.file(@path).hexdigest
      folder = File.join(cache, digest[0, 16].to_s)
      return File.join(folder, "game") if whole?(folder, digest)

      entries = walk("")
      FileUtils.mkdir_p(cache)
      temporary = File.join(cache, ".tmp#{Random.urandom(6).unpack1('H*')}")
      begin
        Dir.mkdir(temporary)
        limit = windows && !long_paths?(temporary)
        check(entries, File.join(folder, "game"), path_limit: limit)
        write(entries, File.join(temporary, "game"))
        File.write(File.join(temporary, RECORD), record(digest, entries, File.join(temporary, "game")))
        settle(temporary, folder, digest)
      ensure
        FileUtils.rm_rf(temporary)
      end
      File.join(folder, "game")
    end

    # Raises Refused for the first of +entries+ that Lota will not unpack
    # into the folder +destination+, naming it, or returns +nil+.
    #
    # [entries] Array of each entry's path in the archive, its folders
    #   separated by "/", and its type, as Lota::Filesystem::Info#type
    #   gives it, or +nil+ for one PhysFS cannot read.
    # [destination] String path of the folder they would land in.
    # [path_limit] Whether Windows' limit on a path's length applies.
    #
    # === Example
    #
    #   archive.check([["main.rb", :file], ["lib.so", :file]], "/tmp/game")
    #   # Lota::Archive::Refused: Cannot play the game in '.../pong.lota': its entry "lib.so" is native code, ...
    def check(entries, destination, path_limit: false)
      seen = {} #: Hash[String, String]
      entries.each do |name, type|
        reason = refusal(name, type) || (path_limit && length_refusal(File.join(destination, name), type))
        unless reason
          key = name.unicode_normalize(:nfc).downcase(:fold)
          other = seen[key]
          reason = "has the same name as #{other.inspect} but for case, which Windows and macOS cannot tell apart" if other
          seen[key] = name
        end
        raise Refused, "Cannot play the game in '#{@path}': its entry #{name.inspect} #{reason}." if reason
      end
      nil
    end

    # Why the entry +name+ of +type+ cannot be unpacked, whatever its
    # length, or +nil+.
    private def refusal(name, type)
      return "is not valid UTF-8, which Windows cannot name" unless name.valid_encoding?

      components = name.split("/", -1)
      return "would land outside the game's folder" if components.any? { |part| ["", ".", ".."].include?(part) }
      return "has a character Windows forbids in a name" if name.match?(FORBIDDEN)
      return "has a name ending in a dot or a space, which Windows drops" if components.any? { |part| part.end_with?(".", " ") }
      return "has a name Windows reserves for a device" if components.any? { |part| part.match?(RESERVED) }
      return "is native code, which a game in one file cannot hold" if type == :file && name.match?(NATIVE)
      return "is a symbolic link, which Lota does not unpack" if type == :symlink

      "cannot be read from the archive" unless %i[file directory].include?(type)
    end

    # Why +path+, of +type+, is too long for Windows where long paths are
    # not enabled, or +nil+, counting its UTF-16 code units, as Windows
    # counts.
    private def length_refusal(path, type)
      length = path.encode(Encoding::UTF_16LE).bytesize / 2
      limit = (type == :directory) ? FOLDER_PATH_LIMIT : FILE_PATH_LIMIT
      return if length <= limit

      "makes a path of #{length} characters, longer than the #{limit} Windows allows where long paths are not enabled"
    end

    # Whether this process can make a path longer than MAX_PATH in
    # +folder+, as it can where Windows has long paths enabled and the
    # program declares it knows them.
    private def long_paths?(folder)
      probe = File.join(folder, "l" * 160, "l" * 160)
      FileUtils.mkdir_p(probe)
      true
    rescue SystemCallError
      false
    ensure
      FileUtils.rm_rf(File.join(folder, "l" * 160))
    end

    # The entries of the archive under +folder+, "" for its top, as
    # [path, type] pairs, each folder before what it holds, read through
    # Lota::Filesystem, which also lists the save directory's files: those
    # are left out. An entry whose name PhysFS cannot open, such as "..",
    # is listed with no type and not looked into.
    private def walk(folder)
      entries = [] #: Array[entry]
      Filesystem.directory_items(folder).sort.each do |name|
        entry = folder.empty? ? name : "#{folder}/#{name}"
        type = Filesystem.info(entry)&.type
        next entries << [entry, nil] if type.nil?
        next unless Filesystem.real_directory(entry).first == Filesystem.source

        entries << [entry, type]
        entries.concat(walk(entry)) if type == :directory
      end
      entries
    end

    # Writes +entries+ into the folder +destination+, reading each file
    # from the archive.
    private def write(entries, destination)
      Dir.mkdir(destination)
      entries.each do |name, type|
        target = File.join(destination, name)
        next Dir.mkdir(target) if type == :directory

        contents, message = Filesystem.read(name)
        raise Refused, "Cannot play the game in '#{@path}': its entry #{name.inspect} cannot be read: #{message}" unless contents

        File.binwrite(target, contents)
      end
    end

    # The record of +entries+, unpacked into +game+ from the archive whose
    # SHA-256 is +digest+: a header with the digest, then a line for each
    # entry, "d" and the path of a folder, or "f", the size, and the path
    # of a file, which no tab or newline can be in, since check refuses
    # control characters.
    private def record(digest, entries, game)
      lines = entries.map do |name, type|
        (type == :directory) ? "d\t#{name}" : "f\t#{File.size(File.join(game, name))}\t#{name}"
      end
      "#{RECORD_HEADER} #{digest}\n#{lines.map { |line| "#{line}\n" }.join}"
    end

    # Whether +folder+ holds a whole unpack of the archive whose SHA-256
    # is +digest+: its record names the digest, and every folder and file
    # the record lists is there, each file the size it was written.
    private def whole?(folder, digest)
      lines = File.readlines(File.join(folder, RECORD), chomp: true)
      return false unless lines.shift == "#{RECORD_HEADER} #{digest}"

      game = File.join(folder, "game")
      lines.all? do |line|
        kind, *fields = line.split("\t", 3)
        path = File.join(game, fields.last.to_s)
        (kind == "d") ? File.directory?(path) : (File.file?(path) && File.size(path) == fields.first.to_i)
      end
    rescue SystemCallError, IOError
      false
    end

    # Renames the whole unpack in +temporary+ to +folder+, replacing a
    # folder there that is not whole, or leaves the one another unpack put
    # there first.
    private def settle(temporary, folder, digest)
      FileUtils.rm_rf(folder) if File.exist?(folder) && !whole?(folder, digest)
      File.rename(temporary, folder)
    rescue SystemCallError
      raise unless whole?(folder, digest)
    end
  end
end
