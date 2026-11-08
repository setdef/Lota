# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.data tests (vendor/love/testing/tests/data.lua),
# translated to Ruby by ADR 001's rules. They run in the test suite's own
# process (test/lovetest/data_test.rb) and under lota run
# (test/lovetest/game). love.data's container types, formats, and hash
# functions are Symbols (rule 9). The class is DataModuleTest, as Lota's
# is LotaModuleTest, since DataTest is test/native/data_test.rb's.
class DataModuleTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type (love.test.data.ByteData).
  TYPES = %w[ByteData CompressedData].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Lua's type of +value+, for the two kinds Lövetest's compress and
  # encode tests tell apart: a string, and the userdata of one of LÖVE's
  # objects, which Lota makes a Lota::Object, as assertObject recognises it
  # (lovetest_helper.rb, assert_object).
  def lua_type(value)
    if value.is_a?(String) then "string"
    elsif value.is_a?(Lota::Object) then "userdata"
    else value.class.name
    end
  end

  # Translated to Ruby from love.test.data.ByteData
  # (vendor/love/testing/tests/data.lua:12-40): newByteData becomes
  # ByteData.new (rule 2), getString and getSize string and size (rule 3),
  # setString the writer string= of its two values (rule 6), and clone
  # Ruby's clone, which makes LÖVE's copy (ADR 001, section 7). Lövetest
  # reads the bytes through getFFIPointer only where its global ffi is
  # set, which neither Lövetest's main.lua nor its classes set, so LÖVE
  # skips that check; Lota has no FFI pointer, and leaves it out.
  def test_byte_data
    # create new obj
    data = Lota::Data::ByteData.new("helloworld")
    assert_object(data)

    # check properties match expected
    assert_equal("helloworld", data.string, "check data string")
    assert_equal(10, data.size, "check data size")

    # check cloning the bytedata
    cloneddata = data.clone
    assert_object(cloneddata)
    assert_equal("helloworld", cloneddata.string, "check cloned data")
    assert_equal(10, cloneddata.size, "check cloned size")

    # check overwriting the byte data string
    data.string = "love!", 5
    assert_equal("hellolove!", data.string, "check change string")
  end

  # Translated to Ruby from love.test.data.CompressedData
  # (vendor/love/testing/tests/data.lua:44-62): getFormat becomes format
  # (rule 3), a Symbol (rule 9), and getSize and getString size and string
  # (rule 3).
  def test_compressed_data
    # create new compressed data
    cdata = Lota::Data.compress(:data, :zlib, "helloworld", -1)
    assert_object(cdata)
    assert_equal(:zlib, cdata.format, "check format used")

    # check properties match expected
    assert_equal(18, cdata.size)
    assert_equal("helloworld", Lota::Data.decompress(:data, cdata).string)

    # check cloning the data
    clonedcdata = cdata.clone
    assert_object(clonedcdata)
    assert_equal(:zlib, clonedcdata.format)
    assert_equal(18, clonedcdata.size)
    assert_equal("helloworld", Lota::Data.decompress(:data, clonedcdata).string)
  end

  # Translated to Ruby from love.test.data.compress
  # (vendor/love/testing/tests/data.lua:73-111): Lua's type becomes
  # lua_type, above, and obj:type() object_type (rule 16).
  def test_compress
    # here just testing each combo 'works' - in decompress's test method
    # we actually check the compress + decompress give the right value back
    compressions = [
      [Lota::Data.compress(:string, :lz4, "helloworld", -1), "string"],
      [Lota::Data.compress(:string, :lz4, "helloworld", 0), "string"],
      [Lota::Data.compress(:string, :lz4, "helloworld", 9), "string"],
      [Lota::Data.compress(:string, :zlib, "helloworld", -1), "string"],
      [Lota::Data.compress(:string, :zlib, "helloworld", 0), "string"],
      [Lota::Data.compress(:string, :zlib, "helloworld", 9), "string"],
      [Lota::Data.compress(:string, :gzip, "helloworld", -1), "string"],
      [Lota::Data.compress(:string, :gzip, "helloworld", 0), "string"],
      [Lota::Data.compress(:string, :gzip, "helloworld", 9), "string"],
      [Lota::Data.compress(:string, :deflate, "aaaaaa", 1), "string"],
      [Lota::Data.compress(:string, :deflate, "heloworld", -1), "string"],
      [Lota::Data.compress(:string, :deflate, "heloworld", 0), "string"],
      [Lota::Data.compress(:string, :deflate, "heloworld", 9), "string"],
      [Lota::Data.compress(:data, :lz4, "helloworld", -1), "userdata"],
      [Lota::Data.compress(:data, :lz4, "helloworld", 0), "userdata"],
      [Lota::Data.compress(:data, :lz4, "helloworld", 9), "userdata"],
      [Lota::Data.compress(:data, :zlib, "helloworld", -1), "userdata"],
      [Lota::Data.compress(:data, :zlib, "helloworld", 0), "userdata"],
      [Lota::Data.compress(:data, :zlib, "helloworld", 9), "userdata"],
      [Lota::Data.compress(:data, :gzip, "helloworld", -1), "userdata"],
      [Lota::Data.compress(:data, :gzip, "helloworld", 0), "userdata"],
      [Lota::Data.compress(:data, :gzip, "helloworld", 9), "userdata"],
      [Lota::Data.compress(:data, :deflate, "heloworld", -1), "userdata"],
      [Lota::Data.compress(:data, :deflate, "heloworld", 0), "userdata"],
      [Lota::Data.compress(:data, :deflate, "heloworld", 9), "userdata"],
    ]
    compressions.each do |compressed, kind|
      assert_not_nil(compressed)
      # sense check return type and make sure bytedata returns are an object
      assert_equal(kind, lua_type(compressed), "check is userdata")
      refute_equal(nil, compressed.object_type, "check has :type()") if kind == "userdata"
    end
  end

  # Translated to Ruby from love.test.data.decode
  # (vendor/love/testing/tests/data.lua:115-126): newByteData becomes
  # ByteData.new (rule 2), and getString string (rule 3).
  def test_decode
    # setup encoded strings
    str1 = Lota::Data.encode(:string, :base64, "helloworld", 0)
    str2 = Lota::Data.encode(:string, :hex, "helloworld")
    str3 = Lota::Data.encode(:data, :base64, "helloworld", 0)
    str4 = Lota::Data.encode(:data, :hex, "helloworld")
    # check value matches expected when decoded back
    assert_equal("helloworld", Lota::Data.decode(:string, :base64, str1), "check string base64 decode")
    assert_equal("helloworld", Lota::Data.decode(:string, :hex, str2), "check string hex decode")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decode(:data, :base64, str3).string,
      "check data base64 decode")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decode(:data, :hex, str4).string,
      "check data hex decode")
  end

  # Translated to Ruby from love.test.data.decompress
  # (vendor/love/testing/tests/data.lua:130-169), as test_decode
  # translates its names.
  def test_decompress
    # setup compressed data for each combination
    str1 = Lota::Data.compress(:string, :lz4, "helloworld", -1)
    str2 = Lota::Data.compress(:string, :lz4, "helloworld", 0)
    str3 = Lota::Data.compress(:string, :lz4, "helloworld", 9)
    str4 = Lota::Data.compress(:string, :zlib, "helloworld", -1)
    str5 = Lota::Data.compress(:string, :zlib, "helloworld", 0)
    str6 = Lota::Data.compress(:string, :zlib, "helloworld", 9)
    str7 = Lota::Data.compress(:string, :gzip, "helloworld", -1)
    str8 = Lota::Data.compress(:string, :gzip, "helloworld", 0)
    str9 = Lota::Data.compress(:string, :gzip, "helloworld", 9)
    str10 = Lota::Data.compress(:data, :lz4, "helloworld", -1)
    str11 = Lota::Data.compress(:data, :lz4, "helloworld", 0)
    str12 = Lota::Data.compress(:data, :lz4, "helloworld", 9)
    str13 = Lota::Data.compress(:data, :zlib, "helloworld", -1)
    str14 = Lota::Data.compress(:data, :zlib, "helloworld", 0)
    str15 = Lota::Data.compress(:data, :zlib, "helloworld", 9)
    str16 = Lota::Data.compress(:data, :gzip, "helloworld", -1)
    str17 = Lota::Data.compress(:data, :gzip, "helloworld", 0)
    str18 = Lota::Data.compress(:data, :gzip, "helloworld", 9)
    # check decompressed value matches whats expected
    assert_equal("helloworld", Lota::Data.decompress(:string, :lz4, str1), "check string lz4 decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :lz4, str2), "check string lz4 decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :lz4, str3), "check string lz4 decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :zlib, str4), "check string zlib decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :zlib, str5), "check string zlib decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :zlib, str6), "check string zlib decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :gzip, str7), "check string glib decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :gzip, str8), "check string glib decompress")
    assert_equal("helloworld", Lota::Data.decompress(:string, :gzip, str9), "check string glib decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :lz4, str10).string,
      "check data lz4 decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :lz4, str11).string,
      "check data lz4 decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :lz4, str12).string,
      "check data lz4 decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :zlib, str13).string,
      "check data zlib decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :zlib, str14).string,
      "check data zlib decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :zlib, str15).string,
      "check data zlib decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :gzip, str16).string,
      "check data glib decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :gzip, str17).string,
      "check data glib decompress")
    assert_equal(Lota::Data::ByteData.new("helloworld").string, Lota::Data.decompress(:data, :gzip, str18).string,
      "check data glib decompress")
  end

  # Translated to Ruby from love.test.data.encode
  # (vendor/love/testing/tests/data.lua:173-193), as test_compress
  # translates Lua's type and obj:type().
  def test_encode
    # here just testing each combo 'works' - in decode's test method
    # we actually check the encode + decode give the right value back
    encodes = [
      [Lota::Data.encode(:string, :base64, "helloworld", 0), "string"],
      [Lota::Data.encode(:string, :base64, "helloworld", 2), "string"],
      [Lota::Data.encode(:string, :hex, "helloworld"), "string"],
      [Lota::Data.encode(:data, :base64, "helloworld", 0), "userdata"],
      [Lota::Data.encode(:data, :base64, "helloworld", 2), "userdata"],
      [Lota::Data.encode(:data, :hex, "helloworld"), "userdata"],
    ]
    encodes.each do |encoded, kind|
      assert_not_nil(encoded)
      # sense check return type and make sure bytedata returns are an object
      assert_equal(kind, lua_type(encoded), "check is usedata")
      refute_equal(nil, encoded.object_type, "check has :type()") if kind == "userdata"
    end
  end

  # Translated to Ruby from love.test.data.hash
  # (vendor/love/testing/tests/data.lua:207-237): love.data.hash becomes
  # Lota::Data.hash, which rule 13 names +hash+, and which with arguments
  # is LÖVE's rather than Ruby's own Object#hash.
  def test_hash
    # setup all the different hashing types
    str1 = Lota::Data.hash(:string, :md5, "helloworld")
    str2 = Lota::Data.hash(:string, :sha1, "helloworld")
    str3 = Lota::Data.hash(:string, :sha224, "helloworld")
    str4 = Lota::Data.hash(:string, :sha256, "helloworld")
    str5 = Lota::Data.hash(:string, :sha384, "helloworld")
    str6 = Lota::Data.hash(:string, :sha512, "helloworld")
    data1 = Lota::Data.hash(:data, :md5, "helloworld")
    data2 = Lota::Data.hash(:data, :sha1, "helloworld")
    data3 = Lota::Data.hash(:data, :sha224, "helloworld")
    data4 = Lota::Data.hash(:data, :sha256, "helloworld")
    data5 = Lota::Data.hash(:data, :sha384, "helloworld")
    data6 = Lota::Data.hash(:data, :sha512, "helloworld")
    # check encoded hash value matches what's expected for that algo
    # test container string
    assert_equal("fc5e038d38a57032085441e7fe7010b0", Lota::Data.encode(:string, :hex, str1), "check string md5 encode")
    assert_equal("6adfb183a4a2c94a2f92dab5ade762a47889a5a1", Lota::Data.encode(:string, :hex, str2),
      "check string sha1 encode")
    assert_equal("b033d770602994efa135c5248af300d81567ad5b59cec4bccbf15bcc", Lota::Data.encode(:string, :hex, str3),
      "check string sha224 encode")
    assert_equal("936a185caaa266bb9cbe981e9e05cb78cd732b0b3280eb944412bb6f8f8f07af",
      Lota::Data.encode(:string, :hex, str4), "check string sha256 encode")
    assert_equal("97982a5b1414b9078103a1c008c4e3526c27b41cdbcf80790560a40f2a9bf2ed4427ab1428789915ed4b3dc07c454bd9",
      Lota::Data.encode(:string, :hex, str5), "check string sha384 encode")
    assert_equal("1594244d52f2d8c12b142bb61f47bc2eaf503d6d9ca8480cae9fcf112f66e4967dc5e8fa98285e36db8af1b8ffa8b84cb15e0fbcf836c3deb803c13f37659a60",
      Lota::Data.encode(:string, :hex, str6), "check string sha512 encode")
    # test container data
    assert_equal("fc5e038d38a57032085441e7fe7010b0", Lota::Data.encode(:string, :hex, data1), "check data md5 encode")
    assert_equal("6adfb183a4a2c94a2f92dab5ade762a47889a5a1", Lota::Data.encode(:string, :hex, data2),
      "check data sha1 encode")
    assert_equal("b033d770602994efa135c5248af300d81567ad5b59cec4bccbf15bcc", Lota::Data.encode(:string, :hex, data3),
      "check data sha224 encode")
    assert_equal("936a185caaa266bb9cbe981e9e05cb78cd732b0b3280eb944412bb6f8f8f07af",
      Lota::Data.encode(:string, :hex, data4), "check data sha256 encode")
    assert_equal("97982a5b1414b9078103a1c008c4e3526c27b41cdbcf80790560a40f2a9bf2ed4427ab1428789915ed4b3dc07c454bd9",
      Lota::Data.encode(:string, :hex, data5), "check data sha384 encode")
    assert_equal("1594244d52f2d8c12b142bb61f47bc2eaf503d6d9ca8480cae9fcf112f66e4967dc5e8fa98285e36db8af1b8ffa8b84cb15e0fbcf836c3deb803c13f37659a60",
      Lota::Data.encode(:string, :hex, data6), "check data sha512 encode")
  end

  # Translated to Ruby from love.test.data.getPackedSize
  # (vendor/love/testing/tests/data.lua:197-204): getPackedSize becomes
  # packed_size (rule 3).
  def test_get_packed_size
    pack1 = Lota::Data.packed_size(">xI3b")
    pack2 = Lota::Data.packed_size(">I2B")
    pack3 = Lota::Data.packed_size(">I4I4I4I4x")
    assert_equal(5, pack1, "check pack size 1")
    assert_equal(3, pack2, "check pack size 2")
    assert_equal(17, pack3, "check pack size 3")
  end

  # Translated to Ruby from love.test.data.newByteData
  # (vendor/love/testing/tests/data.lua:242-244): newByteData becomes
  # ByteData.new (rule 2).
  # @NOTE this is just basic nil checking, objs have their own test method
  def test_new_byte_data
    assert_object(Lota::Data::ByteData.new("helloworld"))
  end

  # Translated to Ruby from love.test.data.newDataView
  # (vendor/love/testing/tests/data.lua:249-251): newDataView becomes
  # DataView.new (rule 2).
  # @NOTE this is just basic nil checking, objs have their own test method
  def test_new_data_view
    assert_object(Lota::Data::DataView.new(Lota::Data::ByteData.new("helloworld"), 0, 10))
  end

  # Translated to Ruby from love.test.data.pack
  # (vendor/love/testing/tests/data.lua:255-264): unpack's results, then
  # the position after them, are an Array (rule 4), of which Lua keeps the
  # first four.
  def test_pack
    packed1 = Lota::Data.pack(:string, ">I4I4I4I4", 9999, 1000, 1010, 2030)
    packed2 = Lota::Data.pack(:data, ">I4I4I4I4", 9999, 1000, 1010, 2030)
    a, b, c, d = Lota::Data.unpack(">I4I4I4I4", packed1)
    e, f, g, h = Lota::Data.unpack(">I4I4I4I4", packed2)
    assert_equal(9999 + 9999, a + e, "check packed 1")
    assert_equal(1000 + 1000, b + f, "check packed 2")
    assert_equal(1010 + 1010, c + g, "check packed 3")
    assert_equal(2030 + 2030, d + h, "check packed 4")
  end

  # Translated to Ruby from love.test.data.unpack
  # (vendor/love/testing/tests/data.lua:268-276), as test_pack translates
  # unpack's results; Lua's .. joins strings as Ruby's interpolation does.
  def test_unpack
    packed1 = Lota::Data.pack(:string, ">s5s4I3", "hello", "love", 100)
    packed2 = Lota::Data.pack(:data, ">s5I2", "world", 20)
    a, b, c = Lota::Data.unpack(">s5s4I3", packed1)
    d, e = Lota::Data.unpack(">s5I2", packed2)
    assert_equal("#{a} #{d}", "hello world", "check unpack 1")
    assert_equal(b, "love", "check unpack 2")
    assert_equal(c - e, 80, "check unpack 3")
  end
  # SPDX-SnippetEnd
end
