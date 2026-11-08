# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Data's functions and its ByteData, CompressedData, and DataView,
# beyond what Lövetest's tests for them check (test/lovetest/tests/
# data.rb): how they read their arguments and what they raise, as LÖVE's
# wrap files have them (vendor/love/src/modules/data), and Lua 5.3's
# string.pack, which love.data.pack calls (src/libraries/lua53/lstrlib.c).
class DataModuleFunctionsTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # w_newByteData's three forms (wrap_DataModule.cpp:73-114).
  def test_byte_data_is_made_from_a_size_a_string_or_a_data
    zeros = Lota::Data::ByteData.new(4)
    copy = Lota::Data::ByteData.new(Lota::Data::ByteData.new("helloworld"), 5)
    part = Lota::Data::ByteData.new(Lota::Data::ByteData.new("helloworld"), 2, 3)

    assert_equal "\0\0\0\0", zeros.string
    assert_equal "world", copy.string
    assert_equal "llo", part.string
    assert_equal "ByteData", part.object_type
    assert part.type_of?("Data")
    assert_kind_of Lota::Data, part
    error = assert_raises(RuntimeError) { Lota::Data::ByteData.new(0) }
    assert_equal "Data size must be a positive number.", error.message
    error = assert_raises(RuntimeError) { Lota::Data::ByteData.new(zeros, 2, 3) }
    assert_equal "Offset and size arguments must fit within the given Data's size.", error.message
  end

  # setString copies what fits (wrap_ByteData.cpp:47-64), and a clone is
  # a copy of its own.
  def test_string_writes_bytes_in_place
    data = Lota::Data::ByteData.new("helloworld")
    copy = data.clone
    data.string = "J"

    assert_equal "Jelloworld", data.string
    assert_equal "helloworld", copy.string
    error = assert_raises(RuntimeError) { data.string = "abc", 8 }
    assert_equal "The given string offset and size don't fit within the Data's size.", error.message
  end

  # w_ByteData_setT writes each value as its C type, from the arguments
  # or a table (wrap_ByteData.cpp:66-96), which Data's getters read back.
  def test_numbers_are_written_as_their_c_type
    data = Lota::Data::ByteData.new(16)
    data.float = 0, 1.5, -2.0
    data.int16 = 8, [-300, 7]
    data.uint8 = 12, 255
    data.int8 = 13, -1

    assert_equal [1.5, -2.0], data.float(0, 2)
    assert_equal [-300, 7], data.int16(8, 2)
    assert_equal [255, -1], [data.uint8(12).first, data.int8(13).first]
    data.double = 0, 0.25
    data.uint32 = 8, 4_294_967_295
    data.int32 = 12, -5

    assert_equal [0.25], data.double(0)
    assert_equal [4_294_967_295, -5], [data.uint32(8).first, data.int32(12).first]
    data.uint16 = 0, 65_535
    assert_equal [65_535], data.uint16(0)
    error = assert_raises(RuntimeError) { data.float = 12, 1, 2 }
    assert_equal "The given offset and value parameters don't fit within the Data's size.", error.message
    assert_raises(TypeError) { data.float = [0] }
  end

  # A DataView shares the bytes of the Data it views (DataView.cpp:32-43).
  def test_a_data_view_shares_its_datas_bytes
    data = Lota::Data::ByteData.new("helloworld")
    view = Lota::Data::DataView.new(data, 5)
    data.string = "W", 5

    assert_equal "World", view.string
    assert_equal "World", view.clone.string
    assert_equal "DataView", view.object_type
    error = assert_raises(RuntimeError) { Lota::Data::DataView.new(data, -1) }
    assert_equal "DataView offset and size must not be negative.", error.message
    error = assert_raises(RuntimeError) { Lota::Data::DataView.new(data, 4, 7) }
    assert_equal "Offset and size of Data View must fit within the original Data's size.", error.message
    assert_raises(TypeError) { Lota::Data::DataView.new("helloworld", 0) }
  end

  def test_compressed_data_keeps_its_format
    compressed = Lota::Data.compress(:data, :gzip, Lota::Data::ByteData.new("helloworld" * 10), 9)

    assert_equal :gzip, compressed.format
    assert_equal :gzip, compressed.clone.format
    assert_equal "CompressedData", compressed.object_type
    assert_equal "helloworld" * 10, Lota::Data.decompress(:string, compressed)
    assert_equal "helloworld" * 10, Lota::Data.decompress(:string, :gzip, compressed)
    assert_equal compressed.string, Lota::Data.compress(:string, :gzip, "helloworld" * 10, 9)
  end

  # A CompressedData knows its decompressed size, which w_decompress
  # passes on (wrap_DataModule.cpp:157-162), so LZ4 decompresses it with
  # LZ4_decompress_fast, and bytes given with their format, whose size it
  # does not know, with LZ4_decompress_safe (Compressor.cpp:132-153). Both
  # read what LZ4_compress_default writes and, from level 9,
  # LZ4_compress_HC (lines 74-78): after the size, as a little-endian
  # uint32, the bytes LÖVE's own LZ4 1.8.0, unpatched, writes for this
  # input at either level. Lota's LZ4 patch must not change them
  # (ext/lota/engine/lz4.patch).
  def test_lz4_compressed_data_decompresses_with_its_size_or_without
    source = "helloworld" * 10
    bytes = ["64000000af68656c6c6f776f726c640a004250776f726c64"].pack("H*")

    [-1, 9].each do |level|
      compressed = Lota::Data.compress(:data, :lz4, source, level)

      assert_equal :lz4, compressed.format
      assert_equal bytes, compressed.string.b, "level #{level}"
      assert_equal source, Lota::Data.decompress(:string, compressed), "level #{level}"
      assert_equal source, Lota::Data.decompress(:string, :lz4, compressed.string), "level #{level}"
    end
  end

  # Each function checks its container type and format by name, as
  # luax_enumerror reports them (wrap_DataModule.cpp:46-53 and 116-301).
  def test_names_are_checked
    error = assert_raises(ArgumentError) { Lota::Data.compress(:table, :zlib, "x") }
    assert_match(/\AInvalid container type 'table', expected one of: /, error.message)
    error = assert_raises(ArgumentError) { Lota::Data.compress(:string, :zip, "x") }
    assert_match(/\AInvalid compressed data format 'zip', expected one of: /, error.message)
    error = assert_raises(ArgumentError) { Lota::Data.encode(:string, :base32, "x") }
    assert_match(/\AInvalid encode format 'base32', expected one of: /, error.message)
    error = assert_raises(ArgumentError) { Lota::Data.decode(:string, :base32, "x") }
    assert_match(/\AInvalid decode format 'base32', expected one of: /, error.message)
    assert_raises(ArgumentError) { Lota::Data.pack(:table, "b", 1) }
    assert_raises(TypeError) { Lota::Data.encode(:string, :hex, 12) }
  end

  def test_encode_breaks_base64_into_lines_and_takes_any_data
    assert_includes Lota::Data.encode(:string, :base64, "hellohello", 4), "\n"
    refute_includes Lota::Data.encode(:string, :base64, "hellohello"), "\n"
    assert_equal "aGVsbG8=", Lota::Data.encode(:string, :base64, "hello")
    assert_equal "68656c6c6f", Lota::Data.encode(:string, :hex, Lota::Data::ByteData.new("hello"))
    assert_equal "hello", Lota::Data.decode(:data, :hex, "68656c6c6f").string
  end

  # Lua 5.3's string.pack: byte order, sizes, alignment, and strings
  # (lstrlib.c:290-479).
  def test_pack_lays_out_bytes_as_lua_does
    assert_equal "\x02\x01".b, Lota::Data.pack(:string, ">I2", 513)
    assert_equal "\x01\x02".b, Lota::Data.pack(:string, "<I2", 513)
    assert_equal "\xFF\xFF\xFF".b, Lota::Data.pack(:string, "<i3", -1)
    assert_equal "\x01\0\0\0\x02\0\0\0".b, Lota::Data.pack(:string, "<!4 b i4", 1, 2)
    assert_equal "\x03abc".b, Lota::Data.pack(:string, "s1", "abc")
    assert_equal "ab\0c\0".b, Lota::Data.pack(:string, "c3z", "ab", "c")
    assert_equal [1.5].pack("G"), Lota::Data.pack(:string, ">d", 1.5)
    assert_equal "\0\0\0\0\0".b, Lota::Data.pack(:string, "<i4x", 0)
  end

  def test_pack_refuses_what_does_not_fit
    error = assert_raises(ArgumentError) { Lota::Data.pack(:string, "b", 128) }
    assert_equal "integer overflow", error.message
    error = assert_raises(ArgumentError) { Lota::Data.pack(:string, "B", -1) }
    assert_equal "unsigned overflow", error.message
    error = assert_raises(ArgumentError) { Lota::Data.pack(:string, "c2", "abc") }
    assert_equal "string longer than given size", error.message
    error = assert_raises(ArgumentError) { Lota::Data.pack(:string, "z", "a\0b") }
    assert_equal "string contains zeros", error.message
    error = assert_raises(RuntimeError) { Lota::Data.pack(:string, "q", 1) }
    assert_equal "invalid format option 'q'", error.message
    error = assert_raises(RuntimeError) { Lota::Data.pack(:string, "i17", 1) }
    assert_equal "integral size (17) out of limits [1,16]", error.message
    assert_raises(TypeError) { Lota::Data.pack(:string, "b") }
  end

  # w_pack with a ByteData writes into it at an offset and returns it
  # (wrap_DataModule.cpp:356-376).
  def test_pack_writes_into_byte_data
    data = Lota::Data::ByteData.new(6)

    assert_same data, Lota::Data.pack(data, 2, ">I2", 513)
    assert_equal "\0\0\x02\x01\0\0".b, data.string.b
    error = assert_raises(RuntimeError) { Lota::Data.pack(data, 5, ">I2", 1) }
    assert_equal "The given byte offset and pack format parameters do not fit within the ByteData's size.", error.message
    assert_instance_of Lota::Data, Lota::Data.pack(:data, "b", 1)
  end

  # string.unpack returns the values and the position after them, starts
  # where it is told, and counts back from the end (lstrlib.c:541-599).
  def test_unpack_returns_the_next_position
    bytes = Lota::Data.pack(:string, ">I2s1d", 7, "hi", 0.5)

    assert_equal [7, "hi", 0.5, 14], Lota::Data.unpack(">I2s1d", bytes)
    assert_equal [2, 3], Lota::Data.unpack("B", "\x01\x02\x03", 2)
    assert_equal [3, 4], Lota::Data.unpack("B", "\x01\x02\x03", -1)
    assert_equal [-1, 2], Lota::Data.unpack("b", "\xFF".b)
    assert_equal ["ab", 4], Lota::Data.unpack("z", "ab\0")
    assert_equal [0x0201, 3], Lota::Data.unpack("<I2", Lota::Data::ByteData.new("\x01\x02"))
    error = assert_raises(ArgumentError) { Lota::Data.unpack(">I4", "\x01") }
    assert_equal "data string too short", error.message
    error = assert_raises(ArgumentError) { Lota::Data.unpack("B", "\x01", 5) }
    assert_equal "initial position out of string", error.message
  end

  # Given the container "data", decompress, encode, decode, hash, and pack
  # push what they make as LÖVE's root type Data, not as the ByteData it
  # is in C++ (wrap_DataModule.cpp:191, 238, 287, 345, 374, and 390), so
  # Lua sees Data's type and methods, and none of ByteData's.
  def test_the_data_container_holds_a_plain_data
    packed = Lota::Data.compress(:string, :zlib, "helloworld")
    plain = {
      decompress: Lota::Data.decompress(:data, :zlib, packed),
      compressed_data: Lota::Data.decompress(:data, Lota::Data.compress(:data, :zlib, "helloworld")),
      encode: Lota::Data.encode(:data, :hex, "hi"),
      decode: Lota::Data.decode(:data, :hex, "6869"),
      hash: Lota::Data.hash(:data, :md5, "hi"),
      pack: Lota::Data.pack(:data, ">I2", 513),
    }

    plain.each do |from, data|
      assert_instance_of Lota::Data, data, from
      assert_equal "Data", data.object_type, from
      assert data.type_of?(:Data), from
      assert data.type_of?(:Object), from
      refute data.type_of?(:ByteData), from
      refute_respond_to data, :string=, from
      refute_respond_to data, :uint8=, from
    end
    assert_equal "helloworld", plain.fetch(:decompress).string
    assert_equal "helloworld", plain.fetch(:compressed_data).string
    assert_equal "6869", plain.fetch(:encode).string
    assert_equal "hi", plain.fetch(:decode).string
    assert_equal [2, 1], plain.fetch(:pack).uint8(0, 2)
    assert_equal 16, plain.fetch(:hash).size
  end

  # love.data.hash (wrap_DataModule.cpp:303-352), with every function it
  # has, of a String or a Data, as a String or a Data.
  def test_hash_digests_with_loves_functions
    digests = {
      md5: "fc5e038d38a57032085441e7fe7010b0",
      sha1: "6adfb183a4a2c94a2f92dab5ade762a47889a5a1",
      sha256: "936a185caaa266bb9cbe981e9e05cb78cd732b0b3280eb944412bb6f8f8f07af",
    }

    digests.each do |function, hex|
      assert_equal hex, Lota::Data.hash(:string, function, "helloworld").unpack1("H*")
      assert_equal hex, Lota::Data.hash("data", function.to_s, Lota::Data::ByteData.new("helloworld")).string.unpack1("H*")
    end
    error = assert_raises(ArgumentError) { Lota::Data.hash(:string, :md4, "helloworld") }
    assert_match(/\AInvalid hash function 'md4', expected one of: /, error.message)
    error = assert_raises(ArgumentError) { Lota::Data.hash(:table, :md5, "helloworld") }
    assert_match(/\AInvalid container type 'table', expected one of: /, error.message)
    assert_raises(TypeError) { Lota::Data.hash(:string, :md5, nil) }
  end

  # No call of LÖVE's is love.data.hash with no arguments, so
  # Lota::Data.hash with none is Ruby's own Object#hash, as a Hash key
  # asks it.
  def test_hash_with_no_arguments_is_rubys_own
    assert_equal ::Object.instance_method(:hash).bind_call(Lota::Data), Lota::Data.hash
    assert_equal :data, { Lota::Data => :data }.fetch(Lota::Data)
  end

  # love.data.hash's deprecated form names the function first, returns a
  # String, and marks the variant deprecated (wrap_DataModule.cpp:
  # 311-320). No other test calls it, so the notice is this test's to see.
  def test_hash_with_the_function_first_is_deprecated
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    out, = capture_io { Lota::Data.hash(:md5, "helloworld") }

    assert_match(/\ALota - Warning: .*data_module_test\.rb:\d+: Using deprecated function variant in Lota::Data\.hash \(replaced by variant with container return type parameter\)\n\z/, out)
    capture_io do
      assert_equal "fc5e038d38a57032085441e7fe7010b0", Lota::Data.hash(:md5, "helloworld").unpack1("H*")
    end
  ensure
    capture_io { Lota::Deprecation.output = output }
  end

  def test_packed_size_refuses_variable_lengths
    assert_equal 8, Lota::Data.packed_size("<!4 b i4")
    error = assert_raises(ArgumentError) { Lota::Data.packed_size("s1") }
    assert_equal "variable-length format", error.message
  end
end
