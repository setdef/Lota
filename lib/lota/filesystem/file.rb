# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Filesystem
    # A file LÖVE's filesystem opened, matching LÖVE's File class
    # (src/modules/filesystem/File.h), which Lota::Filesystem.open_file
    # returns. A File not closed closes when Ruby collects it, as a File
    # LÖVE no longer refers to does.
    #
    # Each method that LÖVE lets fail with +nil+ and a message returns an
    # Array on every path (ADR 001, rule 4): its results, or +nil+ and the
    # message, so <tt>.first</tt> is what Lua's first result is. Modes are
    # Symbols (rule 9): +:r+ to read, +:w+ to write, +:a+ to append, and
    # +:c+ for closed.
    #
    # === Example
    #
    #   file, = Lota::Filesystem.open_file("scores.txt", :w)
    #   file.write("ada 120\n")
    #   file.close
    #   file.open(:r)
    #   file.read # => ["ada 120\n", 8]
    class File
      include Object

      # The engine's File, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a File the engine opened. :nodoc:
      def self.from_native(native)
        file = allocate
        file.instance_variable_set(:@native, native)
        file
      end

      # Opens the file in +mode+, matching File:open
      # (src/modules/filesystem/wrap_File.cpp, w_File_open), and returns an
      # Array of whether it opened, or of +nil+ and LÖVE's message, as when
      # a file to read does not exist (rule 4).
      #
      # [mode] +:r+, +:w+, +:a+, or +:c+.
      #
      # LÖVE pairs open with close, which rule 11 would give a block form;
      # it waits for the maintainer, since an open that fails has no file
      # to give the block. Raises ArgumentError for a mode LÖVE does not
      # know.
      #
      # === Example
      #
      #   file.open(:r) # => [true]
      def open(mode)
        @native.open(EnumName.of(mode))
      end

      # Closes the file, matching File:close
      # (src/modules/filesystem/wrap_File.cpp, w_File_close), and returns
      # whether it was open to close (ADR 001, rule 7).
      #
      # === Example
      #
      #   file.close # => true
      def close
        @native.close
      end

      # Whether the file is open, matching File:isOpen
      # (src/modules/filesystem/wrap_File.cpp, w_File_isOpen).
      #
      # === Example
      #
      #   file.open? # => true
      def open?
        @native.open?
      end

      # The mode the file is open in, matching File:getMode
      # (src/modules/filesystem/wrap_File.cpp, w_File_getMode), as an
      # Array of the Symbol (rule 4), or of +nil+ and LÖVE's message for a
      # mode it has no name for.
      #
      # === Example
      #
      #   file.mode # => [:r]
      def mode
        name, message = @native.mode
        name ? [name.to_sym] : [nil, message.to_s]
      end

      # The file's name, as it was opened, matching File:getFilename
      # (src/modules/filesystem/wrap_File.cpp, w_File_getFilename).
      #
      # === Example
      #
      #   file.filename # => "scores.txt"
      def filename
        @native.filename
      end

      # The file's extension, without its dot, matching File:getExtension
      # (src/modules/filesystem/wrap_File.cpp, w_File_getExtension), or an
      # empty String when it has none.
      #
      # === Example
      #
      #   file.extension # => "txt"
      def extension
        @native.extension
      end

      # The file's size in bytes, matching File:getSize
      # (src/modules/filesystem/wrap_File.cpp, w_File_getSize), as an Array
      # of the Integer, or of +nil+ and LÖVE's message when it cannot tell
      # (rule 4).
      #
      # === Example
      #
      #   file.size # => [8]
      def size
        @native.size
      end

      # Reads from the file, matching File:read
      # (src/modules/filesystem/wrap_File.cpp, w_File_read).
      #
      # [container] +:string+ for a String, or +:data+ for a
      #   Lota::Filesystem::FileData; a String when left out.
      # [size] The most bytes to read; the rest of the file when left out
      #   or negative.
      #
      # Returns an Array (rule 4) of what it read and how many bytes it
      # is, or of +nil+ and LÖVE's message, as for a file not open to
      # read. Raises ArgumentError for a container type LÖVE does not
      # know.
      #
      # === Examples
      #
      #   file.read # => ["ada 120\n", 8]
      #   file.read(3) # => ["ada", 3]
      #   data, size = file.read(:data)
      def read(container = nil, size = nil)
        case container
        when Symbol, String then read_into(EnumName.of(container), size)
        else read_into(nil, container)
        end
      end

      # Reads +size+ bytes into the container type +container+ names. :nodoc:
      private def read_into(container, size)
        @native.read(container, size || -1).map do |value|
          value.is_a?(Native::FileData) ? FileData.from_native(value) : value
        end
      end

      # Writes to the file, matching File:write
      # (src/modules/filesystem/wrap_File.cpp, w_File_write).
      #
      # [data] A String, or any Lota::Data, whose bytes it writes.
      # [size] How many bytes of +data+ to write; all of them when left
      #   out.
      #
      # Returns an Array (rule 4) of whether it wrote them all, or of +nil+
      # and LÖVE's message, as for a file not open to write. LÖVE writes
      # +size+ bytes even past the end of +data+; Lota writes no more than
      # +data+ holds. Raises TypeError for +data+ that is neither.
      #
      # === Example
      #
      #   file.write("ada 120\n") # => [true]
      def write(data, size = nil)
        case data
        when String then @native.write_string(data, size)
        when Lota::Data then @native.write_data(data.native, size)
        else raise TypeError, "wrong argument type #{data.class} (expected String or Lota::Data)"
        end
      end

      # Writes what the file holds in its buffer, matching File:flush
      # (src/modules/filesystem/wrap_File.cpp, w_File_flush), and returns
      # an Array of whether it could, or of +nil+ and LÖVE's message, as
      # for a file not open to write (rule 4).
      #
      # === Example
      #
      #   file.flush # => [true]
      def flush
        @native.flush
      end

      # Whether reading has reached the end of the file, matching
      # File:isEOF (src/modules/filesystem/wrap_File.cpp, w_File_isEOF).
      #
      # === Example
      #
      #   file.eof? # => false
      def eof?
        @native.eof?
      end

      # Where in the file the next read or write is, in bytes from its
      # start, matching File:tell
      # (src/modules/filesystem/wrap_File.cpp, w_File_tell), as an Array
      # of the Integer, or of +nil+ and LÖVE's message (rule 4).
      #
      # === Example
      #
      #   file.tell # => [0]
      def tell
        @native.tell
      end

      # Moves to +position+, in bytes from the file's start, matching
      # File:seek (src/modules/filesystem/wrap_File.cpp, w_File_seek), and
      # returns whether it could. A negative position, or one too large
      # for a Float to hold exactly, is refused with +false+, as in LÖVE.
      #
      # === Example
      #
      #   file.seek(4) # => true
      def seek(position)
        @native.seek(position)
      end

      # Sets how the file buffers what is written to it, matching
      # File:setBuffer (src/modules/filesystem/wrap_File.cpp,
      # w_File_setBuffer), and returns an Array of whether it could, or of
      # +nil+ and LÖVE's message (rules 4 and 7).
      #
      # [mode] +:none+, +:line+, or +:full+.
      # [size] The buffer's size in bytes, which +:none+ ignores.
      #
      # Raises ArgumentError for a buffer mode LÖVE does not know.
      #
      # === Example
      #
      #   file.set_buffer(:full, 10_000) # => [true]
      def set_buffer(mode, size = 0)
        @native.set_buffer(EnumName.of(mode), size)
      end

      # How the file buffers what is written to it and the buffer's size,
      # matching File:getBuffer (src/modules/filesystem/wrap_File.cpp,
      # w_File_getBuffer), as an Array of the mode's Symbol and the
      # Integer size (rule 4), or of +nil+ and LÖVE's message.
      #
      # === Example
      #
      #   file.buffer # => [:full, 10000]
      def buffer
        mode, size = @native.buffer
        (mode.is_a?(String) && size.is_a?(Integer)) ? [mode.to_sym, size] : [nil, size.to_s]
      end

      # The file's lines, each a String without its line ending, as an
      # Enumerator, or each given to the block, matching File:lines
      # (src/modules/filesystem/wrap_File.cpp, w_File_lines), whose
      # iterator becomes an Enumerator (ADR 001, rule 15).
      #
      # A file not open to read is opened to read, and one open to read
      # keeps the position its own reads and seeks leave it at, as in
      # LÖVE. The file closes after its last line, so the lines can be
      # read once; reading them again, or after the file leaves read mode,
      # raises RuntimeError (<tt>"File needs to stay in read mode."</tt>).
      # Raises RuntimeError (<tt>"Could not open file."</tt>) when it
      # cannot open the file to read. With a block, it returns +nil+.
      #
      # === Example
      #
      #   file.lines.to_a # => ["ada 120"]
      def lines(&block)
        reader = Native::Filesystem::Lines.of_file(@native)
        return Filesystem.enumerate_lines(reader) unless block

        Filesystem.enumerate_lines(reader, &block)
      end
    end
  end
end
