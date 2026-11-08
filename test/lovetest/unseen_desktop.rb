# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Whether the tests run on a desktop that macOS does not draw, which
# whoever runs them says by setting LOTA_DESKTOP_UNSEEN=1: a login session
# in the background (another account's, kept logged in with Fast User
# Switching), or a virtual machine without a display. macOS counts nearly
# every window there as one that cannot be seen, in front or not, and SDL,
# which remembers only what macOS last said of a window's occlusion (SDL
# 3.4.10, src/video/cocoa/SDL_cocoawindow.m,
# windowDidChangeOcclusionState and Cocoa_SendExposedEventIfVisible),
# calls a window occluded for good once macOS has said so. So Lövetest's
# isOccluded test, which needs a window that can be seen, skips there
# (test/lovetest/tests/window.rb); no other test changes. It is off unless
# set, and means nothing on Linux, where each lane's X display draws its
# windows (tasks/gate.rb).
#
# It needs nothing loaded, so the tasks that count the tests' skips
# (tasks/package.rake) ask it as the tests do.
module UnseenDesktop
  # The skip's reason, as the test reports it.
  REASON = "LOTA_DESKTOP_UNSEEN: macOS does not draw this desktop, so it counts no window as seen, " \
    "and SDL calls a window occluded once macOS has said so"

  # Whether +env+ says the desktop is unseen, on +platform+ (RUBY_PLATFORM's
  # form), which only macOS's can be.
  def self.on?(env: ENV, platform: RUBY_PLATFORM)
    env["LOTA_DESKTOP_UNSEEN"] == "1" && platform.include?("darwin")
  end

  # The skips a run that counts +skips+ without the switch counts with it:
  # one more where the switch is on, for Lövetest's isOccluded test.
  def self.skips(skips, env: ENV, platform: RUBY_PLATFORM)
    on?(env:, platform:) ? skips + 1 : skips
  end
end
