# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' touch.lua
# (test/fixtures/gravity_wars/touch.lua, lines 1-131), as globals.rb and
# logic.rb describe: love.mousepressed, mousereleased, and update become
# Lota's (ADR 003), love.mouse.setCursor becomes cursor= (rule 5), with
# setCursor() as cursor = nil, and getX x (rule 3). clamp's math.max of
# math.min, which keeps a value within bounds the game always gives in
# order, is Ruby's clamp. Lua's clickNearShip,
# forceOffset, distance, diff, and angle are globals no other function
# reads, so they are Ruby locals.

#--------------------------------------------------------------------------------------------------
# Code related to touch interactions (from Codea, not yet updated for Love2D)
#--------------------------------------------------------------------------------------------------
# toggle booleans if clicked in areas where button / sliders are
def Lota.mousepressed(x, y, _button)
  # print(x)
  # print(y)

  # fun times
  # if shotInProgress == true then
  #     explode(x,y)
  # end

  # rectangle on bottom-right to detect pressing shoot button
  if GLOBALS.shot_in_progress == false && (x > (GLOBALS.width - 100) && y > GLOBALS.height - 100)
    player_pressed_shoot_button
  end

  if GLOBALS.shot_in_progress == false
    click_near_ship = near_ship(x, y, current_player)

    if click_near_ship == "force"
      GLOBALS.mouse_xinitial = x
      GLOBALS.dragging_type = "force"
      GLOBALS.dragging = true
      Lota::Mouse.cursor = GLOBALS.drag_cursor
    elsif click_near_ship == "angle"
      GLOBALS.mouse_xinitial = x
      GLOBALS.dragging_type = "angle"
      GLOBALS.dragging = true
      Lota::Mouse.cursor = GLOBALS.drag_cursor
    end

  end
end

# returns 'force', 'angle', 'no'
def near_ship(x, y, player_n)
  force_offset = 100 * player_n.force / 5

  distance = (((player_n.x - x) ** 2) + ((player_n.y - y) ** 2)) ** 0.5

  if distance < clamp(force_offset, 10, 90)
    "force"
  elsif distance < 100
    "angle"
  else
    "no"
  end
end

# short circuit the love.update function with boolean
def Lota.mousereleased(_x, _y, _button)
  GLOBALS.dragging = false
  Lota::Mouse.cursor = nil
end

# if the mouse is being dragged after clicking, update the values of force or angle
# uses distance from initial click for smoothly
def Lota.update(_dt)
  if GLOBALS.dragging

    GLOBALS.mouse_xcurrent = Lota::Mouse.x

    if GLOBALS.mouse_xinitial != GLOBALS.mouse_xcurrent

      diff = GLOBALS.mouse_xcurrent - GLOBALS.mouse_xinitial

      if GLOBALS.dragging_type == "angle"

        if GLOBALS.turn == 1
          GLOBALS.player1.angle = get_angle(GLOBALS.player1, diff)
        elsif GLOBALS.turn == 2
          GLOBALS.player2.angle = get_angle(GLOBALS.player2, diff)
        end

      elsif GLOBALS.dragging_type == "force"

        if GLOBALS.turn == 1
          GLOBALS.player1.force = get_force(GLOBALS.player1, diff)
        elsif GLOBALS.turn == 2
          GLOBALS.player2.force = get_force(GLOBALS.player2, diff)
        end

      end

      Lota::Graphics.canvas = GLOBALS.canvas
      draw_ui
      Lota::Graphics.canvas = nil

    end
  end

  # if shotInProgress == false then
  #     if keyUp then
  #         player1.force = player1.force * 1.01
  #     end
  # end
end

def get_force(player_n, diff)
  clamp(player_n.force + clamp((diff / 1000.0) ** 3, -0.02, 0.02), 0, 5)
end

def get_angle(player_n, diff)
  angle = player_n.angle + clamp((diff / 200.0) ** 3, -1, 1)
  if angle > 360
    angle -= 360
  elsif angle < 0
    angle += 360
  end

  angle
end

# make the input value never go below min or above max
def clamp(value, min, max)
  value.clamp(min, max)
end
# SPDX-SnippetEnd
