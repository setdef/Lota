# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Window
    # One of the modes a display can be set to, which
    # Lota::Window.fullscreen_modes returns, translated from the tables
    # love.window.getFullscreenModes returns
    # (src/modules/window/wrap_Window.cpp, w_getFullscreenModes): a frozen
    # value with LÖVE's field names (ADR 001, rule 10).
    #
    # [width] Integer width, in pixels.
    # [height] Integer height, in pixels.
    # [refreshrate] Float refresh rate, in Hz.
    #
    # === Example
    #
    #   mode = Lota::Window.fullscreen_modes.first
    #   Lota::Window.set_mode(mode.width, mode.height, fullscreen: true, fullscreentype: :exclusive)
    class FullscreenMode < ::Data.define(:width, :height, :refreshrate)
      include Record
    end
  end
end
