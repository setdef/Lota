# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"

# A controller reaches a game as LÖVE gives it: the joystick callbacks
# receive LÖVE's arguments, the Joystick first, and the same Joystick
# each time, and Lota::Joystick answers from LÖVE's own joystick module.
#
# No test machine has a controller, so each test plugs in a joystick SDL
# makes in software (LotaNativeTest.attach_virtual_joystick), which SDL
# reports as it reports a device, and moves its buttons, axes, and hats
# through SDL; LÖVE's own Event::convert
# (vendor/love/src/modules/event/sdl/Event.cpp:618-757) turns what SDL
# reports into messages.
class JoystickEventsTest < Minitest::Test
  include CallbackHelper
  include NativeHelper

  CALLBACKS = %i[
    joystickadded
    joystickremoved
    joystickpressed
    joystickreleased
    joystickaxis
    joystickhat
    gamepadpressed
    gamepadreleased
    gamepadaxis
  ].freeze

  # SDL drops a joystick's input while no window of the program has
  # keyboard focus, unless background events are on (SDL 3.4.10,
  # src/joystick/SDL_joystick.c, SDL_PrivateJoystickShouldIgnoreEvent),
  # and a test's window never takes focus (EngineHelper), so each test
  # turns them on with LÖVE's own switch, as a game played in the
  # background would.
  def setup
    super
    EngineHelper.open_window
    Lota::Joystick.background_events = true
    @attached = []
    drain
  end

  def teardown
    @attached.each { |id| LotaNativeTest.detach_virtual_joystick(id) }
    drain
    Lota::Joystick.background_events = false
    super
  end

  # Empties the queue, so that a frame handles only what the test did.
  def drain
    Lota::Event.pump
    nil while Lota::Callbacks.poll
  end

  # Records every call of the joystick callbacks, in order, as its name
  # and every argument LÖVE passed, while the block runs and one frame of
  # Lota's loop after it.
  def calls
    received = []
    CALLBACKS.each { |name| define_callback(name) { |*arguments| received << [name, *arguments] } }
    yield
    Lota.run.call
    received
  end

  def attach(gamepad:, name: "Lota test joystick")
    LotaNativeTest.attach_virtual_joystick(gamepad, name).tap { |id| @attached << id }
  end

  def detach(id)
    LotaNativeTest.detach_virtual_joystick(@attached.delete(id))
  end

  # SDL_EVENT_JOYSTICK_ADDED becomes joystickadded with the Joystick LÖVE
  # adds (Event.cpp:714-722), which getJoysticks then lists; it is one
  # object in Ruby, as it is one userdata in Lua, so it keys a Hash.
  def test_a_joystick_plugged_in_is_added_and_listed_as_one_object
    received = calls { attach(gamepad: false) }

    assert_equal [:joystickadded], received.map(&:first)
    joystick = received.first.last
    assert_instance_of Lota::Joystick::Joystick, joystick
    assert_same joystick, Lota::Joystick.joysticks.last
    assert_equal({ joystick => 1 }, { Lota::Joystick.joysticks.last => 1 })
    assert_equal Lota::Joystick.joysticks.size, Lota::Joystick.joystick_count
    assert_equal "Lota test joystick", joystick.name
    assert_match(/\A\h{32}\z/, joystick.guid)
    assert_equal [2, 4, 1], [joystick.axis_count, joystick.button_count, joystick.hat_count]
    assert_predicate joystick, :connected?
    refute_predicate joystick, :gamepad?
    assert_equal Lota::Joystick.joysticks.size, joystick.connected_index
    assert_equal "Joystick", joystick.type
  end

  # A button counts from 1 in LÖVE (Event.cpp:638-649), an axis too, with
  # its value SDL's divided by 32768 (lines 650-662), and a hat names its
  # direction (lines 663-675).
  def test_a_joysticks_buttons_axes_and_hats_reach_the_callbacks
    id = attach(gamepad: false)
    Lota.run.call
    joystick = Lota::Joystick.joysticks.last

    received = calls do
      LotaNativeTest.set_virtual_button(id, 1, true)
      LotaNativeTest.set_virtual_axis(id, 0, 16_384)
      LotaNativeTest.set_virtual_hat(id, 0, 1)
    end

    assert_includes received, [:joystickpressed, joystick, 2]
    assert_includes received, [:joystickaxis, joystick, 1, 0.5]
    assert_includes received, [:joystickhat, joystick, 1, :u]
    assert joystick.down?(2)
    assert joystick.down?([1, 2])
    refute joystick.down?(1)
    assert_in_delta 0.5, joystick.axis(1)
    assert_equal [0.5, 0.0], joystick.axes
    assert_equal :u, joystick.hat(1)

    received = calls { LotaNativeTest.set_virtual_button(id, 1, false) }
    assert_equal [[:joystickreleased, joystick, 2]], received
  end

  # A gamepad's button and axis also arrive by their gamepad names
  # (Event.cpp:676-713), after the joystick's own.
  def test_a_gamepad_reaches_the_gamepad_callbacks_by_name
    id = attach(gamepad: true, name: "Lota test gamepad")
    Lota.run.call
    joystick = Lota::Joystick.joysticks.last

    received = calls do
      LotaNativeTest.set_virtual_button(id, 0, true)
      LotaNativeTest.set_virtual_axis(id, 0, -32_768)
    end

    assert_includes received, [:gamepadpressed, joystick, :a]
    assert_includes received, [:gamepadaxis, joystick, :leftx, -1.0]
    assert_includes received, [:joystickpressed, joystick, 1]
    assert_predicate joystick, :gamepad?
    assert joystick.gamepad_down?(:a)
    assert joystick.gamepad_down?(%i[b a])
    refute joystick.gamepad_down?(:b)
    assert_in_delta(-1.0, joystick.gamepad_axis(:leftx))
    assert_equal [:button, 1], joystick.gamepad_mapping(:a)
    assert_equal [:axis, 1], joystick.gamepad_mapping(:leftx)
    assert_includes joystick.gamepad_mapping_string, "a:b0"
    assert_equal :gamepad, joystick.joystick_type
  end

  # SDL_EVENT_JOYSTICK_REMOVED becomes joystickremoved with the same
  # Joystick (Event.cpp:723-732), which then says it is disconnected.
  def test_a_joystick_unplugged_is_removed_as_the_same_object
    id = attach(gamepad: false)
    Lota.run.call
    joystick = Lota::Joystick.joysticks.last

    received = calls { detach(id) }

    assert_equal [[:joystickremoved, joystick]], received
    refute_predicate joystick, :connected?
    assert_nil joystick.connected_index
    refute_includes Lota::Joystick.joysticks, joystick
  end

  # The test's joysticks have motors that refuse every request, so
  # setVibration returns false rather than raising, passing on what SDL
  # answers (rule 7 of doc/contributors/design/translation.md;
  # joystick/sdl/Joystick.cpp:495-528). Stopping motors that are not running
  # asks the device nothing, and SDL answers true (src/joystick/SDL_joystick.c,
  # SDL_RumbleJoystick). getVibration, which LÖVE 12 deprecated, returns zeros
  # (lines 530-535).
  def test_vibration_returns_whether_the_device_took_it
    attach(gamepad: true)
    Lota.run.call
    joystick = Lota::Joystick.joysticks.last

    assert_predicate joystick, :vibration_supported?
    refute joystick.set_vibration(1, 1, 0.5)
    assert joystick.set_vibration
    assert_equal [0.0, 0.0], joystick.vibration
  end

  # setPlayerIndex and getPlayerIndex count from 1 (wrap_Joystick.cpp:
  # 184-198).
  def test_the_player_index_counts_from_1
    attach(gamepad: true)
    Lota.run.call
    joystick = Lota::Joystick.joysticks.last

    joystick.player_index = 2
    assert_equal 2, joystick.player_index
  end

  # The Joystick methods check their names as LÖVE does, and isDown and
  # isGamepadDown raise when given nothing (wrap_Joystick.cpp:152-275).
  def test_a_joystick_refuses_what_love_refuses
    attach(gamepad: true)
    Lota.run.call
    joystick = Lota::Joystick.joysticks.last

    assert_equal "Invalid gamepad axis: up", assert_raises(ArgumentError) { joystick.gamepad_axis(:up) }.message
    assert_equal "Invalid gamepad button: up", assert_raises(ArgumentError) { joystick.gamepad_down?(:up) }.message
    assert_equal "Invalid gamepad axis/button: up",
      assert_raises(ArgumentError) { joystick.gamepad_mapping(:up) }.message
    assert_raises(ArgumentError) { joystick.down? }
    assert_raises(ArgumentError) { joystick.gamepad_down? }
    error = assert_raises(ArgumentError) { joystick.sensor?(:compass) }
    assert_equal "Invalid sensor type 'compass', expected one of: 'accelerometer', 'gyroscope'", error.message
  end

  # A gamepad mapping set for a GUID applies to every controller with it,
  # and saveGamepadMappings lists it (wrap_JoystickModule.cpp:80-184).
  def test_a_gamepad_mapping_is_set_read_and_saved_by_guid
    guid = "030000005e040000130b000011050000"

    assert Lota::Joystick.set_gamepad_mapping(guid, :a, :button, 1)
    assert Lota::Joystick.set_gamepad_mapping(guid, :dpup, :hat, 1, :u)
    assert Lota::Joystick.set_gamepad_mapping(guid, :leftx, :axis, 1)
    mapping = Lota::Joystick.gamepad_mapping_string(guid)
    assert_includes mapping, "a:b0"
    assert_includes mapping, "dpup:h0.1"
    assert_includes mapping, "leftx:a0"
    assert_includes Lota::Joystick.save_gamepad_mappings, guid
    error = assert_raises(RuntimeError) { Lota::Joystick.set_gamepad_mapping("faker", :a, :button, 1) }
    assert_equal "Invalid joystick GUID: faker", error.message
    assert_nil Lota::Joystick.gamepad_mapping_string("faker")
  end

  def test_set_gamepad_mapping_checks_its_names_in_loves_order
    guid = "030000005e040000130b000011050000"

    assert_equal "Invalid gamepad axis/button: up",
      assert_raises(ArgumentError) { Lota::Joystick.set_gamepad_mapping(guid, :up, :wheel, 1) }.message
    assert_equal "Invalid joystick input type: wheel",
      assert_raises(ArgumentError) { Lota::Joystick.set_gamepad_mapping(guid, :a, :wheel, 1) }.message
    assert_equal "Invalid joystick hat: up",
      assert_raises(ArgumentError) { Lota::Joystick.set_gamepad_mapping(guid, :a, :hat, 1, :up) }.message
    assert_raises(ArgumentError) { Lota::Joystick.set_gamepad_mapping(guid, :a, :hat, 1) }
  end

  # loadGamepadMappings reads a file LÖVE's filesystem finds, and
  # otherwise takes its argument as the mappings (wrap_JoystickModule.cpp:
  # 131-154), skipping comments and another platform's mappings
  # (joystick/sdl/JoystickModule.cpp:411-460), and raising when none of
  # them is one.
  def test_gamepad_mappings_load_from_a_string_or_a_file
    Lota::Joystick.load_gamepad_mappings("# a comment\n03000000123400005678000000000000,Lota pad one,a:b0,b:b1,\n")
    assert_includes Lota::Joystick.gamepad_mapping_string("03000000123400005678000000000000"), "Lota pad one"

    Lota::Filesystem.write("lota-mappings.txt", "03000000123400005678000001000000,Lota pad two,a:b1,\n")
    Lota::Joystick.load_gamepad_mappings("lota-mappings.txt")
    assert_includes Lota::Joystick.gamepad_mapping_string("03000000123400005678000001000000"), "Lota pad two"

    error = assert_raises(RuntimeError) { Lota::Joystick.load_gamepad_mappings("fakefile.txt") }
    assert_equal "Invalid gamepad mappings.", error.message
  ensure
    Lota::Filesystem.remove("lota-mappings.txt")
  end

  # A game that polls the joysticks each frame and keeps none of them
  # drops each frame's wrappers, and the collector finds them dead in
  # some frame and frees them in a later one. getJoysticks must not hand
  # a frame a wrapper the collector has found dead: it would be freed
  # while the frame uses it.
  def test_joysticks_never_returns_a_wrapper_the_collector_found_dead
    attach(gamepad: true)
    Lota.run.call

    assert_never_reads_back_a_dead_wrapper { Lota::Native::Joystick.joysticks.last }
  end

  def test_lota_joystick_is_the_module
    assert_same Lota::Joystick, lota.joystick
  end
end
