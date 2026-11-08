# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# LotaNativeTest.window_state, which says in a focusing test's failure
# message (test/native/focus_for_tests.rb) what the system says of the
# program's windows, since SDL's flags say only what SDL last heard.
class WindowStateTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # On macOS it names SDL's window by the number the system's window list
  # gives it, says whether the system counts it as seen and where it is,
  # and then whether the program is the active one. Under X11, where each
  # lane's display holds only this window (tasks/gate.rb), it has nothing
  # to say, and the failure message says nothing of it.
  def test_it_describes_sdls_window_as_macos_sees_it
    state = LotaNativeTest.window_state

    if TestHome::LINUX
      assert_empty state
    else
      assert_match(/window \d+ \(SDL's\): seen by macOS (yes|no), ordered in (yes|no), key (yes|no), /, state)
      assert_match(/, frame \(-?\d+, -?\d+, \d+, \d+\), screen /, state)
      assert_match(/program active (yes|no), activation policy \d\z/, state)
    end
  end
end
