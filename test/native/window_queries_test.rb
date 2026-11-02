# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Window's queries and settings, beyond what Lövetest's tests for
# them check (test/lovetest/tests/window.rb): what they return, in which
# form (ADR 001, rules 4, 9, and 10), and what they raise
# (src/modules/window/wrap_Window.cpp). None of them takes the keyboard
# or the pointer, or fills the screen.
class WindowQueriesTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # Puts back what a test may have changed.
  def teardown
    Lota::Window.set_fullscreen(false, :desktop)
    Lota::Window.v_sync = 1
  end

  def test_the_displays_are_counted_and_named_from_1
    assert_kind_of Integer, Lota::Window.display_count
    assert_operator Lota::Window.display_count, :>=, 1
    name = Lota::Window.display_name(1)
    assert_equal Encoding::UTF_8, name.encoding
    refute_empty name
  end

  # DisplayName raises for a display that is not connected
  # (SDL's Window::getDisplayName).
  def test_a_display_that_is_not_connected_has_no_name
    error = assert_raises(RuntimeError) { Lota::Window.display_name(99) }

    assert_equal "Invalid display index: 99", error.message
  end

  # w_getDisplayOrientation (wrap_Window.cpp:253-270) names the
  # orientation, which is a Symbol (rule 9), and asks the window's own
  # display when it is given none.
  def test_a_displays_orientation_is_a_symbol_and_the_windows_own_by_default
    orientation = Lota::Window.display_orientation

    assert_includes %i[unknown landscape landscapeflipped portrait portraitflipped], orientation
    assert_equal orientation, Lota::Window.display_orientation(Lota::Window.position.last)
  end

  # w_getFullscreenModes (wrap_Window.cpp:272-309) lists tables of width,
  # height, and refresh rate, which rule 10 makes frozen DisplayModes that
  # also answer brackets.
  def test_the_fullscreen_modes_are_frozen_records
    modes = Lota::Window.fullscreen_modes

    refute_empty modes
    mode = modes.first
    assert_instance_of Lota::Window::DisplayMode, mode
    assert_predicate mode, :frozen?
    assert_kind_of Integer, mode.width
    assert_kind_of Integer, mode.height
    assert_kind_of Float, mode.refreshrate
    assert_equal mode.width, mode[:width]
    assert_equal modes, Lota::Window.fullscreen_modes(Lota::Window.position.last)
  end

  # w_getFullscreen (wrap_Window.cpp:332-345) returns the flag and the
  # name of the type, a Symbol (rules 4 and 9), and that type is the one
  # the window will use, so it is set while the window is not fullscreen.
  def test_fullscreen_is_the_flag_and_the_type
    assert_equal [false, :desktop], Lota::Window.fullscreen
    assert Lota::Window.set_fullscreen(false, :exclusive)
    assert_equal [false, :exclusive], Lota::Window.fullscreen
    assert Lota::Window.set_fullscreen(false, "desktop")
    assert_equal [false, :desktop], Lota::Window.fullscreen
  end

  # w_setFullscreen (wrap_Window.cpp:311-330) names the types it knows
  # when it is given one it does not.
  def test_an_unknown_fullscreen_type_raises
    error = assert_raises(ArgumentError) { Lota::Window.set_fullscreen(true, :sideways) }

    assert_match(/\AInvalid fullscreen type 'sideways', expected one of: '(desktop|exclusive)', '(desktop|exclusive)'\z/,
      error.message)
    assert_equal [false, :desktop], Lota::Window.fullscreen
  end

  # w_setVSync (wrap_Window.cpp:434-443) reads a boolean as 1 or 0 and
  # otherwise needs an integer. The system decides whether it can wait
  # unless a frame is late (-1), so only 0 and 1 are checked.
  def test_v_sync_is_an_integer_that_a_boolean_sets
    Lota::Window.v_sync = false
    assert_equal 0, Lota::Window.v_sync
    Lota::Window.v_sync = true
    assert_equal 1, Lota::Window.v_sync
    Lota::Window.v_sync = 0.0
    assert_equal 0, Lota::Window.v_sync

    error = assert_raises(TypeError) { Lota::Window.v_sync = "1" }
    assert_equal "wrong argument type String for vsync (expected Integer, true, or false)", error.message
  end

  # w_toPixels and w_fromPixels (wrap_Window.cpp:512-552) convert one
  # number to one, and a position to two, which rule 4 returns as an Array.
  def test_pixels_convert_a_length_or_a_position
    dpi = Lota::Window.dpi_scale

    assert_instance_of Float, Lota::Window.to_pixels(50)
    assert_equal [50 * dpi, 20 * dpi], Lota::Window.to_pixels(50, 20)
    assert_equal 50.0, Lota::Window.from_pixels(Lota::Window.to_pixels(50))
    assert_equal [50.0, 20.0], Lota::Window.from_pixels(*Lota::Window.to_pixels(50, 20))
    assert_operator Lota::Window.native_dpi_scale, :>, 0
  end

  # w_setPosition (wrap_Window.cpp:377-394) takes the display and whether
  # to wait for the system as its third and fourth values, both optional,
  # which rule 6 puts in the Array.
  def test_the_position_takes_a_display_and_whether_to_wait
    x, y, display = Lota::Window.position
    assert_kind_of Integer, x
    assert_kind_of Integer, y
    assert_equal 1, display

    Lota::Window.position = 120, 130
    assert_equal [120, 130, 1], Lota::Window.position
    Lota::Window.position = 140, 150, nil, false
    assert_equal [140, 150, 1], Lota::Window.position
  ensure
    Lota::Window.position = x, y, display
  end

  # w_setIcon (wrap_Window.cpp:418-425) checks its argument is an
  # ImageData before it stores anything. The test sets no icon of its
  # own, which Lövetest's getIcon test needs unset
  # (test/lovetest/tests/window.rb).
  def test_an_icon_is_an_image_data
    error = assert_raises(TypeError) { Lota::Window.set_icon("icon.png") }

    assert_equal "wrong argument type String (expected Lota::Image::ImageData)", error.message
  end

  def test_the_system_theme_is_a_symbol
    assert_includes %i[unknown light dark], Lota::Window.system_theme
  end

  def test_the_queries_answer_true_or_false
    %i[focus? mouse_focus? visible? occluded? maximized? minimized? display_sleep_enabled?].each do |query|
      assert_includes [true, false], Lota::Window.public_send(query), query.to_s
    end
  end

  # w_requestAttention (wrap_Window.cpp:759-764) returns nothing, whatever
  # the system does with the request.
  def test_attention_can_be_requested
    assert_nil Lota::Window.request_attention
    assert_nil Lota::Window.request_attention(false)
  end

  # w_showMessageBox (wrap_Window.cpp:590-653) checks its arguments
  # before it shows anything.
  def test_a_message_box_checks_its_arguments_before_it_shows
    error = assert_raises(ArgumentError) { Lota::Window.show_message_box("Title", "Message", []) }
    assert_equal "Must have at least one messagebox button.", error.message

    error = assert_raises(ArgumentError) { Lota::Window.show_message_box("Title", "Message", :fatal) }
    assert_match(/\AInvalid messagebox type 'fatal', expected one of: '\w+', '\w+', '\w+'\z/, error.message)

    error = assert_raises(ArgumentError) { Lota::Window.show_message_box("Title", "Message", %w[A], :fatal) }
    assert_match(/\AInvalid messagebox type 'fatal'/, error.message)

    error = assert_raises(ArgumentError) { Lota::Window.show_message_box("Title", "Message", :info, true, enterbutton: 1) }
    assert_equal "enterbutton and escapebutton need an Array of buttons", error.message

    assert_raises(ArgumentError) { Lota::Window.show_message_box("Title", "Message", :info, true, true) }
    assert_raises(ArgumentError) { Lota::Window.show_message_box("Title", "Message", %w[A], :info, true, true) }
  end
end
