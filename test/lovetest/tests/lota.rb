# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's tests of the table LÖVE's modules hang from (vendor/love/
# testing/tests/love.lua), translated to Ruby by ADR 001's rules, all six.
# That table is Lota (rule 1). Like the graphics tests, they run in the test suite's own
# process (test/lovetest/lota_test.rb) and under lota run
# (test/lovetest/game).
class LotaModuleTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.love.getVersion
  # (vendor/love/testing/tests/love.lua:13-20): getVersion becomes version
  # (rule 3), its four results an Array (rule 4). Lua's
  # assertGreaterEqual(0, major) checks that major is at least 0.
  def test_get_version
    major, minor, revision, codename = Lota.version
    assert_operator(major, :>=, 0, "check major is number")
    assert_operator(minor, :>=, 0, "check minor is number")
    assert_operator(revision, :>=, 0, "check revision is number")
    assert_true(!codename.nil?, "check has codename")
  end

  # Translated to Ruby from love.test.love.hasDeprecationOutput and
  # love.test.love.setDeprecationOutput (love.lua:23-41): the predicate
  # drops has (rule 8) and the setter becomes a writer (rule 5).
  def test_has_deprecation_output
    enabled = Lota.deprecation_output?
    assert_equal(true, enabled, "check enabled by default")
  end

  def test_set_deprecation_output
    enabled = Lota.deprecation_output?
    assert_equal(true, enabled, "check enabled by default")
    Lota.deprecation_output = false
    assert_equal(false, Lota.deprecation_output?, "check disable")
    Lota.deprecation_output = true
  end

  # Translated to Ruby from love.test.love.isVersionCompatible
  # (love.lua:30-34): isVersionCompatible becomes version_compatible?
  # (rule 8).
  def test_is_version_compatible
    major, minor, revision, = Lota.version
    assert_true(Lota.version_compatible?(major, minor, revision), "check own version")
  end

  # Translated to Ruby from love.test.love.errhand and love.test.love.run
  # (love.lua:44-54), which check that the callbacks love defines for a
  # game to replace exist; Lota defines them on itself (Lota::DefaultCallbacks).
  def test_errhand
    assert_true(Lota.respond_to?(:errhand), "check defined")
  end

  def test_run
    assert_true(Lota.respond_to?(:run), "check defined")
  end
  # SPDX-SnippetEnd
end
