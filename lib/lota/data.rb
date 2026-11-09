# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # LÖVE's root type Data, whose methods every one of LÖVE's Data objects
  # answers, whatever its class, translated from Data's methods
  # (src/modules/data/wrap_Data.cpp), and LÖVE's love.data module, whose
  # functions are its class methods.
  #
  # A sound's samples, an image's pixels, and a file's bytes are all
  # memory the engine holds. A game that saves a screenshot's bytes, sends
  # a sound over the network, or reads numbers from a binary file needs
  # those bytes, whatever kind of Data holds them.
  #
  # Every class that holds some, Lota::Sound::SoundData,
  # Lota::Image::ImageData, Lota::Filesystem::FileData,
  # Lota::Data::ByteData, Lota::Data::CompressedData, and
  # Lota::Data::DataView, inherits from this class, as each inherits from
  # Data in LÖVE (src/common/Data.h). Rule 1 of ADR 001 gives love.data the
  # name Lota::Data, and LÖVE's root type keeps its name there too, so it
  # is one class, and inside <tt>module Lota</tt> a bare +Data+ means this
  # class, and Ruby's own is written <tt>::Data</tt>.
  #
  # Its class methods are love.data's: they compress and decompress,
  # encode and decode base64 and hex, hash, and pack numbers and strings
  # into bytes and unpack them, each returning a String or, given the
  # container +:data+, a Data. That Data is an object of this class
  # itself, whose type is <tt>"Data"</tt>, as LÖVE hands it to Lua: it
  # has Data's methods, and none of ByteData's. LÖVE has no function that
  # makes one otherwise, so Lota::Data has no +new+.
  #
  # Data's getPointer and getFFIPointer give Lua the bytes' address, as a
  # raw pointer and as a pointer LuaJIT's FFI reads. Ruby's own FFI is
  # Fiddle, so #pointer and #ffi_pointer give a Fiddle::Pointer to the same
  # address, with the fiddle gem in the game's Gemfile.
  #
  # === Examples
  #
  #   sound = Lota::Sound::SoundData.new("click.ogg")
  #   sound.size              # => 11708
  #   sound.string(0, 4).size # => 4
  #
  #   packed = Lota::Data.compress(:string, :zlib, "helloworld")
  #   Lota::Data.decompress(:string, :zlib, packed) # => "helloworld"
  #   Lota::Data.decompress(:data, :zlib, packed).type # => "Data"
  class Data < Object
    # Wraps a plain Data the engine made, as love.data's functions return
    # for the container +:data+.
    private_class_method def self.from_native(native)
      data = allocate
      data.instance_variable_set(:@native, native)
      data
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # +source+ compressed, matching love.data.compress
    # (src/modules/data/wrap_DataModule.cpp:116-149).
    #
    # [container] Symbol +:string+ for a String of the compressed bytes,
    #   or +:data+ for a Lota::Data::CompressedData.
    # [format] Symbol: +:lz4+, +:zlib+, +:gzip+, or +:deflate+.
    # [source] String or Lota::Data of the bytes to compress.
    # [level] Integer from 0, the fastest, to 9, the smallest; the
    #   format's default when -1 or +nil+.
    #
    # Raises ArgumentError for an unknown container or format, TypeError
    # for a +source+ that is neither, and RuntimeError when the data
    # module is not open.
    #
    # === Examples
    #
    #   Lota::Data.compress(:string, :zlib, "helloworld")
    #   Lota::Data.compress(:data, :lz4, save_bytes, 9).format # => :lz4
    def self.compress(container, format, source, level = nil)
      native = Native::Data.compress(EnumName.of(format), level || -1, EnumName.of(container), source_of(source))
      native.is_a?(String) ? native : CompressedData.__send__(:from_native, native)
    end

    # The bytes compressed in +compressed+, matching love.data.decompress
    # (src/modules/data/wrap_DataModule.cpp:151-201).
    #
    # [container] Symbol +:string+ for a String, or +:data+ for a
    #   Lota::Data.
    # [compressed] Lota::Data::CompressedData, which knows its format; or
    #   the Symbol format, as Lota::Data.compress takes it, then the
    #   compressed bytes as a String or a Lota::Data.
    #
    # Raises ArgumentError for an unknown container or format, TypeError
    # for bytes that are neither, and RuntimeError, with LÖVE's message,
    # for bytes that are not compressed in that format.
    #
    # === Examples
    #
    #   Lota::Data.decompress(:string, compressed_data)
    #   Lota::Data.decompress(:string, :zlib, packed) # => "helloworld"
    def self.decompress(container, compressed, source = nil)
      native = if compressed.is_a?(CompressedData)
        Native::Data.decompress_compressed_data(EnumName.of(container), compressed.__send__(:native))
      else
        Native::Data.decompress(EnumName.of(compressed), source_of(source), EnumName.of(container))
      end
      result_of(native)
    end

    # +source+ encoded as text, matching love.data.encode
    # (src/modules/data/wrap_DataModule.cpp:203-252).
    #
    # [container] Symbol +:string+ for a String, or +:data+ for a
    #   Lota::Data.
    # [format] Symbol +:base64+ or +:hex+.
    # [source] String or Lota::Data of the bytes to encode.
    # [line_length] Integer: base64 is broken into lines this long, or
    #   not at all when 0 or +nil+.
    #
    # Raises ArgumentError for an unknown container or format.
    #
    # === Example
    #
    #   Lota::Data.encode(:string, :hex, "hi") # => "6869"
    def self.encode(container, format, source, line_length = nil)
      result_of(Native::Data.encode(EnumName.of(format), line_length || 0, EnumName.of(container), source_of(source)))
    end

    # The bytes +source+ encodes, matching love.data.decode
    # (src/modules/data/wrap_DataModule.cpp:254-301), in a +format+
    # Lota::Data.encode takes.
    #
    # Raises ArgumentError for an unknown container or format.
    #
    # === Example
    #
    #   Lota::Data.decode(:string, :base64, "aGk=") # => "hi"
    def self.decode(container, format, source)
      result_of(Native::Data.decode(EnumName.of(format), source_of(source), EnumName.of(container)))
    end

    # The digest of +source+ by the hash function +function+, matching
    # love.data.hash (src/modules/data/wrap_DataModule.cpp:303-352); or,
    # given no arguments, Ruby's own Object#hash of this class, since no
    # call of LÖVE's takes none.
    #
    # [container] Symbol +:string+ for a String of the digest's bytes, or
    #   +:data+ for a Lota::Data.
    # [function] Symbol +:md5+, +:sha1+, +:sha224+, +:sha256+, +:sha384+,
    #   or +:sha512+.
    # [source] String or Lota::Data of the bytes to hash.
    #
    # LÖVE's deprecated form, with no container, the function first, still
    # works, returns a String, and prints LÖVE's notice on its first use.
    # Raises ArgumentError for an unknown container or function, and
    # TypeError for a +source+ that is neither a String nor a Data.
    #
    # === Examples
    #
    #   Lota::Data.hash(:string, :md5, "helloworld").unpack1("H*") # => "fc5e038d38a57032085441e7fe7010b0"
    #   Lota::Data.hash(:data, :sha256, save_bytes).size            # => 32
    def self.hash(*arguments)
      return super() if arguments.empty?

      container, function, source = arguments
      if Native::Data.hash_function?(EnumName.of(container))
        Deprecation.mark("Lota::Data.hash", :functionvariant, :replaced, "variant with container return type parameter",
          where: Deprecation.where(caller_locations(1, 1)))
        container, function, source = :string, container, function
      end
      source = source.__send__(:native) if source.is_a?(Data)
      result_of(Native::Data.hash_bytes(EnumName.of(container), source, EnumName.of(function)))
    end

    # +values+ packed into bytes by +format+, matching love.data.pack
    # (src/modules/data/wrap_DataModule.cpp:354-397), whose formats are
    # Lua 5.3's string.pack's: <tt>"<I4"</tt> packs an unsigned 32-bit
    # integer little-endian, and <tt>"s1"</tt> a string after its length
    # in a byte.
    #
    # [container] Symbol +:string+ for a String, or +:data+ for a
    #   Lota::Data; or a Lota::Data::ByteData to pack into, followed by the
    #   Integer byte to pack from.
    # [format] String of the format.
    # [values] The numbers and Strings it packs, one for each option.
    #
    # Packing into a ByteData returns it. Raises ArgumentError for a value
    # that does not fit its option, RuntimeError for an option the format
    # does not have, and RuntimeError, with LÖVE's message, for bytes that
    # do not fit in the ByteData.
    #
    # === Examples
    #
    #   Lota::Data.pack(:string, ">I2", 513) # => "\x02\x01"
    #   Lota::Data.pack(header, 4, "<I4", 1024)
    def self.pack(container, *arguments)
      if container.is_a?(ByteData)
        offset, format, *values = arguments
        pack_into(container, offset, format, values)
      else
        name = EnumName.of(container)
        Native::Data.check_container(name)
        format, *values = arguments
        packed = Packing.pack(format, values)
        (name == "data") ? from_native(Native::Data.new_data_of_string(packed)) : packed
      end
    end

    # The values +format+ packed in +source+, matching love.data.unpack
    # (src/modules/data/wrap_DataModule.cpp:399-417), then the position of
    # the byte after them, counted from 1, all in one Array (ADR 001, rule
    # 4).
    #
    # [format] String format, as Lota::Data.pack takes it.
    # [source] String or Lota::Data of the bytes.
    # [position] Integer byte to start at, counted from 1, and back from
    #   the end when negative.
    #
    # Raises ArgumentError, with Lua's message, for bytes too few for the
    # format.
    #
    # === Example
    #
    #   a, b, next_position = Lota::Data.unpack(">I2I2", "\x00\x01\x00\x02") # => [1, 2, 5]
    def self.unpack(format, source, position = nil)
      bytes = case source
      when Data then source.size.zero? ? "".b : source.string.b
      when String then source.b
      else raise TypeError, "wrong argument type #{source.class} (expected String or Lota::Data)"
      end
      Packing.unpack(format, bytes, position)
    end

    # How many bytes +format+ packs, as an Integer, matching
    # love.data.getPackedSize, which is Lua 5.3's string.packsize
    # (src/modules/data/wrap_DataModule.cpp:431,
    # src/libraries/lua53/lstrlib.c:482-504).
    #
    # Raises ArgumentError for a format that packs a String of a length of
    # its own.
    #
    # === Example
    #
    #   Lota::Data.packed_size(">I2B") # => 3
    def self.packed_size(format)
      Packing.packed_size(format)
    end

    # w_pack with a ByteData (src/modules/data/wrap_DataModule.cpp:356-376):
    # the packed bytes written into +data+ from byte +offset+, which LÖVE
    # reads as a number and casts to a size_t, as the processor converts
    # a negative one, to 0.
    private_class_method def self.pack_into(data, offset, format, values)
      start = case offset
      when Integer then offset.negative? ? 0 : offset
      when Float then (offset.nan? || offset.negative?) ? 0 : offset.truncate
      else raise TypeError, "wrong argument type #{offset.class} (expected Float or Integer)"
      end
      packed = Packing.pack(format, values)
      if start + packed.bytesize > data.size
        raise "The given byte offset and pack format parameters do not fit within the ByteData's size."
      end

      data.__send__(:native).set_string(packed, start)
      data
    end

    # The engine's object for a Lota::Data, or +source+ itself.
    private_class_method def self.source_of(source)
      case source
      when Data then source.__send__(:native)
      else source
      end
    end

    # A String, or the Ruby wrapper of the Data the engine made.
    private_class_method def self.result_of(native)
      native.is_a?(String) ? native : from_native(native)
    end

    # SPDX-SnippetEnd

    # How many bytes the Data holds, as an Integer, matching Data:getSize
    # (src/modules/data/wrap_Data.cpp, w_Data_getSize).
    #
    # === Example
    #
    #   sound.size # => 11708
    def size
      native.size
    end

    # The address of the Data's bytes, as a Fiddle::Pointer of no size,
    # matching Data:getPointer (src/modules/data/wrap_Data.cpp,
    # w_Data_getPointer), which gives Lua the address as a raw pointer
    # (ADR 001, section 7).
    #
    # The pointer is valid only while the Data lives, as in LÖVE: once the
    # Data is released or garbage collected, reading or writing through it
    # reads or writes freed memory. Keep the Data while the pointer is in
    # use.
    #
    # Needs the fiddle gem, which Lota does not depend on: add
    # <tt>gem "fiddle"</tt> to the game's Gemfile. Raises LoadError, saying
    # so, when Fiddle will not load (Lota::Pointer).
    #
    # === Example
    #
    #   data = Lota::Data::ByteData.new("helloworld")
    #   data.pointer[4, 1] # => "o"
    def pointer
      Pointer.at(native.pointer)
    end

    # The address of the Data's bytes, as a Fiddle::Pointer whose size is
    # the Data's, matching Data:getFFIPointer
    # (src/modules/data/wrap_Data.lua), which gives a game running on
    # LuaJIT a pointer its FFI reads. Lota's Ruby has Fiddle where LuaJIT
    # has its FFI, so the pointer is Fiddle's, to the address #pointer
    # gives, and Fiddle::Pointer#size is #size.
    #
    # The pointer is valid only while the Data lives, as #pointer is.
    #
    # Needs the fiddle gem, which Lota does not depend on: add
    # <tt>gem "fiddle"</tt> to the game's Gemfile. Raises LoadError, saying
    # so, when Fiddle will not load (Lota::Pointer).
    #
    # === Example
    #
    #   data = Lota::Data::ByteData.new("helloworld")
    #   data.ffi_pointer.to_str # => "helloworld"
    def ffi_pointer
      Pointer.at(native.pointer, size)
    end

    # The Data's bytes, as a String, matching Data:getString
    # (src/modules/data/wrap_Data.cpp, w_Data_getString).
    #
    # [offset] Integer byte to start at.
    # [size] Integer bytes to take; every byte from +offset+ on when +nil+
    #   or left out.
    #
    # The String is in Ruby's default external encoding, as File.read's
    # is, holding the bytes as they are. Raises RuntimeError, with LÖVE's
    # message, for a +size+ below 1, or bytes outside the Data.
    #
    # === Example
    #
    #   sound.string(0, 4).bytesize # => 4
    def string(offset = 0, size = nil)
      native.string(offset, size)
    end

    # Calls the block with +arguments+ while no other thread can use the
    # Data, and returns what the block returns, matching
    # Data:performAtomic (src/modules/data/wrap_Data.cpp,
    # w_Data_performAtomic), whose function becomes the block (ADR 001,
    # rule 12).
    #
    # [arguments] Anything, passed on to the block.
    #
    # The Data's lock is let go when the block returns or raises.
    #
    # === Example
    #
    #   sound.perform_atomic(0) { |i| sound.sample(i) }
    def perform_atomic(*arguments, &block)
      native.perform_atomic([block, *arguments])
    end

    # +count+ 32-bit floats from byte +offset+, as an Array of Floats,
    # matching Data:getFloat (src/modules/data/wrap_Data.cpp,
    # w_Data_getFloat), which returns each as a value of its own.
    #
    # [offset] Integer byte the first starts at.
    # [count] Integer how many, at least 1.
    #
    # Raises RuntimeError, with LÖVE's message, for a +count+ below 1, or
    # values outside the Data.
    #
    # === Example
    #
    #   data.float(0) # => [1.5]
    def float(offset, count = 1)
      native.float(offset, count)
    end

    # +count+ 64-bit floats from byte +offset+, as an Array of Floats,
    # matching Data:getDouble (src/modules/data/wrap_Data.cpp,
    # w_Data_getDouble), as #float reads them.
    #
    # === Example
    #
    #   data.double(0, 2) # => [1.5, -2.0]
    def double(offset, count = 1)
      native.double(offset, count)
    end

    # +count+ signed 8-bit integers from byte +offset+, as an Array of
    # Integers, matching Data:getInt8 (src/modules/data/wrap_Data.cpp,
    # w_Data_getInt8), as #float reads them.
    #
    # === Example
    #
    #   data.int8(0, 2) # => [-1, 7]
    def int8(offset, count = 1)
      native.int8(offset, count)
    end

    # +count+ signed 16-bit integers from byte +offset+, in the machine's
    # byte order, as an Array of Integers, matching Data:getInt16
    # (src/modules/data/wrap_Data.cpp, w_Data_getInt16), as #float reads
    # them.
    #
    # === Example
    #
    #   sound.int16(0) # => [-7]
    def int16(offset, count = 1)
      native.int16(offset, count)
    end

    # +count+ signed 32-bit integers from byte +offset+, in the machine's
    # byte order, as an Array of Integers, matching Data:getInt32
    # (src/modules/data/wrap_Data.cpp, w_Data_getInt32), as #float reads
    # them.
    #
    # === Example
    #
    #   data.int32(4) # => [65536]
    def int32(offset, count = 1)
      native.int32(offset, count)
    end

    # +count+ unsigned 8-bit integers from byte +offset+, as an Array of
    # Integers, matching Data:getUInt8 (src/modules/data/wrap_Data.cpp,
    # w_Data_getUInt8), as #float reads them. Rule 13 of ADR 001 spells
    # LÖVE's UInt as C's uint, one word.
    #
    # === Example
    #
    #   data.uint8(0, 2) # => [255, 7]
    def uint8(offset, count = 1)
      native.uint8(offset, count)
    end

    # +count+ unsigned 16-bit integers from byte +offset+, in the
    # machine's byte order, as an Array of Integers, matching
    # Data:getUInt16 (src/modules/data/wrap_Data.cpp, w_Data_getUInt16),
    # as #float reads them.
    #
    # === Example
    #
    #   data.uint16(2) # => [65535]
    def uint16(offset, count = 1)
      native.uint16(offset, count)
    end

    # +count+ unsigned 32-bit integers from byte +offset+, in the
    # machine's byte order, as an Array of Integers, matching
    # Data:getUInt32 (src/modules/data/wrap_Data.cpp, w_Data_getUInt32),
    # as #float reads them.
    #
    # === Example
    #
    #   data.uint32(4) # => [4294967295]
    def uint32(offset, count = 1)
      native.uint32(offset, count)
    end
  end
end

require_relative "pointer"
require_relative "data/packing"
require_relative "data/byte_data"
require_relative "data/compressed_data"
require_relative "data/data_view"
