# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  class Data
    # Bytes in the engine's memory that a game can write, matching LÖVE's
    # ByteData class (src/modules/data/ByteData.h).
    #
    # A save file, a network packet, or a buffer of numbers a shader
    # reads is bytes, and most of LÖVE's other Data cannot be written
    # once it is made. A ByteData holds bytes that #string= and the
    # writers of numbers (#float=, #int16=, and the rest) change in place,
    # and that the readers it includes from Lota::Data read back.
    #
    # === Example
    #
    #   data = Lota::Data::ByteData.new(8)
    #   data.uint32 = 0, 7, 9
    #   data.uint32(0, 2) # => [7, 9]
    class ByteData < Data
      # Wraps a ByteData the engine made, such as one
      # Lota::Data.decompress returns. :nodoc:
      private_class_method def self.from_native(native)
        data = allocate
        data.instance_variable_set(:@native, native)
        data.freeze
      end

      # Makes a ByteData, matching love.data.newByteData
      # (src/modules/data/wrap_DataModule.cpp:73-114).
      #
      # [source] Integer size, for that many bytes, each 0; a String, for
      #   a copy of its bytes; or a Lota::Data, for a copy of some of its
      #   bytes.
      # [offset] Integer byte of a Data to start the copy at, 0 when
      #   +nil+.
      # [size] Integer bytes of a Data to copy, every byte from +offset+
      #   on when +nil+.
      #
      # Raises RuntimeError, with LÖVE's message, for a size below 1, or
      # bytes outside the Data, and when the data module is not open.
      #
      # === Examples
      #
      #   Lota::Data::ByteData.new(16)
      #   Lota::Data::ByteData.new("helloworld")
      #   Lota::Data::ByteData.new(file_data, 4, 2)
      def self.new(source, offset = nil, size = nil)
        native = case source
        when Data then Native::Data.new_byte_data_of_data(source.__send__(:native), offset, size)
        when String then Native::Data.new_byte_data_of_string(source)
        else Native::Data.new_byte_data_of_size(source)
        end
        from_native(native)
      end

      # Makes this ByteData, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching ByteData:clone
      # (src/modules/data/wrap_ByteData.cpp:37-45): a new ByteData with a
      # copy of the bytes (doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   data.clone.string # => "helloworld"
      def initialize_copy(source)
        super
        @native = source.native.clone
        freeze
      end

      # Copies a String's bytes into the ByteData at a byte offset,
      # matching ByteData:setString
      # (src/modules/data/wrap_ByteData.cpp:47-64), which takes them as
      # one Array (rule 6 of doc/contributors/design/translation.md).
      #
      # [string_and_offset] The String, or an Array of it and the Integer
      #   byte to start at, 0 when left out.
      #
      # Only as many bytes as the ByteData holds are copied. Raises
      # RuntimeError, with LÖVE's message, when they do not fit from the
      # offset.
      #
      # === Examples
      #
      #   data.string = "love!", 5
      #   data.string = "hello"
      def string=(string_and_offset)
        string, offset = string_and_offset.is_a?(Array) ? string_and_offset : [string_and_offset, 0]
        @native.set_string(string, offset)
      end

      # Writes 32-bit floats from a byte offset, matching
      # ByteData:setFloat (src/modules/data/wrap_ByteData.cpp:66-101),
      # which takes the offset and the values as one Array (rule 6 of
      # doc/contributors/design/translation.md).
      #
      # [offset_and_values] An Array of the Integer byte offset, then each
      #   Float or Integer value, or an Array of them, as LÖVE takes a
      #   table.
      #
      # Raises RuntimeError, with LÖVE's message, for values that do not
      # fit from the offset, and TypeError for a value that is not a
      # number, or none.
      #
      # === Examples
      #
      #   data.float = 0, 1.5, -2.0
      #   data.float = 0, [1.5, -2.0]
      def float=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_float(offset, values)
      end

      # Writes 64-bit floats from a byte offset, matching
      # ByteData:setDouble (src/modules/data/wrap_ByteData.cpp:103-106),
      # as #float= writes.
      #
      # === Example
      #
      #   data.double = 0, 1.5
      def double=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_double(offset, values)
      end

      # Writes signed 8-bit integers from a byte offset, matching
      # ByteData:setInt8 (src/modules/data/wrap_ByteData.cpp:108-111), as
      # #float= writes. LÖVE casts each number to the type in C, which
      # keeps the low bits of the 32-bit integer the number truncates to.
      #
      # === Example
      #
      #   data.int8 = 0, -1, 7
      def int8=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_int8(offset, values)
      end

      # Writes unsigned 8-bit integers from a byte offset, matching
      # ByteData:setUInt8 (src/modules/data/wrap_ByteData.cpp:113-116), as
      # #int8= writes. Rule 36 of doc/contributors/design/translation.md spells
      # LÖVE's UInt as C's uint, one word.
      #
      # === Example
      #
      #   data.uint8 = 0, 255, 7
      def uint8=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_uint8(offset, values)
      end

      # Writes signed 16-bit integers, in the machine's byte order, from a
      # byte offset, matching ByteData:setInt16
      # (src/modules/data/wrap_ByteData.cpp:118-121), as #int8= writes.
      #
      # === Example
      #
      #   data.int16 = 0, -7
      def int16=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_int16(offset, values)
      end

      # Writes unsigned 16-bit integers, in the machine's byte order, from
      # a byte offset, matching ByteData:setUInt16
      # (src/modules/data/wrap_ByteData.cpp:123-126), as #int8= writes.
      #
      # === Example
      #
      #   data.uint16 = 2, 65535
      def uint16=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_uint16(offset, values)
      end

      # Writes signed 32-bit integers, in the machine's byte order, from a
      # byte offset, matching ByteData:setInt32
      # (src/modules/data/wrap_ByteData.cpp:128-131), as #int8= writes.
      #
      # === Example
      #
      #   data.int32 = 4, 65536
      def int32=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_int32(offset, values)
      end

      # Writes unsigned 32-bit integers, in the machine's byte order, from
      # a byte offset, matching ByteData:setUInt32
      # (src/modules/data/wrap_ByteData.cpp:133-136). LÖVE's C cast of a
      # number to an unsigned 32-bit integer is the processor's, which
      # makes a negative number 0 and a number too large the largest.
      #
      # === Example
      #
      #   data.uint32 = 4, 4294967295
      def uint32=(offset_and_values)
        offset, values = ByteData.__send__(:offset_and_values, offset_and_values)
        @native.set_uint32(offset, values)
      end

      # The offset and the values a writer of numbers is given, as LÖVE
      # reads them: the values are a table when the first is one, and
      # otherwise every argument after the offset. :nodoc:
      private_class_method def self.offset_and_values(arguments)
        offset, *rest = arguments
        first = rest.first
        [offset, first.is_a?(Array) ? first : rest] #: [Float | Integer, Array[Float | Integer]]
      end
    end
  end
end
