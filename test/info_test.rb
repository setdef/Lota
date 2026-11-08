# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# What the engine says about itself, translated from the fields and
# functions of LÖVE's love table (vendor/love/src/modules/love/love.cpp:
# 300-352, 499-510, and 543-614): Lota.version, Lota.version_compatible?,
# the deprecation output, and the version fields. Lövetest checks that the
# version has a number and a codename and that its own version is
# compatible (test/lovetest/tests/lota.rb).
class InfoTest < Minitest::Test
  def setup
    @output = Lota.deprecation_output?
  end

  def teardown
    capture_io { Lota.deprecation_output = @output }
  end

  # The pinned engine's version (vendor/love/src/common/version.h).
  def test_version_is_the_engines_numbers_and_codename
    assert_equal [12, 0, 0, "Bestest Friend"], Lota.version
    assert_equal "12.0", Lota._version
    assert_equal [12, 0, 0, "Bestest Friend"],
      [Lota._version_major, Lota._version_minor, Lota._version_revision, Lota._version_codename]
  end

  # love.isVersionCompatible appends ".0" to a string with fewer than two
  # dots, once, and compares it with each compatible version written the
  # same way (love.cpp:309-352), so "12.0" and "12.0.0" pass and "12" does
  # not; numbers are written major.minor.revision.
  def test_a_version_is_compatible_when_it_is_in_the_list
    assert_equal ["12.0"], Lota._version_compat
    assert Lota.version_compatible?("12.0")
    assert Lota.version_compatible?("12.0.0")
    refute Lota.version_compatible?("12")
    refute Lota.version_compatible?("11.5")
    assert Lota.version_compatible?(12, 0)
    assert Lota.version_compatible?(12, 0, 0)
    assert Lota.version_compatible?(12.0, 0.0)
    refute Lota.version_compatible?(12, 0, 1)
    refute Lota.version_compatible?(11, 5)
  end

  # luaL_optinteger reads a nil revision as one left out, so it is 0.
  def test_a_nil_revision_is_zero
    assert Lota.version_compatible?(12, 0, nil)
  end

  def test_a_version_in_numbers_needs_a_minor
    error = assert_raises(TypeError) { Lota.version_compatible?(12) }

    assert_equal "wrong argument type NilClass (expected Integer)", error.message
  end

  def test_the_os_is_the_systems
    assert_equal Lota::System.os, Lota._os
  end

  # setDeprecationOutputEnabled (deprecation.cpp:48-60): turning output on
  # prints the notice of each name used once so far, also those other tests
  # used while it was off.
  def test_deprecation_output_is_on_or_off
    capture_io { Lota.deprecation_output = true }

    assert_predicate Lota, :deprecation_output?

    capture_io { Lota.deprecation_output = false }

    refute_predicate Lota, :deprecation_output?
    Lota::Deprecation.mark("test.info only while off", :function)
    out, = capture_io { Lota.deprecation_output = true }

    assert_includes out, "Lota - Warning: Using deprecated function test.info only while off\n"
  end

  def test_deprecation_output_takes_a_boolean
    assert_raises(TypeError) { Lota.deprecation_output = 1 }
    assert_equal @output, Lota.deprecation_output?
  end
end
