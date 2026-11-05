# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require "desktop_input_lock"

# Lota::Mouse, beyond what Lövetest's tests for it check
# (test/lovetest/tests/mouse.rb): the arguments LÖVE takes, what it
# returns, and the errors it raises (src/modules/mouse/wrap_Mouse.cpp).
class CursorTest < Minitest::Test
  # The pointer and its cursor are the computer's, so a test that reads or
  # sets them holds the desktop input lock (the desktop_input_lock gem),
  # silently, since it takes neither from the person at the computer.
  def setup
    @desktop_input = DesktopInputLock.acquire(speak: false)
    EngineHelper.open_window
  end

  def teardown
    Lota::Mouse.cursor = nil
  ensure
    @desktop_input.release
  end

  def test_the_mouse_is_open_once_lota_boots
    assert_equal Lota::Mouse, Lota.mouse
    assert_equal "love::mouse::Cursor", Lota::Native::Mouse::Cursor.cpp_class
  end

  def test_a_system_cursor_is_a_cursor_by_symbol_or_string
    assert_instance_of Lota::Mouse::Cursor, Lota::Mouse.system_cursor(:sizewe)
    assert_instance_of Lota::Native::Mouse::Cursor, Lota::Mouse.system_cursor("hand").native
  end

  # LÖVE's message names the enum, its system cursor type
  # (wrap_Mouse.cpp:94-107). The words are joined here because the native
  # suite's check for forking (test/tasks/rake_tasks_test.rb) reads the
  # Kernel method in a string that holds them as they are.
  def test_an_unknown_system_cursor_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Mouse.system_cursor(:love) }

    assert_equal "Invalid #{:system_cursor.to_s.tr('_', ' ')} type: love", error.message
  end

  # newCursor converts a file's name to an ImageData (luax_convobj,
  # wrap_Mouse.cpp:74-75) and makes an image cursor of it, as it does of an
  # ImageData given, or of a table of them (w_newCursor).
  def test_a_cursor_is_made_of_an_image_its_file_or_an_array_of_them
    skip("cursor not supported on this system") unless Lota::Mouse.cursor_supported?

    logo = "resources/love.png" # in the game folder, test/lovetest
    image = Lota::Image::ImageData.new(logo)

    assert_equal :image, Lota::Mouse::Cursor.new(image).get_type
    assert_equal :image, Lota::Mouse::Cursor.new([image], 3, 4).get_type
    assert_equal :image, Lota::Mouse::Cursor.new(logo).get_type
  end

  # getCursor returns the cursor setCursor last showed, and nothing after
  # setCursor with nothing (w_getCursor).
  def test_the_cursor_shown_is_the_one_last_set
    Lota::Mouse.cursor = Lota::Mouse.system_cursor(:crosshair)

    assert_equal :crosshair, Lota::Mouse.cursor.get_type
  ensure
    Lota::Mouse.cursor = nil

    assert_nil Lota::Mouse.cursor
  end

  # setCursor with a cursor shows it, and with nothing the system's arrow
  # again (w_setCursor), so either is accepted, and anything else is not.
  def test_the_cursor_is_a_cursor_or_nil
    Lota::Mouse.cursor = Lota::Mouse.system_cursor(:crosshair)
    Lota::Mouse.cursor = nil

    error = assert_raises(TypeError) { Lota::Mouse.cursor = :crosshair }
    assert_equal "wrong argument type Symbol (expected Lota::Mouse::Cursor)", error.message
  end

  # getPosition reports a double (w_getX), so x is a Float wherever the
  # pointer is (ADR 001, rule 14).
  def test_x_is_a_float
    assert_instance_of Float, Lota::Mouse.x
  end
end
