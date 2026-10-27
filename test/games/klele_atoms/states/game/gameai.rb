# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' states/game/gameai.lua
# (test/fixtures/klele_atoms/states/game/gameai.lua, lines 1-191), as
# main.rb and gamelogic.rb describe: the grid is a Hash of columns keyed
# from 1, each a Hash of tiles keyed from 1, as in Lua, and the lists of
# tiles Arrays of [x, y], so Lua's t[1] and t[2] are t[0] and t[1].
# love.math.random becomes Lota::Math.random, which draws from LÖVE's
# generator, so the computer picks the tiles LÖVE's picks.

module GameAI
  C_AIDELAY = 0.3 # AI move delay

  @aitime = 0.0 # Timer for AI (it can only move after cAIDELAY)

  @logic = nil

  @ccdchecktab = {} # Table of diagonally closest tiles to a corner, created every time AI code is initialized

  class << self
    attr_accessor :playertab, :difficulty
  end

  def self.ai_is_tile_enemy(x, y) # Check if a tile belongs to another player
    tplayer = @logic.grid[x][y].player
    (tplayer != 0 && tplayer != @logic.curplayer)
  end

  def self.ai_get_corners(gridx, gridy) # Get how many corners a player has
    corcount = 0
    corcount += 1 if @logic.grid[1][1].player == @logic.curplayer
    corcount += 1 if @logic.grid[gridx][1].player == @logic.curplayer
    corcount += 1 if @logic.grid[1][gridy].player == @logic.curplayer
    corcount += 1 if @logic.grid[gridx][gridy].player == @logic.curplayer
    corcount
  end

  def self.ai_atoms_nearby(x, y) # Check if any atoms are in the nearby tiles
    grid = @logic.grid
    return true if y > 1 && grid[x][y - 1].atoms.size > 0
    return true if y < grid[1].size && grid[x][y + 1].atoms.size > 0
    return true if x > 1 && grid[x - 1][y].atoms.size > 0
    return true if x < grid.size && grid[x + 1][y].atoms.size > 0

    false
  end

  def self.ai_check_advantage(x, y, patoms) # Check if you have advantage over any enemy tile
    grid = @logic.grid
    crit = @logic.critgrid
    return true if y > 1 && ai_is_tile_enemy(x, y - 1) && patoms >= grid[x][y - 1].atoms.size - crit[x][y - 1]
    if y < grid[1].size && ai_is_tile_enemy(x, y + 1) && patoms >= grid[x][y + 1].atoms.size - crit[x][y + 1]
      return true
    end
    return true if x > 1 && ai_is_tile_enemy(x - 1, y) && patoms >= grid[x - 1][y].atoms.size - crit[x - 1][y]
    return true if x < grid.size && ai_is_tile_enemy(x + 1, y) && patoms >= grid[x + 1][y].atoms.size - crit[x + 1][y]

    false
  end

  # Check if enemy or the current player has an undefended corner (1 atom on every side near the corner and no 2
  # atom tile diagonally from the corner)
  def self.ai_corner_check(x, y)
    grid = @logic.grid
    crit = @logic.critgrid
    return false if crit[x][y] > 2

    ccval = 0
    patoms = -2
    ccval += 1 if y > 1 && grid[x][y - 1].player > 0 && patoms >= grid[x][y - 1].atoms.size - crit[x][y - 1]
    if y < grid[1].size && grid[x][y + 1].player > 0 && patoms >= grid[x][y + 1].atoms.size - crit[x][y + 1]
      ccval += 1
    end
    ccval += 1 if x > 1 && grid[x - 1][y].player > 0 && patoms >= grid[x - 1][y].atoms.size - crit[x - 1][y]
    if x < grid.size && grid[x + 1][y].player > 0 && patoms >= grid[x + 1][y].atoms.size - crit[x + 1][y]
      ccval += 1
    end
    cposx, cposy = @ccdchecktab[x][y][0], @ccdchecktab[x][y][1]
    return false if ai_is_tile_enemy(cposx, cposy) && grid[x][y].atoms.size == grid[cposx][cposy].atoms.size - 2

    (ccval >= 2)
  end

  def self.ai_check_pre_crit(x, y) # Check if any nearby enemy tiles are 1 atom before explosion
    grid = @logic.grid
    crit = @logic.critgrid
    return true if y > 1 && ai_is_tile_enemy(x, y - 1) && grid[x][y - 1].atoms.size >= crit[x][y - 1] - 1
    return true if y < grid[1].size && ai_is_tile_enemy(x, y + 1) && grid[x][y + 1].atoms.size >= crit[x][y + 1] - 1
    return true if x > 1 && ai_is_tile_enemy(x - 1, y) && grid[x - 1][y].atoms.size >= crit[x - 1][y] - 1
    return true if x < grid.size && ai_is_tile_enemy(x + 1, y) && grid[x + 1][y].atoms.size >= crit[x + 1][y] - 1

    false
  end

  def self.ai_get_special_tiles(difficulty) # Make a list of available tiles, avoided tiles and "special" tiles
    grid = @logic.grid
    sptiles = [] # Special tiles
    advtiles = [] # Advantage tiles
    tiles = [] # All available tiles
    natiles = [] # Tiles without avoided ones
    gridx = grid.size # Grid width
    gridy = grid[1].size # Grid height
    was_sp_corner = false # Was any tile a special corner
    was_adv_corner = false # Was any tile an advantage corner
    corners = [] # Corner tiles
    cornercount = ai_get_corners(gridx, gridy)
    1.upto(gridx) do |x|
      1.upto(gridy) do |y|
        next unless grid[x][y].player == @logic.curplayer || grid[x][y].player == 0 # If tile is clickable by the player

        is_sp_tile = false
        tile_avoided = false
        tiles.push([x, y]) # Tile is valid
        natiles.push([x, y])
        if difficulty == 2 # Medium difficulty
          if ai_check_pre_crit(x, y) # Check if any nearby tiles will explode after 1 atom is added
            if grid[x][y].atoms.size == (@logic.critgrid[x][y] - 1) # If your tile will do it as well, focus on it
              sptiles.push([x, y])
              is_sp_tile = true
            else # Otherwise, avoid it
              natiles.pop
              tile_avoided = true
            end
          end
        elsif difficulty == 3 # Hard (at least it's supposed to be)
          is_corner = (x == 1 || x == gridx) && (y == 1 || y == gridy)
          atomcount = grid[x][y].atoms.size
          if is_corner && atomcount == 1 && !ai_atoms_nearby(x, y) # Avoid exploding corners when no atoms are nearby
            natiles.pop
            tile_avoided = true
          elsif ai_check_pre_crit(x, y) # Otherwise the same as in difficulty 2
            if grid[x][y].atoms.size == (@logic.critgrid[x][y] - 1)
              sptiles.push([x, y])
              is_sp_tile = true
            else
              natiles.pop
              tile_avoided = true
            end
          end
          is_advantage = false
          # Check for any atom advantage in the tile
          is_advantage = ai_check_advantage(x, y, atomcount - @logic.critgrid[x][y]) unless is_sp_tile
          # If corner tile is not avoided and the player either has no corners or the corner spot is undefended,
          # focus on it
          if !tile_avoided && (cornercount == 0 || ai_corner_check(x, y)) && is_corner
            if was_sp_corner && is_sp_tile # If any corner was special, only focus on special corners
              corners.push([x, y])
            elsif was_adv_corner # If any corner had an advantage, only focus on advantageous and special corners
              if is_sp_tile
                corners = []
                was_sp_corner = true
              end
              corners.push([x, y])
            else
              if is_sp_tile
                corners = []
                was_sp_corner = true
              elsif is_advantage
                corners = []
                was_adv_corner = true
              end
              # Unless there's an advantage or it's a special tile, don't explode corner
              corners.push([x, y]) if atomcount == 0 || is_sp_tile || is_advantage
            end
          elsif is_advantage && !is_corner && !tile_avoided # Add advantage tiles
            advtiles.push([x, y])
          end
        end
      end
    end
    # First priority: corners (only if none are claimed by the player or they're strategically important)
    if corners.size > 0
      sptiles = corners
    # Second priority: special tiles, third priority: advantage tiles (difficulty 3 only)
    elsif sptiles.empty? && advtiles.size > 0
      sptiles = advtiles
    end
    # If there are any tiles except avoided ones choose only them, otherwise choose any available tile
    tiles = natiles if natiles.size > 0
    [sptiles, tiles]
  end

  def self.ai_thinker # Pick a tile and use the clickedTile() function
    tx = 0
    ty = 0
    # Easy - just pick a random tile, Normal and Hard - more advanced strategies, not too advanced for optimization
    # reasons
    unless @difficulty[@logic.curplayer] <= 3
      raise "Incorrect AI difficulty - #{@difficulty[@logic.curplayer]}"
    end

    sptiles, tiles = ai_get_special_tiles(@difficulty[@logic.curplayer])
    if sptiles.size > 0
      rindex = Lota::Math.random(1, sptiles.size)
      tx = sptiles[rindex - 1][0]
      ty = sptiles[rindex - 1][1]
    else
      rindex = Lota::Math.random(1, tiles.size)
      tx = tiles[rindex - 1][0]
      ty = tiles[rindex - 1][1]
    end
    @logic.clicked_tile(tx, ty, true) # Simulate clicking the chosen tile
  end

  @playertab = { 1 => false, 2 => false }

  @difficulty = { 1 => 2, 2 => 2, 3 => 2, 4 => 2 }

  def self.init(logictab) # Initialize AI
    @logic = logictab
    gridw = @logic.grid.size
    gridh = @logic.grid[1].size
    @ccdchecktab = {
      1 => { 1 => [2, 2], gridh => [2, gridh - 1] },
      gridw => { 1 => [gridw - 1, 2], gridh => [gridw - 1, gridh - 1] },
    }
  end

  def self.reset_time # Reset AI delay timer
    @aitime = 0.0
  end

  def self.try_move(dt) # Execute thinker if no more delay is required
    @aitime += dt
    ai_thinker if @aitime >= C_AIDELAY
  end
end
# SPDX-SnippetEnd
