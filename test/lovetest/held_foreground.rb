# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Whether the tests run on a Windows desktop where a window of the shell's
# own holds the foreground, which whoever runs them says by setting
# LOTA_FOREGROUND_HELD=1, as CI does on GitHub's windows-11-arm runner:
# there a Windows.UI.Core.CoreWindow stays in front, and Windows gives no
# other window the foreground or keyboard focus, whether the test asks
# directly, through the input of the thread in front, or after a key of
# its own (LotaNativeTest.focus_window, ext/lota/native_test/
# dialogs_windows.cpp). SDL grabs the mouse only for the window with
# keyboard focus (SDL 3.4.10, src/video/SDL_video.c,
# SDL_UpdateWindowGrab), so Lövetest's setGrabbed test skips there
# (test/lovetest/tests/mouse.rb), and focus_for_tests.rb asks for focus
# for no test; isOccluded still runs, since a window behind the shell's
# is not occluded. LÖVE's own CI runs Lövetest on no Windows ARM64
# runner at all (vendor/love/.github/workflows/main.yml). It is off
# unless set, and means nothing but on Windows.
module HeldForeground
  # The skip's reason, as the test reports it.
  REASON = "LOTA_FOREGROUND_HELD: a window of the shell's holds this desktop's foreground, " \
    "so Windows gives no test window keyboard focus, for which alone SDL grabs the mouse"

  # Whether +env+ says the foreground is held, on +platform+ (RUBY_PLATFORM's
  # form), which only Windows' can be.
  def self.on?(env: ENV, platform: RUBY_PLATFORM)
    env["LOTA_FOREGROUND_HELD"] == "1" && platform.include?("mingw")
  end

  # The skips a run that counts +skips+ without the switch counts with it:
  # one more where the switch is on, for Lövetest's setGrabbed test.
  def self.skips(skips, env: ENV, platform: RUBY_PLATFORM)
    on?(env:, platform:) ? skips + 1 : skips
  end
end
