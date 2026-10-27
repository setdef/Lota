# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# ADR 001, rule 16: every object Lota hands a game answers +type+ with
# LÖVE's name for its type, as Object:type does, and <tt>type_of?</tt>
# for that type and each type it inherits from, as Object:typeOf does
# (vendor/love/src/common/runtime.cpp:65-80). The parents are LÖVE's own,
# as each type names its parent: graphics/Texture.cpp:160,
# graphics/Drawable.cpp:29, graphics/Font.cpp:53, image/ImageData.cpp:34,
# filesystem/FileData.cpp:32, mouse/Cursor.cpp:28, graphics/Quad.cpp:32,
# graphics/SpriteBatch.cpp:41, and common/Data.cpp:28.
class ObjectTypeTest < Minitest::Test
  PNG = File.binread(File.join(NativeHelper::ROOT, "vendor/love/testing/output/expected/love.test.graphics.clear-1.png"))

  def setup
    EngineHelper.open_window
  end

  def objects
    file_data = Lota::Filesystem::FileData.new(PNG, "clear-1.png")
    {
      "Texture" => [Lota::Graphics::Canvas.new(4, 4), %w[Texture Drawable Object]],
      "Font" => [Lota::Graphics::Font.new(12), %w[Font Object]],
      "ImageData" => [Lota::Image::ImageData.new(file_data), %w[ImageData Data Object]],
      "FileData" => [file_data, %w[FileData Data Object]],
      "Cursor" => [Lota::Mouse.system_cursor(:hand), %w[Cursor Object]],
      "Quad" => [Lota::Graphics::Quad.new(0, 0, 1, 1, 4, 4), %w[Quad Object]],
      "SpriteBatch" => [
        Lota::Graphics::SpriteBatch.new(Lota::Graphics::Canvas.new(4, 4)),
        %w[SpriteBatch Drawable Object],
],
    }
  end

  def test_each_object_names_its_loves_type
    objects.each do |name, (object, _)|
      assert_equal name, object.type
    end
  end

  def test_each_object_is_of_its_type_and_every_parent
    objects.each do |name, (object, types)|
      types.each { |type| assert object.type_of?(type), "#{name} is a #{type}" }
    end
  end

  def test_an_object_is_not_of_another_type_or_of_a_name_love_lacks
    texture = Lota::Graphics::Canvas.new(4, 4)

    refute texture.type_of?("Font")
    refute texture.type_of?("Data")
    refute texture.type_of?("Image")
    refute texture.type_of?("texture")
    refute texture.type_of?("")
  end

  # luaL_checkstring raises for a table where it wants a string; Ruby
  # raises TypeError for any value that is not a String.
  def test_a_name_that_is_not_a_string_raises
    texture = Lota::Graphics::Canvas.new(4, 4)
    error = assert_raises(TypeError) { texture.type_of?(:Texture) }

    assert_equal "wrong argument type Symbol (expected String)", error.message
    assert_raises(TypeError) { texture.type_of?(nil) }
  end
end
