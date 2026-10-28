# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "rbconfig"

# Lota::ErrorMessage, which rewrites the Lua names in LÖVE's error
# messages by ADR 001's rules (section 7). test/native/
# error_translation_test.rb checks the messages the engine raises, through
# the handler that calls it; these check the translator itself, in Ruby.
class ErrorMessageTest < Minitest::Test
  def translate(message)
    Lota::ErrorMessage.translate(message)
  end

  def test_a_module_takes_its_ruby_name
    assert_equal "Lota::Image must be loaded", translate("love.image must be loaded")
  end

  def test_a_function_and_a_method_take_the_names_the_generators_table_gives_them
    assert_equal "Lota::Window.title= and Lota::Image::ImageData#pixel",
      translate("love.window.setTitle and ImageData:getPixel")
  end

  def test_a_function_the_table_does_not_know_keeps_its_spelling_after_its_module
    assert_equal "Lota::Graphics.noSuchFunction_2 and Texture:noSuchMethod",
      translate("love.graphics.noSuchFunction_2 and Texture:noSuchMethod")
  end

  # A full stop that ends a sentence, or a module that ends at a digit or
  # a capital, ends the module's name.
  def test_a_module_ends_where_its_lowercase_letters_end
    assert_equal "in Lota::Graphics. Lota::Image2 Lota::Image.2 love.Image",
      translate("in love.graphics. love.image2 love.image.2 love.Image")
  end

  def test_a_name_counts_only_where_it_starts_a_word
    assert_equal "glove.image _love.image 1love.image xImageData:getPixel (Lota::Image)",
      translate("glove.image _love.image 1love.image xImageData:getPixel (love.image)")
  end

  # A type followed by anything but a colon and a lowercase letter is no
  # method, and the colons of a Ruby name are not taken for one.
  def test_a_type_without_a_method_is_unchanged
    assert_equal "Error: x, ImageData:GetPixel, Lota::Image::ImageData#pixel",
      translate("Error: x, ImageData:GetPixel, Lota::Image::ImageData#pixel")
  end

  def test_a_message_keeps_its_encoding_and_every_byte_that_is_not_a_name
    binary = "love.image \xFF\xFE ImageData:paste".b
    invalid = "love.image \xFF".dup.force_encoding(Encoding::UTF_8)

    assert_equal "Lota::Image \xFF\xFE Lota::Image::ImageData#paste".b, translate(binary)
    assert_equal Encoding::BINARY, translate(binary).encoding
    assert_equal "Lota::Image \xFF".b, translate(invalid).b
    assert_equal Encoding::UTF_8, translate(invalid).encoding
  end

  def test_a_frozen_message_translates_into_a_new_string
    message = "love.image"

    assert_equal "Lota::Image", translate(message)
    assert_equal "love.image", message
  end

  # Every Ractor translates the engine's messages, so the table and the
  # pattern are shareable, and translate keeps no state. The Ractor runs in
  # a Ruby of its own: once a process has made one, ObjectSpace no longer
  # finds the objects other tests count (test/native/
  # physics_callbacks_test.rb).
  def test_the_name_table_is_shareable_and_translates_in_another_ractor
    script = <<~RUBY
      Warning[:experimental] = false
      require #{File.expand_path('../lib/lota/error_message', __dir__).dump}
      print Ractor.new { Lota::ErrorMessage.translate("love.window.setMode in love.graphics.") }.value
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-w", "-e", script)

    assert Ractor.shareable?(Lota::ErrorMessage::NAMES)
    assert Ractor.shareable?(Lota::ErrorMessage::NAME)
    assert_predicate status, :success?, output
    assert_equal "Lota::Window.set_mode in Lota::Graphics.", output
  end
end
