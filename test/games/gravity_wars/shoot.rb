# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' shoot.lua
# (test/fixtures/gravity_wars/shoot.lua, lines 1-202), as globals.rb and
# ui.rb describe. math.random becomes Lota::Math.random, which draws from
# LÖVE's own generator, as love.math.random does (Plan 001, "Random
# numbers"); Lua's math.cos and math.sin are Ruby's Math.cos and Math.sin.
# Lota::Math.random returns whole bounds' numbers as Integers, so
# setExplodyColor divides by 255.0, as globals.rb divides whole numbers.
# Lua's temp, randX, randY, and radius are globals no other function
# reads, so they are Ruby locals. split is never called, and would fail in
# Lua as in Ruby, since it assigns the fields of bullets it never made.

#--------------------------------------------------------------------------------------------------
# Code related to shooting bullets
#--------------------------------------------------------------------------------------------------
# this function sets the initial velocities for each bullet
# it doesn't shoot - it relies on the "drawShot" function to continue
#
# f - force            additional to player's chosen force,
# t - theta (angle)    additional to player's chosen angle,
# bulletIndex - index of the bullet
def set_bullet_initial_velocity(f, t, bullet_index)
  if GLOBALS.turn == 1
    # preturb it by a bit for jitter so it's not the same
    f = GLOBALS.player1.force + f # + math.random() * 2
    t = GLOBALS.player1.angle + t # + math.random() * 10
  elsif GLOBALS.turn == 2
    f = GLOBALS.player2.force + f # + math.random() * 2
    t = GLOBALS.player2.angle + t # + math.random() * 10
  end

  # *** REDUCE THE FORCE BY some amount and reduce weight of planets by some amount
  # *** this will make the resolution of the shot higher!!?! ***
  f /= 2.0

  # calculate the x and y components of shot for initial force
  GLOBALS.all_bullets[bullet_index].vx = f * Math.cos(0.0174533 * t)
  GLOBALS.all_bullets[bullet_index].vy = f * Math.sin(0.0174533 * t)
end

# to split a bullet (special bullet type allows for splitting while in air)
def split(x, y)
  Lota::Graphics.ellipse(:line, x, y, 10, 10)

  # print("SPLIT @ ", x, y)

  1.upto(3) do |i|
    temp = GLOBALS.num_of_bullets + i
    GLOBALS.all_bullets[i] = Bullet.new
    GLOBALS.all_bullets[temp].x = x
    GLOBALS.all_bullets[temp].y = y
  end

  GLOBALS.num_of_bullets = GLOBALS.num_of_bullets + 3

  1.upto(3) do |i|
    temp = GLOBALS.num_of_bullets - 3 + i
    set_bullet_initial_velocity(0.01, Lota::Math.random(0, 360), temp)
  end
end

def shot_type1
  # shoot only one bullet
  GLOBALS.num_of_bullets = 1

  1.upto(GLOBALS.num_of_bullets) do |i|
    GLOBALS.all_bullets[i] = Bullet.new
    GLOBALS.all_bullets[i].x = GLOBALS.ship_x
    GLOBALS.all_bullets[i].y = GLOBALS.ship_y
    set_bullet_initial_velocity(1, 1, i)
  end
end

def shot_type2
  # shoot three bullets
  GLOBALS.num_of_bullets = 30

  1.upto(GLOBALS.num_of_bullets) do |i|
    GLOBALS.all_bullets[i] = Bullet.new
    GLOBALS.all_bullets[i].x = GLOBALS.ship_x
    GLOBALS.all_bullets[i].y = GLOBALS.ship_y
    set_bullet_initial_velocity(1, 1, i)
  end
end

def shot_type3
  # shoot five bullets
  GLOBALS.num_of_bullets = 5

  1.upto(GLOBALS.num_of_bullets) do |i|
    GLOBALS.all_bullets[i] = Bullet.new
    GLOBALS.all_bullets[i].x = GLOBALS.ship_x
    GLOBALS.all_bullets[i].y = GLOBALS.ship_y
    set_bullet_initial_velocity(1, 1, i)
  end
end

def shot_type4
  # shoot only one bullet
  GLOBALS.num_of_bullets = 1

  1.upto(GLOBALS.num_of_bullets) do |i|
    GLOBALS.all_bullets[i] = Bullet.new
    GLOBALS.all_bullets[i].x = GLOBALS.ship_x
    GLOBALS.all_bullets[i].y = GLOBALS.ship_y
    set_bullet_initial_velocity(1, 1, i)
  end
end

def player_pressed_shoot_button
  dim_trails

  puts(["Whose is shooting? Player ", GLOBALS.turn].join("\t"))

  # origin of the shot set to player's location
  if GLOBALS.turn == 1
    GLOBALS.ship_x = GLOBALS.player1.x
    GLOBALS.ship_y = GLOBALS.player1.y
    GLOBALS.player1.last_angle = GLOBALS.player1.angle
    GLOBALS.player1.last_force = GLOBALS.player1.force
  elsif GLOBALS.turn == 2
    GLOBALS.ship_x = GLOBALS.player2.x
    GLOBALS.ship_y = GLOBALS.player2.y
    GLOBALS.player2.last_angle = GLOBALS.player2.angle
    GLOBALS.player2.last_force = GLOBALS.player2.force
  end

  GLOBALS.all_bullets = {} # reset to empty

  # make bullet benign
  GLOBALS.benign = 0

  if GLOBALS.bul_type == 1
    shot_type1
  elsif GLOBALS.bul_type == 2
    shot_type2
  elsif GLOBALS.bul_type == 3
    shot_type3
  elsif GLOBALS.bul_type == 4
    shot_type4
  else
    1.upto(GLOBALS.num_of_bullets) do |i|
      GLOBALS.all_bullets[i] = Bullet.new
      GLOBALS.all_bullets[i].x = GLOBALS.ship_x
      GLOBALS.all_bullets[i].y = GLOBALS.ship_y
      set_bullet_initial_velocity(2, 2, i)
    end
  end

  Lota::Graphics.canvas = GLOBALS.canvas
  draw_ui
  Lota::Graphics.canvas = nil

  GLOBALS.shot_in_progress = true
end

# blow up a location in a pretty way
def explode(x, y)
  Lota::Graphics.canvas = GLOBALS.canvas

  1.upto(10) do |i|
    temp = GLOBALS.num_of_bullets + i
    GLOBALS.all_bullets[temp] = Bullet.new

    rand_x = Lota::Math.random(-20, 20)
    rand_y = Lota::Math.random(-20, 20)

    radius = Lota::Math.random(5, 15)
    set_explody_color
    Lota::Graphics.ellipse(:fill, x + rand_x, y + rand_y, radius, radius)

    GLOBALS.all_bullets[temp].x = x + rand_x
    GLOBALS.all_bullets[temp].y = y + rand_y
  end

  Lota::Graphics.canvas = nil

  GLOBALS.num_of_bullets = GLOBALS.num_of_bullets + 10

  1.upto(10) do |i|
    temp = GLOBALS.num_of_bullets - 10 + i
    set_bullet_initial_velocity(1, Lota::Math.random(0, 360), temp)
  end
end

def set_explody_color
  # red     1    0     0
  # orange  1    0.5   0
  # yellow  1    1     0

  Lota::Graphics.color = 1, Lota::Math.random(0, 255) / 255.0, 0, 1
end
# SPDX-SnippetEnd
