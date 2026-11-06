# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's love.keyboard tests, translated in tests/keyboard.rb, in
# the test suite's own process. test/native/lota_run_test.rb runs them
# again through lota run.
require_relative "../test_helper"
require_relative "tests/keyboard"

# A window opens with text input off: LÖVE turns it on only when a game
# asks (vendor/love/src/modules/keyboard/sdl/Keyboard.cpp:136-145), and
# SDL 3 no longer turns it on for a new window (SDL 3.4.10,
# docs/README-migration.md). KeyboardTest ends each test with it off, so
# that a suite run after it, in the same process, finds it as a game
# starts. Without that, this fails with text input on.
class KeyboardTextInputTest < Minitest::Test
  def test_a_keyboard_test_leaves_text_input_off
    EngineHelper.open_window
    Lota::Keyboard.text_input = false

    assert_predicate KeyboardTest.new("test_set_text_input").run, :passed?

    refute_predicate Lota::Keyboard, :text_input?
  ensure
    Lota::Keyboard.text_input = false
  end
end
