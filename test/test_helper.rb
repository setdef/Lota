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
require_relative "test_home"

# Every test, and every program a test starts, gets a home of its own
# before the engine loads (test/test_home.rb), so a test that saves never
# touches yours. OpenAL Soft plays into a wave file in that home
# (test/alsoft.conf), so no test makes a sound.
unless ENV["LOTA_TEST_HOME"]
  home = Dir.mktmpdir("lota-test-home-")
  TestHome.enter(home)
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
# On Linux, under X11, only the last does anything: SDL leaves whether a
# window takes focus as it is shown to the window manager
# (src/video/x11/SDL_x11window.c, X11_ShowWindow), so CI runs the tests
# on a display of their own, Xvfb's, as LÖVE's own Linux CI runs Lövetest
# (vendor/love/.github/workflows/main.yml).
ENV.update("SDL_MAC_BACKGROUND_APP" => "1", "SDL_WINDOW_ACTIVATE_WHEN_SHOWN" => "0",
  "SDL_WINDOW_ACTIVATE_WHEN_RAISED" => "0")

require "lota"

require "minitest/autorun"
