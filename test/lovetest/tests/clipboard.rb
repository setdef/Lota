# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.system tests (vendor/love/testing/tests/system.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds: the
# clipboard's and getOS. Like the graphics tests, they run in the test suite's own
# process (test/lovetest/clipboard_test.rb) and under lota run
# (test/lovetest/game). They replace the clipboard's text, as Lövetest's
# do.
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
  # (classes/TestMethod.lua:151-163), Minitest's assert_includes.
  def test_get_os
    # check os is in documented values
    os = Lota::System.os
    options = ["OS X", "Windows", "Linux", "Android", "iOS"]
    assert_includes(options, os, "check value matches")
  end
  # SPDX-SnippetEnd
end
