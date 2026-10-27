# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# rake test:native puts the sanitized extensions ahead of lib on the load
# path; moving lib to the front would load lib/lota's bundle instead.
lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "fileutils"
require "minitest"
require "tmpdir"

# Every test, and every program a test starts, gets a home of its own
# before the engine loads: Foundation reads the home directory from
# CFFIXED_USER_HOME when it is set, and LÖVE's filesystem saves under the
# home's Application Support (src/common/apple.mm, getUserDirectory), so a
# test that saves never touches yours. OpenAL Soft plays into a wave file
# in that home (test/alsoft.conf), so no test makes a sound.
unless ENV["LOTA_TEST_HOME"]
  ENV["LOTA_TEST_HOME"] = ENV["CFFIXED_USER_HOME"] = Dir.mktmpdir("lota-test-home-")
  home = ENV["LOTA_TEST_HOME"]
  Minitest.after_run { FileUtils.rm_rf(home) }
end
ENV["ALSOFT_CONF"] = File.expand_path("alsoft.conf", __dir__)

# The windows the tests open, here and in every program they start, the
# parity harness's LÖVE among them, stay in the background, so they take
# no keyboard focus from whatever the person at the computer is typing in.
# SDL reads its hints from the environment: SDL_MAC_BACKGROUND_APP keeps
# it from making the program a regular one and activating it as it starts
# (SDL 3.4.10, src/video/cocoa/SDL_cocoaevents.m, Cocoa_RegisterApp and
# applicationDidFinishLaunching), and SDL_WINDOW_ACTIVATE_WHEN_SHOWN and
# SDL_WINDOW_ACTIVATE_WHEN_RAISED keep showing a window and raising it,
# which LÖVE does on every setMode (window/sdl/Window.cpp:641), from
# activating it (src/video/cocoa/SDL_cocoawindow.m, Cocoa_ShowWindow and
# Cocoa_RaiseWindow). A game a player runs gets none of them. Dialogs
# activate their program regardless, so the harness that presses Return
# on them also keeps it in the background (ext/lota/native_test/dialogs.mm).
ENV.update("SDL_MAC_BACKGROUND_APP" => "1", "SDL_WINDOW_ACTIVATE_WHEN_SHOWN" => "0",
  "SDL_WINDOW_ACTIVATE_WHEN_RAISED" => "0")

require "lota"

require "minitest/autorun"
