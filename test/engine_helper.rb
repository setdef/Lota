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

  private_class_method def self.boot
    Lota::Boot.new(CONF).init
    true
  end
end
