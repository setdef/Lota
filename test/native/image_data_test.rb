# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Image::ImageData's pixels, as LÖVE's LuaJIT code reads and writes
# them in place of ImageData's C++ (src/modules/image/wrap_ImageData.lua),
# where the two differ: components in double precision rather than
# through a float, positions rounded down rather than truncated, LuaJIT's
# bit library's rounding, ties to even, and its conversions of a Lua
# number into a C field. Each format's expected bytes are worked out from
# the Lua's conversions table by hand.
class ImageDataTest < Minitest::Test
  ImageData = Lota::Image::ImageData

  def setup
    EngineHelper.open_window
  end

  def one(format, bytes = nil)
    ImageData.new(1, 1, format, bytes)
  end

  # tolua divides the byte by 255 as a Lua number, a double, where the C++
  # divides in a float: 128 reads as 0.5019607843137255, not
  # 0.501960813999176.
  def test_an_8_bit_pixel_reads_in_double_precision
    assert_equal [128 / 255.0, 0.0, 1.0, 64 / 255.0], one(:rgba8, "\x80\x00\xFF\x40".b).pixel(0, 0)
  end

  # getPixel rounds its position down (math.floor), where the C++ reads
  # it with luaL_checkinteger, which truncates: -0.5 is the column -1,
  # outside the image, and 1.9 the column 1.
  def test_a_position_is_rounded_down
    image = ImageData.new(2, 2, :r8, "\x00\x00\x00\xFF".b)

    assert_equal [1.0, 0.0, 0.0, 1.0], image.pixel(1.9, 1.2)
    error = assert_raises(RuntimeError) { image.pixel(-0.5, 0) }
    assert_equal "Attempt to get out-of-range pixel!", error.message
    assert_raises(RuntimeError) { image.pixel = -0.5, 0, 1, 1, 1 }
  end

  # fromlua stores (clamp01(x) * 255) + 0.5, cut to a whole number by
  # LuaJIT, and a missing alpha as 255; a table of the color works as its
  # four numbers do.
  def test_setting_a_pixel_clamps_rounds_and_fills_in_alpha
    image = one(:rgba8)
    image.pixel = 0, 0, 0.5, 2, -1

    assert_equal "\x80\xFF\x00\xFF".b, image.string.b
    image.pixel = 0, 0, [0, 1, 0, 0.25]

    assert_equal "\x00\xFF\x00\x40".b, image.string.b
  end

  def test_a_color_component_must_be_a_number
    image = one(:rgba8)
    error = assert_raises(TypeError) { image.pixel = 0, 0, 1, nil, 1 }

    assert_equal "bad green color component argument to Lota::Image::ImageData#pixel= (expected number)",
      error.message
    image.pixel = 0, 0, 1, 1, 1, nil

    assert_equal [1.0, 1.0, 1.0, 1.0], image.pixel(0, 0)
  end

  # The 16-bit, half-float, and float formats: 0.5 is stored as 32768
  # (0.5 * 65535 + 0.5), and 0.1 as the float nearest it, each read back
  # as a double.
  def test_wider_formats_store_and_read_as_the_lua_does
    r16 = one(:r16)
    r16.pixel = 0, 0, 0.5, 0, 0

    assert_equal [32_768 / 65_535.0, 0.0, 0.0, 1.0], r16.pixel(0, 0)
    half = one(:rgba16f)
    half.pixel = 0, 0, 0.25, -2.5, 4, nil

    assert_equal [0.25, -2.5, 4.0, 1.0], half.pixel(0, 0)
    single = one(:rg32f)
    single.pixel = 0, 0, 0.1, 3, 0

    assert_equal [[0.1].pack("e").unpack1("e"), 3.0, 0.0, 1.0], single.pixel(0, 0)
  end

  # The packed formats go through LuaJIT's bit library, which rounds to
  # the nearest whole number, ties to even, where the C++ adds 0.5 and
  # truncates: a green of 2.5 / 15 is 2.5 fifteenths, stored as 2, and an
  # alpha of 0.5 in rgb5a1 as 0.
  def test_packed_formats_round_ties_to_even
    rgba4 = one(:rgba4)
    rgba4.pixel = 0, 0, 1, 2.5 / 15, 0, nil

    assert_equal [0xF20F].pack("S"), rgba4.string.b
    assert_equal [1.0, 2 / 15.0, 0.0, 1.0], rgba4.pixel(0, 0)
    rgb5a1 = one(:rgb5a1)
    rgb5a1.pixel = 0, 0, 1, 0, 1, 0.5

    assert_equal [(0x1F << 11) | (0x1F << 1)].pack("S"), rgb5a1.string.b
    assert_equal [1.0, 0.0, 1.0, 0.0], rgb5a1.pixel(0, 0)
    rgb565 = one(:rgb565)
    rgb565.pixel = 0, 0, 0, 1, 0

    assert_equal [0x3F << 5].pack("S"), rgb565.string.b
  end

  # rgb10a2 and rg11b10f are 32-bit words the bit library makes signed,
  # and LuaJIT stores a negative number in the unsigned field as 0 on
  # Apple silicon (FCVTZU), so a pixel whose alpha sets the word's top
  # bit, as the default alpha of 3 does, is stored as 0, as in LÖVE.
  def test_a_32_bit_word_with_its_top_bit_set_is_stored_as_luajit_stores_it
    rgb10a2 = one(:rgb10a2)
    rgb10a2.pixel = 0, 0, 1, 0, 1, 0

    assert_equal [0x3FF | (0x3FF << 20)].pack("L"), rgb10a2.string.b
    assert_equal [1.0, 0.0, 1.0, 0.0], rgb10a2.pixel(0, 0)
    rgb10a2.pixel = 0, 0, 1, 1, 1

    assert_equal [0].pack("L"), rgb10a2.string.b
    rg11b10f = one(:rg11b10f)
    rg11b10f.pixel = 0, 0, 1, 0.5, 0

    assert_equal [1.0, 0.5, 0.0, 1.0], rg11b10f.pixel(0, 0)
  end

  # A format the Lua's conversions table lacks has no pointer in its
  # object cache, so each method raises, naming itself.
  def test_a_format_the_lua_does_not_read_raises
    image = one(:srgba8)
    error = assert_raises(RuntimeError) { image.pixel(0, 0) }

    assert_equal "Lota::Image::ImageData#pixel does not currently support the srgba8 pixel format.", error.message
    assert_raises(RuntimeError) { image.pixel = 0, 0, 1, 1, 1 }
    assert_raises(RuntimeError) { image.map_pixel { [0, 0, 0, 0] } }
  end

  # mapPixel calls its function with each position, as Integers, and
  # color, row by row, and stores what it returns; a rectangle is checked
  # before it is rounded down.
  def test_map_pixel_calls_the_block_for_each_pixel_of_the_rectangle
    image = ImageData.new(3, 2, :rgba8)
    seen = []
    image.map_pixel(1, 0, 2, 2) do |x, y, r, g, b, a|
      seen << [x, y]
      [1 - r, g, b + 1, a + (x * 0.25)]
    end

    assert_equal [[1, 0], [2, 0], [1, 1], [2, 1]], seen
    assert(seen.flatten.all?(Integer))
    assert_equal [0.0, 0.0, 0.0, 0.0], image.pixel(0, 0)
    assert_equal [1.0, 0.0, 1.0, 128 / 255.0], image.pixel(2, 1)
    error = assert_raises(RuntimeError) { image.map_pixel(2, 0, 2, 1) { [0, 0, 0, 0] } }
    assert_equal "Invalid rectangle dimensions", error.message
    image.map_pixel(0.5, 0, 2.5, 1) { [1, 1, 1, 1] }

    assert_equal [1.0, 1.0, 1.0, 1.0], image.pixel(0, 0)
  end

  # Lua's local r, g, b, a takes as many values as the function returns,
  # so an r8 image needs only red back.
  def test_map_pixel_takes_as_few_components_as_the_format_needs
    image = one(:r8)
    image.map_pixel { 1 }

    assert_equal [1.0, 0.0, 0.0, 1.0], image.pixel(0, 0)
    assert_raises(TypeError) { one(:rgba8).map_pixel { [1] } }
  end

  def test_a_sized_image_data_checks_its_size_format_and_bytes
    assert_equal "Invalid image size.", assert_raises(RuntimeError) { ImageData.new(0, 1) }.message
    assert_match(/\AInvalid pixel format: rgba7/, assert_raises(ArgumentError) { ImageData.new(1, 1, :rgba7) }.message)
    error = assert_raises(RuntimeError) { ImageData.new(1, 1, :rgba8, "\x00".b) }

    assert_equal "The size of the raw byte string must match the ImageData's actual size in bytes.", error.message
    from_data = ImageData.new(1, 1, :rgba8, one(:rgba8, "\x01\x02\x03\x04".b))

    assert_equal "\x01\x02\x03\x04".b, from_data.string.b
    assert_equal [16, 16], [ImageData.new(16, 16).width, ImageData.new(16, 16).height]
  end

  # Ruby's clone and dup make LÖVE's copy, a new ImageData of its own
  # pixels (w_ImageData_clone).
  def test_clone_and_dup_copy_the_pixels
    image = one(:rgba8, "\x10\x20\x30\x40".b)
    copies = [image.clone, image.dup]
    copies.each { |copy| copy.pixel = 0, 0, 1, 1, 1, 1 }

    assert_equal "\x10\x20\x30\x40".b, image.string.b
    copies.each do |copy|
      assert_equal "\xFF\xFF\xFF\xFF".b, copy.string.b
      assert_equal "ImageData", copy.type
      refute_same image.native, copy.native
    end
  end
end
