# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Window
    # The window's settings, which Lota::Window.mode returns, translated
    # from the table love.window.getMode returns
    # (src/modules/window/wrap_Window.cpp, w_getMode): a frozen value with
    # LÖVE's field names (ADR 001, rule 10), each as Lota::Window.set_mode
    # takes it.
    #
    # [fullscreentype] +:desktop+ or +:exclusive+.
    # [fullscreen] Whether the window fills the screen.
    # [vsync] Integer: 1, 0, or -1.
    # [msaa] Integer number of antialiasing samples.
    # [stencil] Whether the window has a stencil buffer.
    # [depth] Whether it has a depth buffer.
    # [resizable] Whether the player can resize it.
    # [minwidth] Integer smallest width the player can resize it to.
    # [minheight] Integer smallest height.
    # [borderless] Whether it has no border.
    # [centered] Whether it opens centered.
    # [displayindex] Integer display it is on, counting from 1.
    # [usedpiscale] Whether sizes count in units of the DPI scale.
    # [refreshrate] Float refresh rate of its display, in Hz.
    # [x] Integer position of its left edge on its display.
    # [y] Integer position of its top edge.
    #
    # === Example
    #
    #   _, _, flags = Lota::Window.mode
    #   flags.resizable # => false
    class Mode < ::Data.define(:fullscreentype, :fullscreen, :vsync, :msaa, :stencil, :depth, :resizable, :minwidth,
      :minheight, :borderless, :centered, :displayindex, :usedpiscale, :refreshrate, :x, :y)
      include Record
    end
  end
end
