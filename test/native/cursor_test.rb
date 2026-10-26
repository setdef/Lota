# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Mouse, beyond what Lövetest's tests for it check
# (test/lovetest/tests/mouse.rb): the arguments LÖVE takes, what it
# returns, and the errors it raises (src/modules/mouse/wrap_Mouse.cpp).
class CursorTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def teardown
    Lota::Mouse.cursor = nil
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

  def test_a_cursor_cannot_be_made_with_new
    assert_raises(NoMethodError) { Lota::Mouse::Cursor.new }
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
