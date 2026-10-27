# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' main.lua
# (test/fixtures/klele_atoms/main.lua, lines 1-182), by ADR 001's rules:
# love.filesystem.getInfo becomes Lota::Filesystem.info (rule 3), whose
# table is a frozen Info (rule 10), lines an Enumerator (rule 15),
# setDefaultFilter a writer of several values (rules 5 and 6), newFont
# Font.new (rule 2), and getOS os (rule 3). love.load and the callbacks
# become methods on Lota (ADR 003), each calling the state's.
#
# KleleAtoms keeps its settings in Lua globals named _CA..., and reads and
# writes some of them by name through _G. Ruby's nearest equivalent is one
# object every file reaches, so each global is a field of CA, a Struct,
# whose fields are read and written by name with [] as _G's are, and read
# nil until assigned, as an unassigned Lua global does. Lua's tonumber,
# which gives nil for text that is not a number, is tonumber below. Lua's
# modules, the tables require returns, become Ruby modules, and
# _CAState is State. Lua numbers are all doubles, so where Lua divides,
# Ruby divides by a Float, and the game's whole numbers stay Integers, as
# Lua's tostring writes a whole double without a fraction.

Globals = Struct.new(:grid_w, :grid_h, :play_exp, :player1, :player2, :player3, :player4, :full_screen,
  :win_resizing, :font16, :font24, :font32, :os_type, :is_mobile, :kb_mode, :use_scaling, :animplaying)

CA = Globals.new

# Lua's tonumber for the text the game reads: the number it writes, or nil.
def tonumber(text)
  Integer(text, exception: false) || Float(text, exception: false)
end

require "state"

SETTSVALS = [ # A table to convert settings2.txt line number to a setting name
  :grid_w,
  :grid_h,
  :play_exp,
  :player1,
  :player2,
  :player3,
  :player4,
  :full_screen,
  :win_resizing,
].freeze

def check_valid_players # Makes sure that at least 2 players are present
  pc = 0
  4.upto(7) do |i|
    pc += 1 if CA[SETTSVALS[i - 1]] > 0
  end
  return unless pc < 2

  pos = 4
  while pc < 2
    if CA[SETTSVALS[pos - 1]] == 0
      pc += 1
      CA[SETTSVALS[pos - 1]] = 1
    end
    pos += 1
  end
end

def check_set_values # Checks if values are in a valid range and type
  CA.grid_w = CA.grid_w.clamp(7, 30)
  CA.grid_h = CA.grid_h.clamp(4, 20)
  CA.play_exp = CA.play_exp.clamp(1, 3)
  CA.player1 = CA.player1.clamp(0, 4)
  CA.player2 = CA.player2.clamp(0, 4)
  CA.player3 = CA.player3.clamp(0, 4)
  CA.player4 = CA.player4.clamp(0, 4)
  CA.full_screen = (CA.full_screen && CA.full_screen != 0)
  CA.win_resizing = (CA.win_resizing && CA.win_resizing != 0)
  check_valid_players
end

def read_args(args)
  valmode = 0 # 0 - nothing, 1 - grid width, 2 - grid height, 3 - AI difficulty, 4-7 - Player types, 100 - OS type
  args.each do |v|
    if valmode == 0
      if v == "-gridwidth" || v == "-gw"
        valmode = 1
      elsif v == "-gridheight" || v == "-gh"
        valmode = 2
      elsif (v[0...-1] == "-player" && v != "-players") || v[0...-1] == "-p"
        pnum = tonumber(v[-1])
        valmode = 3 + pnum if pnum && pnum >= 1 && pnum <= 4
      elsif v == "-mobilemode" || v == "-mobile"
        CA.is_mobile = true
      elsif v == "-forceos" || v == "-os"
        valmode = 100
      elsif v == "-fullscreen" || v == "-full"
        valmode = 101
      elsif v == "-resizable" || v == "-resize"
        valmode = 102
      end
    elsif valmode > 0 && valmode <= 7
      index = SETTSVALS[valmode - 1]
      CA[index] = tonumber(v) || CA[index]
      valmode = 0
    elsif valmode == 100 # Force OS type
      CA.os_type = v
      CA.is_mobile ||= (CA.os_type == "Android" || CA.os_type == "iOS" || CA.os_type == "Web")
      valmode = 0
    elsif valmode == 101 # Fullscreen
      CA.full_screen = tonumber(v) || CA.full_screen
      valmode = 0
    elsif valmode == 102 # Window resizing
      CA.win_resizing = tonumber(v) || CA.win_resizing
      valmode = 0
    end
  end
end

def load_settings
  inum = 1
  if Lota::Filesystem.info("settings2.txt") # Load a settings file (1.2 and newer versions)
    Lota::Filesystem.lines("settings2.txt").each do |line|
      if inum <= SETTSVALS.size
        index = SETTSVALS[inum - 1]
        CA[index] = tonumber(line) || CA[index]
        inum += 1
      end
    end
  elsif Lota::Filesystem.info("settings.txt") # Convert settings format from 1.1.2 and older versions to 1.2 format (with 1.3 changes)
    pcount = nil
    Lota::Filesystem.lines("settings.txt").each do |line|
      if inum <= 2
        index = SETTSVALS[inum - 1]
        CA[index] = tonumber(line) || CA[index]
      elsif inum == 3 # Old index 3 and 4 are replaced by separate player type settings
        pcount = tonumber(line)
        CA.player1, CA.player2, CA.player3, CA.player4 = 0, 0, 0, 0
        if pcount
          pcount = [pcount, 4].min
          1.upto(pcount) do |i|
            index = SETTSVALS[3 + i - 1]
            CA[index] = 1
          end
        end
      elsif inum == 4
        aicount = tonumber(line)
        if aicount && pcount
          aicount = [aicount, 4].min
          (pcount - aicount + 1).upto(pcount) do |i|
            index = SETTSVALS[3 + i - 1]
            break if CA[index] == 0

            CA[index] = 3
          end
        end
      elsif inum == 5 # AI difficulty
        ailevel = tonumber(line) || 2
        1.upto(4) do |i|
          index = SETTSVALS[3 + i - 1]
          CA[index] = 1 + ailevel if CA[index] == 3
        end
      end
      inum += 1
    end
    CA.play_exp = 2 # Hide the tutorial message
    State.printmsg("Converted old settings to 1.2+ format!", 4)
  end
end

def Lota.load(args)
  Lota::Graphics.default_filter = :linear, :linear, 0
  CA.font16 = Lota::Graphics::Font.new(16) # Default font, size 16
  CA.font24 = Lota::Graphics::Font.new(24) # Default font, size 24
  CA.font32 = Lota::Graphics::Font.new(32) # Default font, size 32
  CA.grid_w = 10 # Grid width
  CA.grid_h = 6 # Grid Height
  CA.player1 = 1 # Player 1 type (0 - not present, 1 - player, 2 - AI easy, 3 - AI medium, 4 - AI hard, 9 - dummy/scripted)
  CA.player2 = 3 # Player 2 type
  CA.player3 = 0 # Player 3 type
  CA.player4 = 0 # Player 4 type
  CA.play_exp = 1 # Player experience (1 - none, 2 - started/skipped tutorial, 3 - won a game), replaces unused AI Level variable
  CA.os_type = Lota::System.os
  CA.full_screen = false
  CA.win_resizing = false # Window resizing (on PC)
  CA.is_mobile = (CA.os_type == "Android" || CA.os_type == "iOS" || CA.os_type == "Web") # If true, mobile mode will be enabled
  CA.kb_mode = false # Keyboard mode
  load_settings
  read_args(args) # Read commandline parameters
  check_set_values # Make sure the settings are within the acceptable range
  CA.full_screen = true if CA.is_mobile # Fullscreen is always enabled in mobile mode
  CA.use_scaling = (CA.full_screen || CA.win_resizing) # Is any type of window scaling used?
  require "states/game/gamestate"
  State.list["game"] = GameState
  require "states/menu/menustate"
  State.list["menu"] = MenuState
  State.change("menu")
end

def Lota.update(dt) = State.update(dt)

def Lota.draw = State.draw

def Lota.keypressed(key, scancode, isrepeat) = State.keypressed(key, scancode, isrepeat)

def Lota.keyreleased(key) = State.keyreleased(key)

def Lota.mousepressed(x, y, button) = State.mousepressed(x, y, button)

def Lota.mousereleased(x, y, button) = State.mousereleased(x, y, button)

def Lota.focus(focus) = State.focus(focus)

def Lota.quit = State.quit

def Lota.resize(x, y) = State.resize(x, y)
# SPDX-SnippetEnd
