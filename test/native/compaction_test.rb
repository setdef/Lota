# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Ruby's compaction (GC.compact) moves objects to new addresses. Rice
# finds a bound function by the address of the class it was defined on
# (rice/detail/NativeRegistry.hpp) and the wrapper of an engine object by
# that wrapper's address (rice/detail/InstanceRegistry.hpp), so both must
# hold after any compaction a game, or a test, asks for.
class CompactionTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # Moves every object Ruby can move, as no ordinary GC.compact promises
  # to, so what the test checks does not depend on which objects a
  # compaction happened to move.
  def compact_everything
    GC.verify_compaction_references(expand_heap: true, toward: :empty)
  end

  # A module's functions live on its singleton class, which Ruby does not
  # pin as it pins the named module.
  def test_a_module_function_is_found_after_compaction
    compact_everything

    Lota::Physics.meter = 32
    assert_equal 32, Lota::Physics.meter
    assert_kind_of Integer, Lota::Native.queued_releases
  ensure
    Lota::Physics.meter = 30
  end

  # LÖVE pushes one Lua value for each engine object, so the Body read
  # back from its World is the Body made.
  def test_an_engine_object_read_back_after_compaction_is_its_own_wrapper
    world = Lota::Physics::World.new(0, 0, false)
    body = Lota::Physics::Body.new(world, 1, 2, :dynamic)
    compact_everything

    assert_same body, world.bodies.first
    assert_equal [1.0, 2.0], body.position
  end
end
