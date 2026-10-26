# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' logic.lua
# (test/fixtures/gravity_wars/logic.lua, lines 1-276), as globals.rb,
# ui.rb, and shoot.rb describe. Lua's math.pow is Ruby's ** and
# math.sqrt Ruby's Math.sqrt, which call the same C functions LuaJIT does,
# and math.abs Ruby's abs. setInitialPositions retries by calling itself
# at the first pair of planets, or planet and ship, too close together,
# then jumping past the rest of its loops (goto done); Ruby's any? walks
# the pairs in the same order and stops at the same one, and the retry
# follows. Lua's fpx, fpy, xDiff, yDiff, vfx, vfy,
# explodeX, explodeY, and distanceFromShot are globals no other function
# reads, so they are Ruby locals, and fpx and fpy Hashes keyed from 1.

#--------------------------------------------------------------------------------------------------
# Code related to creating new game, planets, collision check, and draw shot
#--------------------------------------------------------------------------------------------------
def new_game
  set_initial_positions

  GLOBALS.player1.angle = 0
  GLOBALS.player2.angle = 180

  GLOBALS.player1.last_angle = nil
  GLOBALS.player2.last_angle = nil

  GLOBALS.player1.health = 100
  GLOBALS.player2.health = 100

  Lota::Graphics.canvas = GLOBALS.canvas
  Lota::Graphics.clear
  draw_planets
  draw_ships
  draw_ui
  Lota::Graphics.canvas = nil

  puts("New Game Started")
end

# returns `player1` or `player2` table (object) depending on whose turn it is
def current_player
  if GLOBALS.turn == 1
    GLOBALS.player1
  else
    GLOBALS.player2
  end
end

# Randomize placement of planets & ships
# check for overlap, retry if check fails
def set_initial_positions
  puts("randomizing planets attempt")

  GLOBALS.all_planets = {} # reset whatever we had before first

  # include parameters for max and min planet locations

  # TODO: experiment with mass
  # having the mass depend on radius is less fun - small planets stop mattering
  # mass = (math.pow(allPlanets[i].r,3)/25) -- MASS depends on radius^3 *** this affects speed of drawing

  1.upto(GLOBALS.num_of_planets) do |i|
    GLOBALS.all_planets[i] = Planet.new(
      x: Lota::Math.random(100, GLOBALS.width - 100),
      y: Lota::Math.random(150, GLOBALS.height - 250),
      r: Lota::Math.random(15, 50),
      mass: Lota::Math.random(10, 50) * 10,
    )
  end

  player1 = GLOBALS.player1
  player2 = GLOBALS.player2

  # reposition ships
  player1.x = Lota::Math.random(200, (GLOBALS.width / 2.0) - 100)
  player1.y = Lota::Math.random(200, GLOBALS.height - 200)
  player2.x = Lota::Math.random((GLOBALS.width / 2.0) + 100, GLOBALS.width - 200)
  player2.y = Lota::Math.random(200, GLOBALS.height - 200)

  # TODO - compute distance with square roots - not just x & y distance
  # check for planet overlap
  # check for ship overlapping with planet too
  # space them out by 50 px at least
  retry_needed = 1.upto(GLOBALS.num_of_planets).any? do |i|
    1.upto(GLOBALS.num_of_planets).any? do |j|
      planet_i = GLOBALS.all_planets[i]
      planet_j = GLOBALS.all_planets[j]
      if planet_i.x == planet_j.x && planet_i.y ==
          planet_j.y

        # do nothing
        false
      elsif (planet_i.x - planet_j.x).abs < 40 &&
          (planet_i.y - planet_j.y).abs < 40

        true
      elsif (planet_i.x - player1.x).abs < 90 &&
          (planet_i.y - player1.y).abs < 90

        true
      elsif (planet_i.x - player2.x).abs < 90 &&
          (planet_i.y - player2.y).abs < 90

        true
      else
        false
      end
    end
  end
  set_initial_positions if retry_needed
end

# check collisions with every shot that is drawn
# dims trails after every collision
def collison_check(b)
  # insert code that will set shotInProgress = false if all bullets are gone and end the turn with it

  # whenever the bullet hits the planet - remove from drawing & computing
  1.upto(GLOBALS.num_of_planets) do |i|
    planet = GLOBALS.all_planets[i]
    bullet = GLOBALS.all_bullets[b]
    if Math.sqrt(((planet.x - bullet.x) ** 2) +
                          ((planet.y - bullet.y) ** 2)) <
        planet.r

      # remove the bullet from the playing field
      # as long as it's placed outside the cutoff set in the drawShot()
      # it will not compute!!! no wasted CPU cycles!
      bullet.x = 0
      bullet.y = 0
      bullet.vx = 0
      bullet.vy = 0

      # this dims the trails on every collision -- probably should disable
      # dimTrails()
      Lota::Graphics.canvas = GLOBALS.canvas
      draw_planets # draw planets because a collision overlaps with a planet :(
      Lota::Graphics.canvas = nil
    end
  end

  # grace period when your bullet can't kill you
  if GLOBALS.benign > 50
    did_you_hit_player(GLOBALS.player1, b)
    did_you_hit_player(GLOBALS.player2, b)
    if GLOBALS.turn == 1
      update_health_bar(GLOBALS.player2, GLOBALS.player1, b)
    else
      update_health_bar(GLOBALS.player1, GLOBALS.player2, b)
    end
  end
end

# don't forget `b` the bullet index
def did_you_hit_player(player_n, b)
  bullet = GLOBALS.all_bullets[b]
  if Math.sqrt(((player_n.x - bullet.x) ** 2) +
                      ((player_n.y - bullet.y) ** 2)) < 10

    puts("you hit someone!")

    # only decrease 1 life!
    if GLOBALS.end_of_round == false then player_n.lives = player_n.lives - 1 end

    GLOBALS.end_of_round = true

    player_n.health = 0

    # store location where player is
    explode_x = player_n.x
    explode_y = player_n.y

    # hide player from the board
    player_n.x = -100
    player_n.y = -100

    # explode this location !!!
    explode(explode_x, explode_y)

    if player_n.lives == 0 then puts("GAME OVER, SOMEONE WON!") end
  end
end

# don't forget `b` the bullet index
def update_health_bar(player_n, opponent, b)
  bullet = GLOBALS.all_bullets[b]
  distance_from_shot = Math.sqrt(((player_n.x - bullet.x) ** 2) +
                                     ((player_n.y - bullet.y) ** 2))

  if opponent.health > distance_from_shot
    opponent.health = distance_from_shot
    Lota::Graphics.canvas = GLOBALS.canvas
    draw_ui
    Lota::Graphics.canvas = nil
  end
end

# TODO: figure out a sensible default for resolution of the shot and speed of the shot
# warning: planets with all the small radii may allow bullets to pass through
#          because the shot rosolution is LOW

# TODO: allow shot to be outside the border by at least a little bit
# TODO: include code so it doesn't do the calculation if the shot is too far from border
#       if shot is within bounds of the screen, draw it

# THE MOST IMPORTANT FUNCTION - draws the lines for the shot "b" where b (think "bullet") is the shot name
#
# 1) if shot is outside some boundary, discard it
# 2) if the shot is outside drawing area, compute, but don't draw (TODO: this is not implemented yet)
# 3) if the shot is within screen:
#     a) compute x and y components from each planet on the current bullet (store in fpx & fpy variables)
#     b) sum up all the forces into a single vfx & vfy
#     c) add final force to bullet's initial force
#     d) draw the small segment
#     e) update bullet's 'initial' velocity for next iteration
def draw_shot(b)
  # Variables involved:
  # b - bulletIndex `[b]`

  bullet = GLOBALS.all_bullets[b]
  width = GLOBALS.width

  # (1)
  # set the shot outside if it hits outside the play border
  if bullet.x > width - 10 || bullet.x < 10 || bullet.y >
      width - 10 || bullet.y < 10

    bullet.x = 0
    bullet.y = 0
  end

  # (3)
  if bullet.x < width - 10 && bullet.x > 10 && bullet.y <
      width - 10 && bullet.y > 10

    # array to store forces from each planet to each shot (temp use always)
    fpx = {}
    fpy = {}

    # (a)
    # calculate force of planet on x1 and y1
    1.upto(GLOBALS.num_of_planets) do |i|
      x_diff = GLOBALS.all_planets[i].x - bullet.x
      y_diff = GLOBALS.all_planets[i].y - bullet.y

      fpx[i] = x_diff /
        (Math.sqrt((x_diff * x_diff) + (y_diff * y_diff)) **
                                   3)
      fpy[i] = y_diff /
        (Math.sqrt((x_diff * x_diff) + (y_diff * y_diff)) **
                                   3)
    end

    # reset velocity -- TEMPORARY VARIABLES
    vfx = 0
    vfy = 0

    # (b)
    # for each planet add all forces multiplied by gravity of each planet
    1.upto(GLOBALS.num_of_planets) do |i|
      vfx += fpx[i] * GLOBALS.all_planets[i].mass
    end

    1.upto(GLOBALS.num_of_planets) do |i|
      vfy += fpy[i] * GLOBALS.all_planets[i].mass
    end

    # (c)
    # add initial velocity to the final velocity
    vfx += bullet.vx
    vfy += bullet.vy

    # set velocity of each bullet to its final velocity
    bullet.vx = vfx
    bullet.vy = vfy

    # (d)
    # Draw shot to canvas
    Lota::Graphics.canvas = GLOBALS.canvas
    Lota::Graphics.line(bullet.x, bullet.y,
      bullet.x + vfx, bullet.y + vfy)
    Lota::Graphics.canvas = nil

    # (e)
    bullet.x += vfx
    bullet.y += vfy

  end
end
# SPDX-SnippetEnd
