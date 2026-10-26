# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' globals.lua
# (test/fixtures/gravity_wars/globals.lua, lines 1-85), by ADR 001's
# rules: love.graphics.newImage becomes Lota::Graphics::Image.new and
# newFont Font.new (rule 2), getFont font (rule 3), and getSystemCursor
# system_cursor (rule 3), with the cursor's name a symbol (rule 9).
#
# Gravity Wars keeps its state in Lua's global variables, which every one
# of its files reads and assigns. Ruby's nearest equivalent is one object
# every file reaches, so each global is a field of GLOBALS, a Struct, and
# reads nil until assigned, as an unassigned Lua global does. Its tables
# that hold named fields become Structs too (Player, Planet, Bullet,
# Rainbow), with the same fields. Its tables indexed by number, the
# planets and the bullets, become Hashes keyed by the same numbers,
# counting from 1, so that a bullet added past the end, as explode adds
# them, lands where Lua puts it. Lua's global functions become methods
# defined at the top level, which every file and every callback can call.
# Lua numbers are all doubles, so where Lua divides two whole numbers,
# Ruby divides by a Float, and the game's whole numbers that LÖVE reads as
# integers (the window's size) stay Integers.

Globals = Struct.new(:ss1, :ss2, :pixel_font, :ui_font, :drag_cursor, :width, :height, :dragging,
  :dragging_type, :mouse_xinitial, :mouse_xcurrent, :color_mode, :bul_type, :num_of_bullets,
  :num_of_planets, :all_planets, :all_bullets, :player1, :player2, :turn, :shot_in_progress, :benign,
  :end_of_round, :rainbow, :canvas, :canvas2, :ship_x, :ship_y, :key_right, :key_left, :key_up,
  :key_down)
Player = Struct.new(:x, :y, :angle, :force, :lives, :health, :last_angle, :last_force)
Planet = Struct.new(:x, :y, :r, :mass)
Bullet = Struct.new(:x, :y, :vx, :vy)
Rainbow = Struct.new(:r, :g, :b)

GLOBALS = Globals.new

#--------------------------------------------------------------------------------------------------
# Code setting up all the global variables to be used
#--------------------------------------------------------------------------------------------------
def load_external_assets
  GLOBALS.ss1 = Lota::Graphics::Image.new("assets/ss1.png")
  GLOBALS.ss2 = Lota::Graphics::Image.new("assets/ss2.png")
  GLOBALS.pixel_font = Lota::Graphics::Font.new("assets/basis33.ttf", 16)
end

def set_variables
  GLOBALS.ui_font = Lota::Graphics.font # default font

  GLOBALS.drag_cursor = Lota::Mouse.system_cursor(:sizewe)

  GLOBALS.width = 1000
  GLOBALS.height = 800

  # Mouse click interactions
  GLOBALS.dragging = false
  GLOBALS.dragging_type = nil # `force` or `angle`
  GLOBALS.mouse_xinitial = 0
  GLOBALS.mouse_xcurrent = 0

  # FUN kaleidoscope time!
  # colorMode = 1

  # bullet type (should be changeable by player)
  GLOBALS.bul_type = 1

  # set number of bullets
  GLOBALS.num_of_bullets = 10

  # set number of Planets
  GLOBALS.num_of_planets = 7

  GLOBALS.all_planets = {} # each planet will have `mass`, `r`, `x`, `y`

  GLOBALS.all_bullets = {} # list of bullets, each will have `x`, `y`, and `vx`, `vy` (velocity x & y components)

  GLOBALS.player1 = Player.new(
    x: 100,
    y: 100,
    angle: 0,
    force: 1.5,
    lives: 3,
    health: 100,
    last_angle: nil,
    last_force: nil,
  )

  GLOBALS.player2 = Player.new(
    x: 500,
    y: 500,
    angle: 180,
    force: 1.5,
    lives: 3,
    health: 100,
    last_angle: nil,
    last_force: nil,
  )

  # whose turn
  GLOBALS.turn = 1

  # used to end the turn sometime
  GLOBALS.shot_in_progress = false

  # integer to provide time-out so your bullet doesn't kill you in the first 50 iterations
  # benign while it's less than 50 iterations of bullet flight, for example (see collision check)
  GLOBALS.benign = 0

  # if end of round = 1 it restarts the game after all the bullets end their path
  GLOBALS.end_of_round = false

  # kaleidoscope mode colors for shot trails
  GLOBALS.rainbow = Rainbow.new(
    r: 1,
    g: 1,
    b: 1,
  )
end
# SPDX-SnippetEnd
