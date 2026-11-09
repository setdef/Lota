# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# LÖVE's root types, Object and Data, are classes, as every type in LÖVE
# inherits from Object, and every Data from Data (src/common/Object.h,
# src/common/Data.h, and each type's header). Every object answers the
# methods LÖVE gives every object (src/common/runtime.cpp:530-552):
# release, __eq as ==, and __tostring as to_s (rule 38 of
# doc/contributors/design/translation.md). And a game reaches only LÖVE's calls
# and Ruby's own: what Lota's classes use to reach one another is not public.
class EngineObjectTest < Minitest::Test
  # Every class of LÖVE's Data that Lota binds, with the header that makes
  # it a Data.
  DATA_CLASSES = {
    Lota::Data::ByteData => "data/ByteData.h:32",
    Lota::Data::CompressedData => "data/CompressedData.h:35",
    Lota::Data::DataView => "data/DataView.h:33",
    Lota::Filesystem::FileData => "filesystem/FileData.h:35",
    Lota::Image::ImageData => "image/ImageData.h:45, by ImageDataBase.h:32",
    Lota::Sound::SoundData => "sound/SoundData.h:34",
    Lota::Font::GlyphData => "font/GlyphData.h:55",
  }.freeze

  def setup
    EngineHelper.open_window
  end

  def engine_classes
    ObjectSpace.each_object(Class).select { |klass| klass < Lota::Object }
  end

  def test_object_and_data_are_classes_and_every_object_is_one
    assert_instance_of Class, Lota::Object
    assert_instance_of Class, Lota::Data
    assert_equal Lota::Object, Lota::Data.superclass
    DATA_CLASSES.each { |klass, header| assert_equal Lota::Data, klass.superclass, header }
    [
      Lota::Graphics::Texture,
      Lota::Graphics::Font,
      Lota::Graphics::Shader,
      Lota::Mouse::Cursor,
      Lota::Physics::World,
      Lota::Physics::Body,
      Lota::Physics::Shape,
      Lota::Physics::Joint,
      Lota::Audio::Source,
      Lota::Math::Transform,
      Lota::Filesystem::File,
      Lota::Font::Rasterizer,
    ].each { |klass| assert_equal Lota::Object, klass.superclass, klass.name }
    assert_operator Lota::Physics::CircleShape, :<, Lota::Object
    assert_kind_of Lota::Object, Lota::Graphics::Canvas.new(4, 4)
    assert_kind_of Lota::Data, Lota::Data::ByteData.new("hi")
  end

  # LÖVE has no function that makes a plain Object or Data; each class it
  # makes objects of has its factory as new (rule 2).
  def test_only_the_classes_love_makes_have_new
    assert_raises(NoMethodError) { Lota::Object.new }
    assert_raises(NoMethodError) { Lota::Data.new }
    assert_raises(NoMethodError) { Lota::Data::CompressedData.new }
    assert_equal "Font", Lota::Graphics::Font.new(12).object_type
    assert_equal "ImageData", Lota::Image::ImageData.new(2, 2).object_type
    assert_equal "FileData", Lota::Filesystem.new_file_data("hi", "hi.txt").first.object_type
  end

  # w__release (runtime.cpp:170-197) returns whether the object was in use,
  # and luax_checktype refuses a released object wherever it is read
  # (runtime.h:576-577); its type still answers, and the engine hands the
  # object back as a new object.
  def test_release_ends_the_objects_use
    world = Lota::Physics::World.new
    body = Lota::Physics::Body.new(world, 1, 2, :dynamic)

    assert_same body, world.bodies.first
    assert body.release
    refute body.release
    error = assert_raises(RuntimeError) { body.position }
    assert_equal "Cannot use object after it has been released.", error.message
    error = assert_raises(RuntimeError) { Lota::Physics::CircleShape.new(body, 5) }
    assert_equal "Cannot use object after it has been released.", error.message
    assert_equal "Body", body.object_type
    assert body.type_of?(:Body)
    assert_equal "Body: NULL", body.to_s

    again = world.bodies.first
    refute_same body, again
    assert_equal [1.0, 2.0], again.position
    refute_equal again, body
    assert_equal body, body
  end

  # w__tostring (runtime.cpp:57-63): the type's name and the engine
  # object's address, as LuaJIT's %p writes it.
  def test_to_s_names_the_type_and_address
    texture = Lota::Graphics::Canvas.new(4, 4)
    address = LotaNativeTest.engine_address(texture.__send__(:native))

    refute_equal 0, address
    assert_equal "Texture: #{LotaNativeTest.luajit_pointer(address)}", texture.to_s
    assert_match(/\AFont: 0x\h{8,16}\z/, Lota::Graphics::Font.new(12).to_s)
    assert_equal "Data", Lota::Data.decode(:data, :hex, "6869").to_s.split(":").first
  end

  # lj_strfmt_wptr (LuaJIT 2.1, lj_strfmt.c:135-152): NULL, or 0x and at
  # least eight lowercase digits, two more for each byte above 32 bits.
  def test_addresses_are_written_as_luajit_writes_a_pointer
    assert_equal "NULL", LotaNativeTest.luajit_pointer(0)
    assert_equal "0x00001234", LotaNativeTest.luajit_pointer(0x1234)
    assert_equal "0xdeadbeef", LotaNativeTest.luajit_pointer(0xdeadbeef)
    assert_equal "0x0102a4c5e0", LotaNativeTest.luajit_pointer(0x1_02a4_c5e0)
    assert_equal "0x600003a1c000", LotaNativeTest.luajit_pointer(0x6000_03a1_c000)
    assert_equal "0xffff800000001000", LotaNativeTest.luajit_pointer(0xffff_8000_0000_1000)
  end

  # w__eq (runtime.cpp:82-88), which Lua asks only of two different
  # objects of one type: the same engine object, while neither is
  # released.
  def test_equal_objects_hold_the_same_engine_object
    texture = Lota::Graphics::Canvas.new(4, 4)
    copy = texture.clone

    refute_same texture, copy
    assert_equal texture, copy
    refute_equal texture, Lota::Graphics::Canvas.new(4, 4)
    refute_equal texture, texture.to_s
    refute_equal texture, nil
    refute_equal Lota::Data::ByteData.new("hi"), Lota::Data::ByteData.new("hi")
  end

  # w__release lets go of its reference at once (runtime.cpp:170-197), so
  # an object nothing else holds is freed then.
  def test_release_lets_go_of_the_object_at_once
    image = Lota::Image::ImageData.new(4, 4)
    LotaNativeTest.observe_image_data(image.__send__(:native))

    assert_equal [2], LotaNativeTest.observed_reference_counts
    image.release

    assert_equal [1], LotaNativeTest.observed_reference_counts
  ensure
    LotaNativeTest.forget_observed
  end

  # A File's last reference closes it (physfs/File.cpp, ~File), so a
  # released File the game alone held is closed at once.
  def test_a_released_file_is_closed_at_once
    skip("Windows has no /dev/fd to count a process's open files in") if TestHome::WINDOWS
    open_files = -> { Dir.children("/dev/fd").size }
    file, = Lota::Filesystem.open_file("released.txt", :w)
    with_file = open_files.call
    file.release

    assert_equal with_file - 1, open_files.call
  ensure
    Lota::Filesystem.remove("released.txt")
  end

  # A release inside a call that still uses the object, as perform_atomic
  # holds the Data's lock while its block runs, lets go when the call
  # returns, not under it; the sanitized run would see the lock of a freed
  # Data otherwise.
  def test_a_release_inside_a_call_waits_for_the_call_to_return
    image = Lota::Image::ImageData.new(4, 4)
    LotaNativeTest.observe_image_data(image.__send__(:native))
    inside = image.perform_atomic do
      image.release
      LotaNativeTest.observed_reference_counts
    end

    assert_equal [[2], [1]], [inside, LotaNativeTest.observed_reference_counts]
    alone = Lota::Image::ImageData.new(4, 4)

    assert(alone.perform_atomic { alone.release })
  ensure
    LotaNativeTest.forget_observed
  end

  def test_the_engines_object_is_not_public
    texture = Lota::Graphics::Canvas.new(4, 4)

    refute_respond_to texture, :native
    assert_raises(NoMethodError) { texture.native }
    engine_classes.each do |klass|
      refute klass.public_method_defined?(:native), "#{klass}#native"
      refute_respond_to klass, :from_native, klass.name
    end
  end

  # What Lota's own modules and classes use to reach one another is
  # neither a LÖVE call nor Ruby's own, so a game cannot call it.
  def test_lotas_own_helpers_are_not_public
    {
      Lota::Audio => %i[setting_pairs],
      Lota::Audio::Effect => %i[of],
      Lota::Audio::Filter => %i[of],
      Lota::Audio::Source => %i[numbers number],
      Lota::Data::ByteData => %i[offset_and_values],
      Lota::Filesystem => %i[enumerate_lines],
      Lota::Font => %i[file_data image_data optional_number optional_integer],
      Lota::Font::TrueTypeRasterizer => %i[native],
      Lota::Font::BMFontRasterizer => %i[native],
      Lota::Graphics => %i[colored_text standard_placement placement_after],
      Lota::Graphics::Font => %i[image_data],
      Lota::Graphics::GraphicsBuffer => %i[create declarations declaration native_content mark_deprecated_bindings],
      Lota::Graphics::Shader => %i[compute source],
      Lota::Math => %i[coordinates_of],
      Lota::Math::RandomGenerator => %i[number],
      Lota::Math::Transform => %i[native_of layout_and_elements],
      Lota::Physics => %i[shape joint],
      Lota::Physics::Joint => %i[anchored number],
    }.each do |owner, names|
      names.each { |name| refute_respond_to owner, name, "#{owner}.#{name}" }
    end
  end
end
