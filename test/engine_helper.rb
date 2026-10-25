# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Brings the engine up for tests that draw, as LÖVE's boot sequence brings
# it up for Lövetest. How a Lota game itself starts is not decided yet
# (Plan 001, the walking skeleton's entry point), so this lives with the
# tests and drives Lota::Native directly.
module EngineHelper
  # Opens the event, image, window, and graphics modules and a window, once
  # per process. Call it from the main thread.
  def self.open_window
    @open_window ||= boot
  end

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.init (vendor/love/src/modules/love/
  # boot.lua:347-371 and 398-433) as it runs with Lövetest's conf.lua
  # (vendor/love/testing/conf.lua:1-11), for the modules the tests use.
  # boot.lua requires the modules in this order; t.window's other fields
  # keep boot.lua's defaults (boot.lua:178-196), which match
  # WindowSettings' own (vendor/love/src/modules/window/Window.h:284-303).
  # The window's title (boot.lua:404) stays SDL's, because Lota binds no
  # setTitle yet; no test reads it.
  private_class_method def self.boot
    Lota::Native::Event.open
    Lota::Native::Image.open
    Lota::Native::Window.open
    Lota::Native::Graphics.open

    settings = Lota::Native::WindowSettings.new
    settings.resizable = true
    settings.depth = true
    settings.stencil = true
    settings.usedpiscale = false
    raise "Could not set window mode" unless Lota::Native::Window.set_mode(360, 240, settings)

    # "The first couple event pumps on some systems (e.g. macOS) can take a
    # while." (boot.lua:428-433)
    2.times { Lota::Native::Event.pump }
    true
  end
  # SPDX-SnippetEnd
end
