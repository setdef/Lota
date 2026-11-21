# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
# SPDX-License-Identifier: Zlib
#
# LÖVE's wrap functions read a boolean argument in three ways
# (src/common/runtime.cpp:254-275): luax_toboolean takes any value's
# truth, luax_checkboolean raises for anything but true or false, nil
# included, and luax_optboolean takes its default for anything but true
# or false. The generated bindings read each as LÖVE does, in every
# module; these check a few of each kind through Lota's own methods.
class BooleanArgumentsTest < Minitest::Test
  Physics = Lota::Physics

  def setup
    EngineHelper.open_window
  end

  def assert_refused(value, &)
    error = assert_raises(TypeError, &)

    assert_equal "wrong argument type #{value.class} (expected true or false)", error.message
  end

  # w_setVisible and w_setKeyRepeat (wrap_Mouse.cpp:230-235,
  # wrap_Keyboard.cpp:34-38) read their flags with luax_checkboolean.
  def test_an_input_setting_takes_only_true_or_false
    Lota::Mouse.visible = true
    Lota::Keyboard.key_repeat = true

    [nil, 1, "yes"].each do |value|
      assert_refused(value) { Lota::Mouse.visible = value }
      assert_refused(value) { Lota::Keyboard.key_repeat = value }
    end

    assert_predicate Lota::Mouse, :visible?
    assert_predicate Lota::Keyboard, :key_repeat?
  ensure
    Lota::Keyboard.key_repeat = false
  end

  # w_Body_setBullet, w_Shape_setSensor, and w_World_setSleepingAllowed
  # (wrap_Body.cpp:525-531, wrap_Shape.cpp:116-122, wrap_World.cpp:
  # 111-117) read theirs with luax_checkboolean too.
  def test_a_physics_flag_takes_only_true_or_false
    world = Physics::World.new(0, 0, false)
    body = Physics::Body.new(world, 0, 0, :dynamic)
    shape = Physics::CircleShape.new(body, 5)

    [nil, 0].each do |value|
      assert_refused(value) { body.bullet = value }
      assert_refused(value) { shape.sensor = value }
      assert_refused(value) { world.sleeping_allowed = value }
    end

    refute_predicate body, :bullet?
    refute_predicate shape, :sensor?
    refute_predicate world, :sleeping_allowed?
  ensure
    world&.destroy
  end

  # w_newWorld reads whether bodies may sleep with luax_optboolean(L, 3,
  # true) (wrap_Physics.cpp:53-65), so nil leaves them allowed to, as
  # leaving it out does.
  def test_a_world_given_nil_for_sleep_lets_bodies_sleep
    world = Physics::World.new(0, 0, nil)

    assert_predicate world, :sleeping_allowed?
  ensure
    world&.destroy
  end

  # w_setDepthMode reads the compare mode's name, then the write flag
  # with luax_checkboolean, and only then looks the name up
  # (wrap_Graphics.cpp:2884-2901), so a flag that is not true or false is
  # reported before an unknown name.
  def test_a_depth_mode_checks_its_write_flag_before_its_compare_mode
    before = Lota::Graphics.depth_mode

    assert_refused(1) { Lota::Graphics.depth_mode = :sometimes, 1 }
    assert_equal before, Lota::Graphics.depth_mode
  end
end
# SPDX-SnippetEnd
