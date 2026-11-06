# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"

# A finger on a touchscreen reaches a game as LÖVE gives it: the touch
# callbacks receive LÖVE's eight arguments in the order SDL reported the
# finger, Lota::Touch answers from the list LÖVE's event module keeps, and
# the mouse events SDL makes of a touch say so in their istouch argument.
#
# No test can touch a screen, so each pushes into SDL's queue the events
# SDL's own touch code would send (LotaNativeTest.push_finger and
# push_touch_mouse), and LÖVE's own Event::convert
# (vendor/love/src/modules/event/sdl/Event.cpp:330-441) turns them into
# messages, as it turns the system's. The window is the one Lövetest's
# conf.lua asks for, without DPI scaling (test/lovetest/conf.rb), so its
# units are pixels; test/native/lota_run_test.rb runs a game with high
# DPI on.
class TouchEventsTest < Minitest::Test
  include CallbackHelper

  # SDL's phases of a finger, as LotaNativeTest.push_finger names them.
  DOWN = "down"
  MOTION = "motion"
  UP = "up"
  CANCELED = "canceled"

  def setup
    super
    EngineHelper.open_window
    drain
  end

  def teardown
    LotaNativeTest.push_finger(UP, 7, [0.5, 0.5, 0, 0, 1])
    drain
    super
  end

  # Empties the queue of what the system reported before the test, so
  # that a frame handles only what the test pushed.
  def drain
    Lota::Event.pump
    nil while Lota::Callbacks.poll
  end

  # Records every call of each of +callbacks+, in order, as its name and
  # every argument LÖVE passed, while the block runs and one frame of
  # Lota's loop after it.
  def calls(*callbacks)
    received = []
    callbacks.each { |name| define_callback(name) { |*arguments| received << [name, *arguments] } }
    yield
    Lota.run.call
    received
  end

  # A finger lands at a quarter of the window's width and half its height,
  # moves, and lifts. LÖVE turns SDL's position across the window into the
  # window's coordinates, scaled as graphics draws, for a touchscreen
  # (normalizedToDPICoords, Event.cpp:62-77 and 406-411), and its motion
  # too; the id is SDL's finger id, which LÖVE passes as a light userdata
  # and Lota as the Integer it holds.
  def test_a_finger_reaches_the_touch_callbacks_with_loves_arguments_in_order
    width, height = Lota::Graphics.dimensions
    received = calls(:touchpressed, :touchmoved, :touchreleased) do
      LotaNativeTest.push_finger(DOWN, 7, [0.25, 0.5, 0, 0, 0.75])
      LotaNativeTest.push_finger(MOTION, 7, [0.5, 0.75, 0.25, 0.25, 0.5])
      LotaNativeTest.push_finger(UP, 7, [0.5, 0.75, 0, 0, 0])
    end

    assert_equal [
      [:touchpressed, 7, width * 0.25, height * 0.5, 0.0, 0.0, 0.75, :touchscreen, false],
      [:touchmoved, 7, width * 0.5, height * 0.75, width * 0.25, height * 0.25, 0.5, :touchscreen, false],
      [:touchreleased, 7, width * 0.5, height * 0.75, 0.0, 0.0, 0.0, :touchscreen, false],
    ], received
    assert_instance_of Integer, received.first[1]
  end

  # A touch's position and a mouse's at the same point of the window are
  # the same numbers, in the units of Lota::Graphics.width, which is what
  # a game that handles both compares them with.
  def test_a_touch_and_a_mouse_at_one_point_have_one_position
    window_width, window_height = LotaNativeTest.window_size
    received = calls(:touchpressed, :mousepressed) do
      LotaNativeTest.push_finger(DOWN, 7, [0.25, 0.5, 0, 0, 1])
      LotaNativeTest.push_mouse_click(true, [window_width * 0.25, window_height * 0.5])
    end
    LotaNativeTest.push_mouse_click(false, [0, 0])

    _, _, touch_x, touch_y = received.assoc(:touchpressed)
    _, mouse_x, mouse_y = received.assoc(:mousepressed)
    assert_equal [mouse_x, mouse_y], [touch_x, touch_y]
    assert_equal [Lota::Graphics.width * 0.25, Lota::Graphics.height * 0.5], [touch_x, touch_y]
  end

  # While the finger is down, love.touch lists it and answers for it from
  # the event module's list (touch/sdl/Touch.cpp:47-97); once it lifts,
  # LÖVE raises for its id.
  def test_lota_touch_answers_for_a_finger_while_it_is_down
    LotaNativeTest.push_finger(DOWN, 7, [0.25, 0.5, 0, 0, 0.75])
    Lota.run.call

    assert_equal [7], Lota::Touch.touches
    assert_equal [7], Lota::Touch.touches(:touchscreen)
    assert_empty Lota::Touch.touches(:touchpad)
    assert_equal [Lota::Graphics.width * 0.25, Lota::Graphics.height * 0.5], Lota::Touch.position(7)
    assert_in_delta 0.75, Lota::Touch.pressure(7)
    assert_equal :touchscreen, Lota::Touch.device_type(7)
    refute Lota::Touch.mouse?(7)

    LotaNativeTest.push_finger(UP, 7, [0.25, 0.5, 0, 0, 0])
    Lota.run.call

    assert_empty Lota::Touch.touches
    error = assert_raises(RuntimeError) { Lota::Touch.position(7) }
    assert_equal "Invalid active touch ID: 7", error.message
  end

  # Two fingers are listed in the order they landed, each with its own
  # position.
  def test_two_fingers_are_listed_in_the_order_they_landed
    LotaNativeTest.push_finger(DOWN, 9, [0.75, 0.25, 0, 0, 1])
    LotaNativeTest.push_finger(DOWN, 7, [0.25, 0.75, 0, 0, 1])
    Lota.run.call

    assert_equal [9, 7], Lota::Touch.touches
    assert_equal [Lota::Graphics.width * 0.75, Lota::Graphics.height * 0.25], Lota::Touch.position(9)
  ensure
    LotaNativeTest.push_finger(UP, 9, [0, 0, 0, 0, 0])
  end

  # LÖVE's Event::convert has no case for SDL_EVENT_FINGER_CANCELED, the
  # event iOS sends when the system takes a touch for a gesture of its own
  # (Event.cpp:394-441), so a cancelled finger calls no callback and stays
  # in love.touch's list until a finger with its id lifts. Lota matches
  # LÖVE (doc/contributors/upstream/006.md).
  def test_a_cancelled_finger_stays_down_as_in_love
    received = calls(:touchreleased) do
      LotaNativeTest.push_finger(DOWN, 7, [0.25, 0.5, 0, 0, 1])
      LotaNativeTest.push_finger(CANCELED, 7, [0.25, 0.5, 0, 0, 1])
    end

    assert_empty received
    assert_equal [7], Lota::Touch.touches
  end

  # The mouse events SDL makes of a finger come from SDL_TOUCH_MOUSEID,
  # which LÖVE passes as istouch (Event.cpp:350 and 378).
  def test_the_mouse_events_sdl_makes_of_a_touch_say_istouch
    received = calls(:mousemoved, :mousepressed, :mousereleased) do
      LotaNativeTest.push_touch_mouse(true, [30, 40])
      LotaNativeTest.push_touch_mouse(false, [30, 40])
    end

    assert_equal %i[mousemoved mousepressed mousereleased], received.map(&:first)
    assert_equal [true, true, true], [received[0][5], received[1][4], received[2][4]]
    assert_equal [:mousepressed, 30.0, 40.0, 1, true, 1], received[1]
  end

  # A mouse's own click says it is not a touch, and makes no touch: SDL
  # turns a mouse into touches only while SDL_HINT_MOUSE_TOUCH_EVENTS is
  # on, which it is by default on iOS and Android alone, and then it lists
  # SDL_MOUSE_TOUCHID among its touch devices (SDL 3.4.10,
  # src/events/SDL_mouse.c, SDL_MouseTouchEventsChanged).
  def test_a_mouse_click_is_not_a_touch_on_the_desktop
    received = calls(:mousepressed, :touchpressed) { LotaNativeTest.push_mouse_click(true, [30, 40]) }
    LotaNativeTest.push_mouse_click(false, [30, 40])

    assert_equal [[:mousepressed, 30.0, 40.0, 1, false, 1]], received
    refute_includes LotaNativeTest.touch_devices, (2 ** 64) - 1, "SDL turns no mouse into touches"
  end

  # w_getTouches checks its filter's name (wrap_Touch.cpp:46-53), and
  # luax_checktouchid refuses anything but a touch id (lines 36-42).
  def test_lota_touch_refuses_what_love_touch_refuses
    error = assert_raises(ArgumentError) { Lota::Touch.touches(:screen) }
    assert_equal "Invalid touch device type 'screen', expected one of: 'touchscreen', 'touchpad', " \
      "'touchpadrelative'", error.message
    assert_raises(TypeError) { Lota::Touch.position(7.0) }
    assert_raises(TypeError) { Lota::Touch.pressure("7") }
  end

  def test_lota_touch_is_the_module
    assert_same Lota::Touch, lota.touch
  end
end
