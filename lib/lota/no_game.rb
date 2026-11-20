# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The screen Lota shows when it starts with no game, as LÖVE shows its
  # "no game" screen, and which starts the game a player drops on it.
  #
  # LÖVE's screen is a small LÖVE program, nogame.lua, which boot.lua runs
  # when it finds no game (vendor/love/src/modules/love/boot.lua:156-170).
  # It defines the game's callbacks, love.conf among them, so the rest of
  # boot.lua starts it as it would start a game. A file or folder dropped
  # on its window restarts LÖVE with that path as the game's
  # (boot.lua:51-60), and Escape quits.
  #
  # NoGame defines the same callbacks, which do what nogame.lua's do, and
  # Lota::Boot calls it where boot.lua calls love.nogame. What nogame.lua
  # draws is LÖVE's own artwork, which Lota never uses (AGENTS.md,
  # Trademarks), so the screen draws TEXT instead, and nogame.lua's
  # update and resize callbacks, which only move that artwork, have no
  # counterpart. The screen's words, title, and colors are the
  # constants below, and nothing else.
  module NoGame # :nodoc: all
    # The window's title, which load follows with the renderer's name, as
    # nogame.lua's does (lines 3170-3171). LÖVE's names LÖVE, its version,
    # and its codename (line 3276); Lota's names Lota.
    TITLE = "Lota #{VERSION}".freeze

    # What the screen says, centred in the window.
    TEXT = "No game\n\nDrop a .lota file or a game's folder here to play it.\nPress Escape to quit."

    # The size of TEXT's font, in units.
    TEXT_SIZE = 20

    # The color the screen clears to, and the color of TEXT, each red,
    # green, and blue from 0 to 1.
    BACKGROUND = [0.12, 0.12, 0.14].freeze
    FOREGROUND = [0.9, 0.9, 0.9].freeze

    # The callbacks the screen defines on Lota.
    CALLBACKS = %i[conf load draw mousepressed keypressed filedropped directorydropped].freeze

    # Shows the screen from the next frame on, as love.nogame does
    # (nogame.lua:24-3300): defines Lota.conf, Lota.load, and the screen's
    # other callbacks. Each takes every argument Lota passes and hands the
    # screen's method the ones it declares, as Lua drops the arguments a
    # function does not declare.
    def self.call
      CALLBACKS.each do |name|
        callback = method(name)
        Lota.define_singleton_method(name) { |*arguments| callback.call(*arguments.first(callback.arity)) }
      end
      nil
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Translated from vendor/love/src/scripts/nogame.lua, as cited on each
    # method, but for what the screen draws.

    # love.load (nogame.lua:3169-3217): names the renderer in the title
    # and sets the background. The rest of nogame.lua's load makes its
    # artwork; the screen makes its font instead.
    def self.load
      renderername, = Lota::Graphics.renderer_info
      Lota::Window.title = "#{Lota::Window.title} - #{renderername}"

      Lota::Graphics.background_color = BACKGROUND
      @font = Lota::Graphics::Font.new(TEXT_SIZE)
    end

    # Draws TEXT in the middle of the window.
    def self.draw
      font = @font or return
      width = Lota::Graphics.width
      height = Lota::Graphics.height
      lines = TEXT.count("\n") + 1
      Lota::Graphics.color = FOREGROUND
      Lota::Graphics.printf(TEXT, font, 0, ((height - (lines * font.height)) / 2).floor, width, :center)
    end

    # love.mousepressed (nogame.lua:3255-3262).
    def self.mousepressed(_x, _y, _b, istouch, clicks)
      # Double-tap the screen (when using a touch screen) to exit.
      return unless istouch && clicks == 2

      Lota::Event.quit if Lota::Window.show_message_box("Exit No-Game Screen", "", %w[OK Cancel]) == 1
    end

    # love.keypressed (nogame.lua:3264-3268).
    def self.keypressed(key)
      Lota::Event.quit if key == :escape
    end

    # love.conf (nogame.lua:3275-3287), with Lota's title.
    def self.conf(t)
      t.title = TITLE
      graphics = t.graphics
      graphics.gammacorrect = true if graphics.is_a?(Settings::Graphics)
      t.modules.audio = false
      t.modules.sound = false
      t.modules.joystick = false
      window = t.window
      window.resizable = true if window
      t.highdpi = true

      window.borderless = true if window && Lota::System.os == "iOS"
    end

    # restartWithNewGame (nogame.lua:3289-3291): restarts Lota with the
    # game at +path+, which Lota::Boot then starts (boot.lua:51-60).
    def self.restart_with_new_game(path)
      Lota::Event.restart({ "_noGameRestartInfo" => { "gamepath" => path } })
    end

    # love.filedropped (nogame.lua:3293-3295).
    def self.filedropped(file)
      restart_with_new_game(file.filename)
    end

    # love.directorydropped (nogame.lua:3297-3299).
    def self.directorydropped(path)
      restart_with_new_game(path)
    end

    # SPDX-SnippetEnd
  end
end
