# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's love.physics tests, translated in tests/physics.rb, in
# the test suite's own process.
require_relative "../test_helper"
require_relative "tests/physics"

# love.test.physics.setMeter ends with the meter at 10 (vendor/love/testing/
# tests/physics.lua:829-839). PhysicsTest ends each test with LÖVE's
# default, 30, so that a suite run after it, in the same process, scales
# its bodies by the default. Without that, this fails with 10.
class PhysicsMeterTest < Minitest::Test
  def test_a_physics_test_leaves_the_meter_at_the_default
    EngineHelper.open_window
    Lota::Physics.meter = 30

    assert_predicate PhysicsTest.new("test_set_meter").run, :passed?

    assert_equal 30, Lota::Physics.meter
  ensure
    Lota::Physics.meter = 30
  end
end
