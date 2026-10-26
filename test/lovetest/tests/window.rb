# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.window tests (vendor/love/testing/tests/window.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/window_test.rb) and under lota run (test/lovetest/game).
class WindowTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.window.isOpen
  # (vendor/love/testing/tests/window.lua:209-213): isOpen becomes open?
  # (rule 8).
  def test_is_open
    # check open initially
    assert_true(Lota::Window.open?, "check window open")
    # we check closing in test.window.close
  end
  # SPDX-SnippetEnd
end
