# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    Lota::Window.vsync = 1
  end

  # A window that does not fill the screen is safe all over: SDL insets
  # its safe area only where the system covers part of it, which on a Mac
  # is the camera's notch over a fullscreen window (SDL 3.4.10,
  # src/video/cocoa/SDL_cocoawindow.m, Cocoa_SetWindowFullscreen, from
  # NSScreen's safeAreaInsets) and on X11 never, and otherwise answers the
  # whole window (src/video/SDL_video.c, SDL_GetWindowSafeArea). LÖVE
  # gives it in the units Lota::Graphics draws in (Window::getSafeArea,
  # src/modules/window/sdl/Window.cpp:1022-1040), so the menu bar, which
  # is outside the window, takes nothing from it.
  def test_a_window_that_does_not_fill_the_screen_is_safe_all_over
    assert_equal [0, 0, *Lota::Graphics.dimensions], Lota::Window.safe_area
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
  # height, and refresh rate, which rule 10 makes frozen FullscreenModes that
  # also answer brackets.
  def test_the_fullscreen_modes_are_frozen_records
    modes = Lota::Window.fullscreen_modes

    refute_empty modes
    mode = modes.first
    assert_instance_of Lota::Window::FullscreenMode, mode
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
  def test_vsync_is_an_integer_that_a_boolean_sets
    assert_vsync(0) { Lota::Window.vsync = false }
    assert_vsync(1) { Lota::Window.vsync = true }
    assert_vsync(0) { Lota::Window.vsync = 0.0 }

    error = assert_raises(TypeError) { Lota::Window.vsync = "1" }
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
  # which rule 6 puts in the Array. Waiting is the default, so the window
  # is where it was sent at once. Without the wait, a system that moves
  # windows later, as X11 does, reports the move in an event, which SDL
  # reads into the position only as the events are pumped (SDL 3.4.10,
  # src/video/x11/SDL_x11window.c, X11_UpdateWindowPosition, and
  # src/events/SDL_windowevents.c, SDL_EVENT_WINDOW_MOVED).
  def test_the_position_takes_a_display_and_whether_to_wait
    x, y, display = Lota::Window.position
    assert_kind_of Integer, x
    assert_kind_of Integer, y
    assert_equal 1, display

    Lota::Window.position = 120, 130
    assert_equal [120, 130, 1], Lota::Window.position
    Lota::Window.position = 140, 150, nil, false
    pump_until { Lota::Window.position == [140, 150, 1] }
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
  # the system does with the request. This shows only that the call
  # reaches the engine and returns nil: nothing a test can read shows
  # whether the system was asked, or whether +false+ reached it.
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

  # love.window.getPointer gives the address of SDL's window
  # (wrap_Window.cpp:766-770, Window::getHandle), which Lota gives as a
  # Fiddle::Pointer: the window SDL itself lists.
  def test_pointer_points_at_sdls_window
    pointer = Lota::Window.pointer

    assert_instance_of Fiddle::Pointer, pointer
    refute_predicate pointer, :null?
    assert_equal LotaNativeTest.window_address, pointer.to_i
  end

  # Asserts that the block's request for vsync reached the system, which
  # keeps it, so that vsync answers +expected+, or refuses it and says
  # why. LÖVE's Window::setVSync ignores a refusal, and its getVSync
  # answers what SDL keeps instead (src/modules/window/sdl/Window.cpp,
  # lines 1094-1135): Mesa's software GLX, on a display without DRI as
  # Xvfb is, offers no swap control (Mesa 23.2, src/glx/drisw_glx.c, lines
  # 864-871), so SDL refuses every interval and answers 0 (SDL 3.4.10,
  # src/video/x11/SDL_x11opengl.c, lines 961-1008 and 1099-1102).
  #
  # Where SDL refuses, this checks only that vsync answers what SDL
  # keeps, so a binding that passed 0 for +true+ would pass there. SDL's
  # refusal reads the same for 0 and 1 and keeps neither, so nothing in the
  # process can tell which the binding passed short of replacing SDL's
  # function, which the tests do not do. The check of the value itself is
  # macOS's, and any driver's that keeps the interval, where the first
  # branch runs.
  private def assert_vsync(expected)
    LotaNativeTest.clear_sdl_error
    yield
    refusal = LotaNativeTest.sdl_error
    if refusal.empty?
      assert_equal expected, Lota::Window.vsync
    else
      assert_equal LotaNativeTest.swap_interval, Lota::Window.vsync, refusal
    end
  end

  # Pumps the system's events, and drops them, until the block is true or
  # ten seconds have passed.
  private def pump_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Lota::Event.pump
      Lota::Event.clear
      sleep 0.01
    end
  end
end
