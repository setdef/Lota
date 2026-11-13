# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# Lota::Data, LÖVE's root type Data (src/modules/data/wrap_Data.cpp),
# which every Data class includes, and the copies Ruby's clone and dup
# make of each type that has LÖVE's clone
# (doc/contributors/design/translation.md).
class DataTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def file_data(bytes)
    Lota::Filesystem.new_file_data(bytes, "data.bin").first
  end

  # Each Data class includes Lota::Data, and answers type_of?("Data") by
  # LÖVE's Type hierarchy, where SoundData, ImageData, and FileData each
  # have Data as a parent.
  def test_every_data_class_is_a_data
    datas = [
      Lota::Sound::SoundData.new(4, 44_100, 16, 1),
      Lota::Image::ImageData.new(1, 1),
      file_data("hi"),
    ]
    datas.each do |data|
      assert_kind_of Lota::Data, data
      assert data.type_of?("Data"), data.type
      assert data.type_of?("Object"), data.type
    end
    assert_equal [8, 4, 2], datas.map(&:size)
    refute Lota::Graphics::Canvas.new(1, 1).is_a?(Lota::Data)
  end

  # Every Data is frozen as it is made, copies too, and its methods still
  # change its bytes. No engine object's wrapper is shareable: each Ractor
  # holds its own, as each of LÖVE's Lua states holds its own userdata
  # (doc/contributors/design/engine.md, "Threads and Ractors").
  def test_every_data_is_frozen_and_held_by_one_ractor
    image = Lota::Image::ImageData.new(1, 1)
    datas = [
      Lota::Sound::SoundData.new(4, 44_100, 16, 1),
      image,
      file_data("hi"),
      image.clone,
      image.dup,
      image.encode(:png),
      Lota::Data::ByteData.new(2),
      Lota::Data.compress(:data, :zlib, "hi"),
    ]
    datas.each do |data|
      assert_predicate data, :frozen?, data.type
      refute Ractor.shareable?(data), data.type
    end
    image.pixel = 0, 0, 1, 0, 0, 1
    assert_equal [1.0, 0.0, 0.0, 1.0], image.pixel(0, 0)
    refute Ractor.shareable?(Lota::Math::Transform.new)
    refute Ractor.shareable?(Lota::Graphics::Canvas.new(1, 1))
  end

  def test_size_and_string_read_the_bytes
    data = file_data("helloworld")

    assert_equal 10, data.size
    assert_equal "helloworld", data.string
    assert_equal "low", data.string(3, 3)
    error = assert_raises(RuntimeError) { data.string(8, 3) }
    assert_equal "The given offset and size parameters don't fit within the Data's size.", error.message
  end

  # getFloat, getDouble, and getInt8 to getInt32 read numbers of their
  # C type at a byte offset, as many as asked, Floats for the floats and
  # Integers for the integers (rule 14 of
  # doc/contributors/design/translation.md), always as an Array, since they
  # return several (rule 4).
  def test_numbers_are_read_by_their_c_type
    data = file_data([1.5, -2.0].pack("e2") + [-1, 7].pack("c2") + [-300, 70_000].pack("s<l<"))

    assert_equal [1.5], data.float(0)
    assert_equal [1.5, -2.0], data.float(0, 2)
    assert_equal [-1, 7], data.int8(8, 2)
    assert_equal [-300], data.int16(10)
    assert_equal [70_000], data.int32(12)
    assert(data.int8(8).all?(Integer))
    assert_equal [[2.5].pack("E").unpack1("E")], file_data([2.5].pack("E")).double(0)
    error = assert_raises(RuntimeError) { data.int32(14) }
    assert_equal "The given offset and count parameters don't fit within the Data's size.", error.message
    assert_equal "Invalid count parameter (must be greater than 0)",
      assert_raises(RuntimeError) { data.float(0, 0) }.message
  end

  # getUInt8, getUInt16, and getUInt32 read unsigned integers of their C
  # type (wrap_Data.cpp:138-161), named uint8, uint16, and uint32, as C
  # names uint8_t (rule 37 of doc/contributors/design/translation.md), so the
  # bytes int8 reads as -1 are 255.
  def test_unsigned_numbers_are_read_by_their_c_type
    data = file_data([255, 7].pack("C2") + [65_535].pack("S<") + [4_294_967_295].pack("L<"))

    assert_equal [255, 7], data.uint8(0, 2)
    assert_equal [-1], data.int8(0)
    assert_equal [65_535], data.uint16(2)
    assert_equal [4_294_967_295], data.uint32(4)
    assert_equal "The given offset and count parameters don't fit within the Data's size.",
      assert_raises(RuntimeError) { data.uint32(6) }.message
  end

  # performAtomic calls its function, the block, with the arguments after
  # it, while it holds the Data's lock, and returns what it returns; an
  # error leaves the lock, so it can be taken again.
  def test_perform_atomic_yields_under_the_lock_and_returns_the_blocks_value
    data = file_data("ab")

    assert_equal [1, 2, "ab"], data.perform_atomic(1, 2) { |a, b| [a, b, data.string] }
    assert_raises(ZeroDivisionError) { data.perform_atomic { 1 / 0 } }
    assert_equal :again, Thread.new { data.perform_atomic { :again } }.value
  end

  # Data:getPointer gives the bytes' address (wrap_Data.cpp:61-66), which
  # Lota gives as a Fiddle::Pointer: reading through it reads the Data's
  # own bytes, and writing through it writes them.
  def test_pointer_points_at_the_datas_own_bytes
    data = Lota::Data::ByteData.new("helloworld")
    pointer = data.pointer

    assert_instance_of Fiddle::Pointer, pointer
    assert_equal "o", pointer[4, 1]
    pointer[0, 5] = "HELLO"

    assert_equal "HELLOworld", data.string
    assert_equal pointer.to_i, data.pointer.to_i
  end

  # Data:getFFIPointer is LuaJIT's FFI pointer to the same address
  # (wrap_Data.cpp:166-176), which in Ruby is Fiddle's, sized as the Data
  # is, so it reads the whole Data, whatever its class.
  def test_ffi_pointer_is_the_same_address_with_the_datas_size
    data = Lota::Data::ByteData.new("helloworld")

    assert_equal data.pointer.to_i, data.ffi_pointer.to_i
    assert_equal 10, data.ffi_pointer.size
    assert_equal "helloworld", data.ffi_pointer.to_str
    image = Lota::Image::ImageData.new(2, 1)

    assert_equal image.size, image.ffi_pointer.size
    assert_equal image.string, image.ffi_pointer.to_str
  end

  # FileData:clone copies the bytes and the name into a new FileData.
  def test_a_file_data_copy_is_its_own
    data = file_data("helloworld")
    copy = data.clone

    assert_equal "helloworld", copy.string
    assert_equal 10, copy.size
    refute_same data.__send__(:native), copy.__send__(:native)
    refute_same data.__send__(:native), data.dup.__send__(:native)
  end

  # SoundData:clone copies the samples, so a change to the copy leaves the
  # original as it was.
  def test_a_sound_data_copy_is_its_own
    sound = Lota::Sound::SoundData.new(2, 44_100, 16, 1)
    copy = sound.dup
    copy.sample = 0, 1

    assert_equal 0.0, sound.sample(0)
    assert_equal 1.0, copy.sample(0)
    assert_equal [2, 44_100, 16, 1], [copy.sample_count, copy.sample_rate, copy.bit_depth, copy.channel_count]
  end

  # Decoder:clone opens the same sound again, decoding it from its start
  # however far the original has gone.
  def test_a_decoder_copy_decodes_from_the_start
    decoder = Lota::Sound::Decoder.new("resources/click.ogg")
    first = decoder.decode.string
    decoder.decode
    copy = decoder.clone

    assert_equal first, copy.decode.string
    refute_same decoder.__send__(:native), copy.__send__(:native)
  end

  # Source:clone makes a new Source of the same sound, with the original's
  # settings, which it then keeps apart.
  def test_a_source_copy_keeps_its_own_settings
    source = Lota::Audio::Source.new("resources/click.ogg", :static)
    source.volume = 0.5
    copy = source.clone
    copy.volume = 0.25

    assert_in_delta 0.5, source.volume
    assert_in_delta 0.25, copy.volume
    refute copy.playing?
    assert_equal "Source", copy.object_type
  end

  # Source:getType (wrap_Source.cpp:591-602) names how a Source holds its
  # sound, and a copy holds it as its original does; a Source has no type
  # (rule 41 of doc/contributors/design/translation.md).
  def test_a_source_gets_its_type
    assert_equal :static, Lota::Audio::Source.new("resources/click.ogg", :static).clone.get_type
    assert_equal :stream, Lota::Audio::Source.new("resources/click.ogg", :stream).get_type
    refute Lota::Audio::Source.new("resources/click.ogg", :static).respond_to?(:type)
  end
end
