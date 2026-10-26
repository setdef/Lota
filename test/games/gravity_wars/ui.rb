# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' ui.lua
# (test/fixtures/gravity_wars/ui.lua, lines 1-169), as globals.rb
# describes: setColor becomes color= (rules 5 and 6), setCanvas canvas=
# (rule 5), with setCanvas() as canvas = nil, setFont font= (rule 5), and
# the draw modes and alignment symbols (rule 9). w_setFont reads only its
# first argument (wrap_Graphics.cpp:2573-2578), so Lua ignores the 20 that
# drawForceAndAngle passes after the font, and the translation leaves it
# out. Lua's for loops over 1 to n become Ruby's 1.upto(n).

#--------------------------------------------------------------------------------------------------
# Code related to drawing the UI (user interface)
#--------------------------------------------------------------------------------------------------
def draw_ui
  Lota::Graphics.color = 1, 1, 1, 1

  # rectangle for health bars and around play area
  Lota::Graphics.rectangle(:line, 2, 2, GLOBALS.width - 4, 30)
  Lota::Graphics.rectangle(:line, 2, 32, GLOBALS.width - 4, GLOBALS.height - 34)

  draw_shoot_button

  draw_lives

  draw_health_bars

  Lota::Graphics.color = 1, 1, 1, 1
end

# shoot BUTTON rectangle -- change states while shot in progress
def draw_shoot_button
  if GLOBALS.shot_in_progress == true
    Lota::Graphics.color = 0.5, 0, 0, 1
    Lota::Graphics.ellipse(:fill, GLOBALS.width - 50, GLOBALS.height - 50, 30, 30)
  else
    Lota::Graphics.color = 16 / 255.0, 178 / 255.0, 197 / 255.0, 1
    Lota::Graphics.ellipse(:fill, GLOBALS.width - 50, GLOBALS.height - 50, 30, 30)
  end
end

# draw how many lives each has
def draw_lives
  Lota::Graphics.color = 1, 1, 0, 1
  1.upto(GLOBALS.player1.lives) do |i|
    Lota::Graphics
      .ellipse(:fill, (GLOBALS.width / 2.0) + 35 + (20 * i), 16, 8, 8)
  end

  1.upto(GLOBALS.player2.lives) do |i|
    Lota::Graphics
      .ellipse(:fill, (GLOBALS.width / 2.0) - 35 - (20 * i), 16, 8, 8)
  end
end

# draw health bars - responsive depending on WIDTH
def draw_health_bars
  top_offset = 10

  bar_width = (GLOBALS.width / 2.0) - 200

  player1 = GLOBALS.player1
  player2 = GLOBALS.player2

  # right health bar
  Lota::Graphics.color = (255 - (player1.health * 2.55)) / 255.0, 1, 0, 1
  Lota::Graphics.rectangle(:fill, (GLOBALS.width / 2.0) + 150, top_offset, bar_width, 10)

  if player1.health < 100
    Lota::Graphics.color =
      223 / 255.0,
      (45 + player1.health) / 255.0,
      (45 + player1.health) / 255.0,
      1
    Lota::Graphics.rectangle(:fill, ((GLOBALS.width / 2.0) + 150) + bar_width - (bar_width *
                                    ((100 - player1.health) / 100.0)), top_offset,
      bar_width - (bar_width * (player1.health / 100.0)), 10)
  end

  # left health bar
  Lota::Graphics.color = (255 - (player2.health * 2.55)) / 255.0, 1, 0, 1
  Lota::Graphics.rectangle(:fill, (GLOBALS.width / 2.0) - bar_width - 150, top_offset, bar_width, 10)

  if player2.health < 100
    Lota::Graphics.color =
      224 / 255.0,
      (45 + player2.health) / 255.0,
      (45 + player2.health) / 255.0,
      1
    Lota::Graphics.rectangle(:fill, (GLOBALS.width / 2.0) - bar_width - 150, top_offset,
      bar_width - (bar_width * (player2.health / 100.0)), 10)
  end
end

def draw_force_and_angle(player_n, temp_hack)
  # different offset depending on player
  if temp_hack == 1
    x_offset = player_n.x - 140
    angle_y = player_n.y + 80
    force_y = player_n.y + 92
  else
    x_offset = player_n.x + 55
    angle_y = player_n.y + 78
    force_y = player_n.y + 90
  end

  # black background behind angle and force
  Lota::Graphics.color = 0, 0, 0, 0.7
  Lota::Graphics.rectangle(:fill, x_offset + 12, angle_y, 70, 13, 4, 4)
  Lota::Graphics.rectangle(:fill, x_offset + 24, force_y + 1, 66, 12, 4, 4)

  # print force (red)
  Lota::Graphics.color = 1, 0, 0, 1
  Lota::Graphics.font = GLOBALS.pixel_font
  Lota::Graphics.print("GJ", x_offset + 76, force_y) # GigaJoules
  Lota::Graphics.printf(format("%.5f", player_n.force), x_offset, force_y, 75, :right)

  # print angle (white)
  Lota::Graphics.color = 1, 1, 1, 1
  Lota::Graphics.printf(format("%.5f", 360 - player_n.angle), x_offset, angle_y, 75, :right)
  Lota::Graphics.ellipse(:line, x_offset + 78, angle_y + 3, 2, 2)
end

def draw_ships
  # in the user interface (top left and top right)
  Lota::Graphics.draw(GLOBALS.ss1, 24, 11)
  Lota::Graphics.draw(GLOBALS.ss2, GLOBALS.width - 32, 11)

  # love.graphics.setColor(1, 0.6, 0.6, 1)
  # love.graphics.ellipse('fill', player1.x, player1.y, 8, 8)
  # love.graphics.ellipse('fill', player2.x, player2.y, 8, 8)

  if GLOBALS.player1.health > 0
    Lota::Graphics.draw(GLOBALS.ss1, GLOBALS.player1.x - 4, GLOBALS.player1.y - 4)
  end

  if GLOBALS.player2.health > 0
    Lota::Graphics.draw(GLOBALS.ss2, GLOBALS.player2.x - 4, GLOBALS.player2.y - 4)
  end

  # love.graphics.draw(ss1, player1.x, player1.y, player1.angle, 1, 1, 4, 4)
end

# Dim all the shot trails on the screen
# meant to run after every shot
# works by drawing a black rectangle with low opacity over the whole screen
# then redraws all other elements on top
def dim_trails
  puts("dimTrails EXECUTED")

  Lota::Graphics.canvas = GLOBALS.canvas
  Lota::Graphics.color = 0, 0, 0, 0.15 # don't fortget to reset ?
  Lota::Graphics.rectangle(:fill, 0, 0, GLOBALS.width, GLOBALS.height)
  Lota::Graphics.color = 1, 1, 1, 1 # reset back !?
  draw_planets # execute inside `canvas` ?!
  draw_ships
  draw_ui
  Lota::Graphics.canvas = nil # reset canvas ?!
end

def draw_planets
  1.upto(GLOBALS.num_of_planets) do |i|
    planet = GLOBALS.all_planets[i]
    Lota::Graphics.color = 0.1, 0.1, 0.1, 1
    Lota::Graphics.ellipse(:fill, planet.x, planet.y,
      planet.r, planet.r)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.ellipse(:line, planet.x, planet.y,
      planet.r, planet.r)
  end
end
# SPDX-SnippetEnd
