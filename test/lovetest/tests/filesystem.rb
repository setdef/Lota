# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.filesystem tests (vendor/love/testing/tests/
# filesystem.lua), translated to Ruby by ADR 001's rules, for the functions
# Lota binds. Like the graphics tests, they run in the test suite's own
# process (test/lovetest/filesystem_test.rb) and under lota run
# (test/lovetest/game). The rest write files, and so wait for write and
# getInfo, whose results no rule translates yet.
class FilesystemTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.filesystem.getIdentity and
  # love.test.filesystem.setIdentity (vendor/love/testing/tests/
  # filesystem.lua:212-219 and 514-521): getIdentity becomes identity
  # (rule 3), and setIdentity the writer identity= (rule 5).
  def test_get_identity
    # check setting identity matches
    original = Lota::Filesystem.identity
    Lota::Filesystem.identity = "lover"
    assert_equal("lover", Lota::Filesystem.identity, "check identity matches")
    # put back to original value
    Lota::Filesystem.identity = original
  end

  def test_set_identity
    # check setting identity val is returned
    original = Lota::Filesystem.identity
    Lota::Filesystem.identity = "lover"
    assert_equal("lover", Lota::Filesystem.identity, "check indentity value")
    # return value to original
    Lota::Filesystem.identity = original
  end

  # Translated to Ruby from love.test.filesystem.getSaveDirectory
  # (filesystem.lua:273-275): getSaveDirectory becomes save_directory
  # (rule 3).
  def test_get_save_directory
    assert_not_nil(Lota::Filesystem.save_directory)
  end

  # Translated to Ruby from love.test.filesystem.isFused
  # (filesystem.lua:297-300): isFused becomes fused? (rule 8).
  def test_is_fused
    # kinda assuming you'd run the testsuite in a non-fused game
    assert_equal(Lota::Filesystem.fused?, false, "check not fused")
  end
  # SPDX-SnippetEnd
end
