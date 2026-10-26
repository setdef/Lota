# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.keyboard tests (vendor/love/testing/tests/keyboard.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/keyboard_test.rb) and under lota run (test/lovetest/game).
class KeyboardTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.keyboard.isDown
  # (vendor/love/testing/tests/keyboard.lua:45-49): isDown becomes down?
  # (rule 8), and the key's name a symbol (rule 9).
  def test_is_down
    keydown = Lota::Keyboard.down?(:a)
    assert_not_nil(keydown)
  end
  # SPDX-SnippetEnd
end
