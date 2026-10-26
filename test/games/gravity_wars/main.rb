# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' main.lua
# (test/fixtures/gravity_wars/main.lua, lines 1-221), as globals.rb and
# the files it requires describe: Lua's require of a file beside main.lua
# is Ruby's require of the one beside main.rb (ADR 003, section 6),
# love.load and draw become Lota.load and draw (ADR 003), setMode becomes
# Lota::Window.set_mode (rule 7), newCanvas Canvas.new (rule 2) with its
# settings table as keywords (rule 10), and math.randomseed and os.time
# Lota::Math.random_seed= (rule 5) and Time.now.to_i, Ruby's seconds since
# the epoch. Lua's math.pow and math.abs are Ruby's ** and abs, and
# math.sin and math.floor Math.sin and floor. Lua's angleDiff, forceDiff,
# xOffset, fontOpacity, and bulletsInFlight are globals no other function
# reads, so they are Ruby locals. The game has no conf.lua, so this game
# has no conf.rb.

#--------------------------------------------------------------------------------------------------
# Code for imports, the initial load, and the `draw` loop
#--------------------------------------------------------------------------------------------------
require "globals"
require "ui"
require "shoot"
require "logic"
require "touch"
require "keyboard"

# Use this function to perform your initial setup
def Lota.load
  # math.randomseed(42)  -- goes out of bounds
  # math.randomseed(232) -- shot comes close to opponent; set `shotType3()` numOfBullets to 15 to hit opponent
  Lota::Math.random_seed = Time.now.to_i # randomize map every time

  load_external_assets # globals.lua
  set_variables # globals.lua

  Lota::Window.set_mode(GLOBALS.width, GLOBALS.height)

  GLOBALS.canvas = Lota::Graphics::Canvas.new(GLOBALS.width, GLOBALS.height, msaa: 2)

  GLOBALS.canvas2 = Lota::Graphics::Canvas.new(GLOBALS.width, GLOBALS.height, msaa: 2)

  # love.graphics.setCanvas(canvas)
  #     love.graphics.setBlendMode("alpha") -- what does this do ?!??
  # love.graphics.setCanvas()

  new_game

  GLOBALS.bul_type = 1
  # playerPressedShootButton() -- disable this to let the player take the first shot
end

# This function gets called once every frame

def Lota.draw
  # love.graphics.setBackgroundColor(0,0,50/255)

  if GLOBALS.end_of_round == true && GLOBALS.shot_in_progress == false
    GLOBALS.end_of_round = false
    new_game
  end

  rainbow = GLOBALS.rainbow
  if GLOBALS.color_mode == 1
    # this has potential to run over (how many minutes till it crashes?)
    # might want it to reset to 0 sometimes
    rainbow.r = rainbow.r + 1
    rainbow.g = rainbow.g + 2
    rainbow.b = rainbow.b + 3

    # this code oscilates the color all the time (mathematically heavy)
    Lota::Graphics.color =
      ((200 * Math.sin(rainbow.r * 0.005).abs) + 54).floor / 255.0,
      ((200 * Math.sin(rainbow.g * 0.004).abs) + 54).floor / 255.0,
      ((200 * Math.sin(rainbow.b * 0.003).abs) + 54).floor / 255.0,
      1
  elsif GLOBALS.color_mode == 2
    Lota::Graphics.color = 1, 1, 1, 1
  end

  # only draw things if shot is in progress
  if GLOBALS.shot_in_progress == true
    1.upto(GLOBALS.num_of_bullets) { |i| draw_shot(i) }

    1.upto(GLOBALS.num_of_bullets) { |i| collison_check(i) }

    GLOBALS.benign = GLOBALS.benign + 1 # benign makes your own bullet not kill you for the first few moments when you shoot

    bullets_in_flight = false # TODO: fix this hacky thing: if the x location of each shot == 0 then end the turn
    1.upto(GLOBALS.num_of_bullets) do |i|
      if GLOBALS.all_bullets[i].x != 0 && GLOBALS.all_bullets[i].y != 0
        bullets_in_flight = true # HACK -- assumes position of disabled bullet is = (0, 0)
      end
    end

    if bullets_in_flight == false
      puts("all shots have finished")

      GLOBALS.shot_in_progress = false

      if GLOBALS.turn == 1
        GLOBALS.turn = 2
      elsif GLOBALS.turn == 2
        GLOBALS.turn = 1
      end

      Lota::Graphics.canvas = GLOBALS.canvas
      draw_ui
      Lota::Graphics.canvas = nil
    end

  end

  # this code here WILL dim the trails continuously when explosion occurs
  # works too fast so I can slow it down by dimming every 5th frame (temp int)
  # if benign < 0 then dimTrails() end

  # drawUI() -- maybe do not draw continuously ?

  # starts dimming the playing field more aggressively
  if GLOBALS.end_of_round == true
    # dimTrails()
    # love.graphics.setColor(0,0,0,1)
    # love.graphics.rectangle('fill',-1,-1,WIDTH+5,HEIGHT+5)
  end

  # RENDER THE CANVAS NOW
  Lota::Graphics.draw(GLOBALS.canvas)

  if GLOBALS.shot_in_progress == false

    Lota::Graphics.canvas = GLOBALS.canvas2
    Lota::Graphics.clear

    if GLOBALS.turn == 1
      draw_player_angle_and_force(GLOBALS.player1)
      if !GLOBALS.player1.last_angle.nil?
        draw_angle_diff(GLOBALS.player1, 0)
      end
      draw_force_and_angle(GLOBALS.player1, 1)
    else
      draw_player_angle_and_force(GLOBALS.player2)
      if !GLOBALS.player2.last_angle.nil?
        draw_angle_diff(GLOBALS.player2, 1)
      end
      draw_force_and_angle(GLOBALS.player2, 2)
    end

    Lota::Graphics.canvas = nil
    Lota::Graphics.draw(GLOBALS.canvas2)

  end

  draw_ships

  Lota::Graphics.color = 1, 1, 1, 1
end

def draw_player_angle_and_force(player_n)
  # large black circle
  Lota::Graphics.color = 0, 0, 0, 0.6
  Lota::Graphics.ellipse(:fill, player_n.x, player_n.y, 100, 100)

  # red arc showing force
  Lota::Graphics.color = 1, 0, 0, 1
  Lota::Graphics.arc(:fill, :pie, player_n.x, player_n.y, player_n.force * 20, (0.0174533 * player_n.angle) - 0.1,
    (0.0174533 * player_n.angle) + 0.1)

  # smaller red circle showing force
  Lota::Graphics.color = 1, 0, 0, 0.4
  Lota::Graphics.ellipse(:line, player_n.x, player_n.y, player_n.force * 20, player_n.force * 20)

  # love.graphics.setColor(1, 0, 0, 1)
  # love.graphics.line(playerN.x, playerN.y,
  #                     playerN.x + math.cos(0.0174533 * playerN.angle) * 100 * playerN.force / 5,
  #                     playerN.y + math.sin(0.0174533 * playerN.angle) * 100 * playerN.force / 5)

  # large white circle showing maximum
  Lota::Graphics.color = 1, 1, 1, 0.6
  Lota::Graphics.ellipse(:line, player_n.x, player_n.y, 100, 100)

  # long line showing angle
  Lota::Graphics.color = 1, 1, 1, 1
  Lota::Graphics.ellipse(:line, player_n.x, player_n.y, 10, 10)
  Lota::Graphics.line(player_n.x, player_n.y,
    player_n.x + (Math.cos(0.0174533 * player_n.angle) * 100),
    player_n.y + (Math.sin(0.0174533 * player_n.angle) * 100))
end

def draw_angle_diff(player_n, player_offset_hack)
  angle_diff = player_n.last_angle - player_n.angle

  force_diff = player_n.force - player_n.last_force

  if angle_diff > 180
    angle_diff -= 360
  end

  if angle_diff < -180
    angle_diff += 360
  end

  if angle_diff < 10 && angle_diff > -10

    x_offset = player_n.x - 76 + (player_offset_hack * 90)

    font_opacity = ((10 - angle_diff.abs) / 10.0) ** 0.5
    Lota::Graphics.font = GLOBALS.pixel_font

    if angle_diff != 0
      # rectangle
      Lota::Graphics.color = 0, 0, 0, 0.5
      Lota::Graphics.rectangle(:fill, x_offset + 5, player_n.y - 6, 56, 12, 4, 4)
      # text
      Lota::Graphics.color = 1, 1, 1, font_opacity
      Lota::Graphics.printf(format("%.5f", angle_diff), x_offset, player_n.y - 7, 60, :right)
    end

    Lota::Graphics.color = 1, 0, 0, font_opacity

    if force_diff != 0
      # rectangle
      Lota::Graphics.color = 0, 0, 0, 0.5
      Lota::Graphics.rectangle(:fill, x_offset + 5, player_n.y + 6, 56, 12, 4, 4)
      # text
      Lota::Graphics.color = 1, 0, 0, font_opacity
      Lota::Graphics.printf(format("%.5f", force_diff), x_offset, player_n.y + 5, 60, :right)
    end

    Lota::Graphics.color = 1, 1, 1, 1
  end
end
# SPDX-SnippetEnd
