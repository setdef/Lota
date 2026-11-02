# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.system tests (vendor/love/testing/tests/system.lua),
# translated to Ruby by ADR 001's rules, all ten, two of them skipped as
# Lövetest skips them (openURL and vibrate). Like the graphics tests, they
# run in the test suite's own process (test/lovetest/system_test.rb) and
# under lota run (test/lovetest/game). They replace the clipboard's text,
# as Lövetest's do.
class SystemTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.system.getClipboardText and
  # love.test.system.setClipboardText (vendor/love/testing/tests/
  # system.lua:12-20 and 82-90): setClipboardText becomes the writer
  # clipboard_text= (rule 5), and getClipboardText clipboard_text
  # (rule 3).
  def test_get_clipboard_text
    # ignore if not using window
    return skip("clipboard only available in window mode") if Lovetest::WINDOWMODE == false

    # check clipboard value is set
    Lota::System.clipboard_text = "helloworld"
    assert_equal("helloworld", Lota::System.clipboard_text, "check clipboard match")
  end

  def test_set_clipboard_text
    # ignore if not using window
    return skip("clipboard only available in window mode") if Lovetest::WINDOWMODE == false

    # check value returned is what was set
    Lota::System.clipboard_text = "helloworld"
    assert_equal("helloworld", Lota::System.clipboard_text, "check set text")
  end

  # Translated to Ruby from love.test.system.getOS
  # (vendor/love/testing/tests/system.lua:24-29): getOS becomes os
  # (rule 3), and assertMatch, which looks for the value in a list
  # (classes/TestMethod.lua:151-164), Minitest's assert_includes.
  def test_get_os
    # check os is in documented values
    os = Lota::System.os
    options = ["OS X", "Windows", "Linux", "Android", "iOS"]
    assert_includes(options, os, "check value matches")
  end

  # Translated to Ruby from love.test.system.getPreferredLocales
  # (system.lua:33-37): getPreferredLocales becomes preferred_locales
  # (rule 3), and the Lua table an Array, whose type Lua checks as 'table'.
  def test_get_preferred_locales
    locale = Lota::System.preferred_locales
    assert_not_nil(locale)
    assert_kind_of(Array, locale, "check returns table")
  end

  # Translated to Ruby from love.test.system.getPowerInfo
  # (system.lua:41-53): getPowerInfo becomes power_info (rule 3), its
  # three results an Array (rule 4), and the state a symbol (rule 9).
  # Lua's nil percent and seconds are Ruby's, and assertRange of a value
  # between two bounds is Minitest's assert_includes on the Range of them.
  # A machine that reports a percent or seconds makes one more assertion
  # for each, as in Lövetest (test/native/lota_run_test.rb counts them).
  def test_get_power_info
    # check battery state is one of the documented states
    state, percent, seconds = Lota::System.power_info
    states = [:unknown, :battery, :nobattery, :charging, :charged]
    assert_includes(states, state, "check value matches")
    # if percent/seconds check within expected range
    assert_includes(0..100, percent, "check battery percent within range") unless percent.nil?
    assert_not_nil(seconds) unless seconds.nil?
  end

  # Translated to Ruby from love.test.system.getProcessorCount and
  # love.test.system.getMemorySize (system.lua:57-65): getProcessorCount
  # becomes processor_count and getMemorySize memory_size (rule 3).
  def test_get_processor_count
    assert_not_nil(Lota::System.processor_count) # youd hope right
  end

  def test_get_memory_size
    assert_not_nil(Lota::System.memory_size)
  end

  # Translated to Ruby from love.test.system.hasBackgroundMusic
  # (system.lua:69-71): hasBackgroundMusic becomes background_music?
  # (rule 8).
  def test_has_background_music
    assert_not_nil(Lota::System.background_music?)
  end

  # Translated to Ruby from love.test.system.openURL and
  # love.test.system.vibrate (system.lua:75-78 and 95-97), which Lövetest
  # skips because it cannot tell that they worked. openURL becomes open_url
  # (rule 13).
  def test_open_url
    skip("cant test this worked")
  end

  def test_vibrate
    skip("cant test this worked")
  end
  # SPDX-SnippetEnd
end
