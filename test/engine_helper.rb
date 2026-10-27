# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "lota"

# Brings the engine up for tests that draw, as lota run brings it up for
# a game: with Lota::Boot, from the conf.rb that translates Lövetest's own
# (test/lovetest/conf.rb).
module EngineHelper
  # The folder whose conf.rb configures the tests' window. It holds no
  # main.rb, so booting it runs no game.
  CONF = File.expand_path("lovetest", __dir__)

  # Opens the modules and the window Lövetest's conf.lua asks for, once
  # per process, unless lota run already opened them, as it does for
  # test/lovetest/game. Call it from the main thread.
  def self.open_window
    @open_window ||= booted? || boot
  end

  private_class_method def self.booted?
    Lota::Native::Graphics.open? && Lota::Graphics.active?
  end

  # Booting opens the window, which SDL_MAC_BACKGROUND_APP keeps from
  # activating the program (test/test_helper.rb), but a click of the
  # person at the computer still could, and give the window keyboard
  # focus, which SDL lets go of every held key on losing
  # (SDL_SetKeyboardFocus, SDL 3.4.10, src/events/SDL_keyboard.c), as when
  # the person clicks elsewhere, so a test holding a key could find it let
  # go. With the test extension loaded, the program stays in the
  # background for good (LotaNativeTest.stay_in_background), and its
  # windows never take focus but where a test asks for it.
  private_class_method def self.boot
    Lota::Boot.new(CONF).init
    LotaNativeTest.stay_in_background if defined?(LotaNativeTest)
    true
  end
end
