# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' states/game/gamestate.lua
# (test/fixtures/klele_atoms/states/game/gamestate.lua, lines 1-232), as
# main.rb and gamelogic.rb describe: newImage becomes Image.new and
# newQuad Quad.new (rule 2), Texture:getDimensions dimensions (rules 3
# and 4), love.timer.getDelta Lota::Timer.delta (rule 3), setColor a
# writer (rules 5 and 6), and the draw modes, the alignment, and the keys
# symbols (rule 9). The quads, indexed from 1, are an Array, so Lua's
# ailevelquads[ailevel] is ailevelquads[ailevel - 1]. string.format's
# %0.2d is Ruby's format.

module GameState
  CATOM = Lota::Graphics::Image.new("graphics/atom.png")

  CEXPLODE = Lota::Graphics::Image.new("graphics/explode.png")

  CPLAYER = Lota::Graphics::Image.new("graphics/player.png")

  CPLAYERAI = Lota::Graphics::Image.new("graphics/playerai.png") # AI player sprite (without bars)

  CPLAYERAI2 = Lota::Graphics::Image.new("graphics/playerai2.png") # AI difficulty bars

  AILEVELQUADS = [ # Quads for drawing only a part of cplayerai2 texture depending on AI difficulty
    Lota::Graphics::Quad.new(0, 0, 10, 50, *CPLAYERAI2.dimensions), # Easy (AI 1)
    Lota::Graphics::Quad.new(0, 0, 14, 50, *CPLAYERAI2.dimensions), # Medium (AI 2)
    Lota::Graphics::Quad.new(0, 0, 18, 50, *CPLAYERAI2.dimensions), # Hard (AI 3)
  ].freeze

  CBACK = Lota::Graphics::Image.new("graphics/back.png")

  require "states/game/gamelogic"

  require "states/game/gametut"

  require "states/game/gamepause"

  @restarttime = 0.0 # In-game timer

  @exiting = nil # If the exit button is clicked, it stores a mouse button

  @pausing = false # Will the game pause next turn?

  @tutorial = false # Is tutorial active?

  def self.get_game_time
    format("%0.2d:%0.2d", (@restarttime / 60).floor, (@restarttime % 60).floor)
  end

  def self.pause_game
    if @tutorial
      State.change("menu")
      return false
    end
    if GameLogic.atomstack.size > 0 || GameLogic.animplaying
      @pausing = true
      State.printmsg("Pausing...", 0.1)
      return false
    end
    @pausing = false
    GamePause.init(GameLogic, @restarttime)
    true
  end

  def self.init(_laststate, argtab = nil)
    @exiting = nil
    @pausing = false
    @tutorial = false
    @restarttime = 0.0
    ttime = nil
    CA.play_exp = [CA.play_exp, 2].max
    if argtab && argtab[0] == "tutorial"
      @tutorial = true
      GameLogic.load_all(10, 6, [9, 9, 9, 9])
      GameTut.init(GameLogic)
    else
      GameLogic.load_all(CA.grid_w, CA.grid_h, [CA.player1, CA.player2, CA.player3, CA.player4])
      ttime = GameLogic.load_game
    end
    if ttime
      @restarttime = ttime
      State.printmsg("Saved game loaded.", 2)
    end
    [GameLogic.winsize[0], GameLogic.winsize[1]]
  end

  def self.update(dt)
    GameLogic.generate_grid(GameLogic.grid.size, GameLogic.grid[1].size) unless GameLogic.bgimg
    if GameLogic.paused
      GamePause.update(dt)
    elsif GameLogic.playerwon == 0
      return if @pausing && pause_game

      @restarttime += dt
      return if @tutorial && GameTut.update(dt)

      GameLogic.tick(dt)
    end
  end

  # Draw all stuff, move animated atoms and calculate atom count for each player
  def self.draw
    dt = Lota::Timer.delta
    mspeed = GameLogic.c_atomspeed * dt * [[GameLogic.expcount, 2000].min / 10.0, 1].max # move speed (in pixels)
    GameLogic.animplaying = false
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.draw(GameLogic.bgimg) if GameLogic.bgimg
    1.upto(4) do |i|
      GameLogic.playeratoms[i] = 0
    end
    k = 0
    1.upto(4) do |i|
      v = GameLogic.playertab[i]
      next if v.nil?

      k += 1
      ypos = 20
      xpos = ((k * GameLogic.winsize[0] / (GameLogic.startplayers + 1).to_f) - 12).floor
      if !v
        Lota::Graphics.color = 0.5, 0.5, 0.5, 1
      elsif GameLogic.curplayer == i
        Lota::Graphics.color = 1, 1, 1, 1
        Lota::Graphics.rectangle(:fill, xpos - 2, ypos - 2, 29, 54)
        Lota::Graphics.color = GameLogic.coltab[i]
      else
        Lota::Graphics.color = GameLogic.coltab[i]
      end
      if GameLogic.ai.playertab[i]
        ailevel = GameLogic.ai.difficulty[i]
        Lota::Graphics.draw(CPLAYERAI, xpos, ypos)
        Lota::Graphics.color = 1, 1, 1, 1
        Lota::Graphics.draw(CPLAYERAI2, AILEVELQUADS[ailevel - 1], xpos, ypos)
      else
        Lota::Graphics.draw(CPLAYER, xpos, ypos)
      end
    end
    grid = GameLogic.grid
    gridsize = GameLogic.c_gridsize
    1.upto(grid.size) do |x|
      1.upto(grid[1].size) do |y|
        atomg = grid[x][y].atoms
        plcolor = grid[x][y].player
        if grid[x][y].explode > 0 # Atom is exploding
          GameLogic.animplaying = true
          grid[x][y].explode = [grid[x][y].explode - dt, 0].max
          Lota::Graphics.color = 1, 1, 1, 1
          qgridsize = 19 * gridsize / 64.0
          Lota::Graphics.draw(CEXPLODE, 10 + ((x - 1) * gridsize) + qgridsize, 90 + ((y - 1) * gridsize) + qgridsize)
        elsif plcolor >= 0 && atomg # Atoms are present, animate atoms if needed
          atomg.each do |v|
            xdist = (v[0] - v[2]).abs
            ydist = (v[1] - v[3]).abs
            if xdist > 0 || ydist > 0
              GameLogic.animplaying = true
              xdir = v[2] - v[0]
              ydir = v[3] - v[1]
              if xdir > 0
                xdir = 1
              elsif xdir < 0
                xdir = -1
              end
              if ydir > 0
                ydir = 1
              elsif ydir < 0
                ydir = -1
              end
              xstep = [xdist, mspeed].min * xdir
              ystep = [ydist, mspeed].min * ydir
              v[0] += xstep
              v[1] += ystep
            end
            xpos = 10 + ((x - 1) * gridsize) + v[0]
            ypos = 90 + ((y - 1) * gridsize) + v[1]
            Lota::Graphics.color = GameLogic.coltab[plcolor]
            Lota::Graphics.draw(CATOM, xpos, ypos, 0, 0.5)
          end
          # Calculate player atoms
          if plcolor > 0 && plcolor <= 4 && !GameLogic.playertab[plcolor].nil?
            GameLogic.playeratoms[plcolor] += grid[x][y].atoms.size
          end
        end
      end
    end
    if GameLogic.playerwon != 0
      GameLogic.draw_victory_win(get_game_time)
      return
    end
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.printf(get_game_time, CA.font16, 0, 0, GameLogic.winsize[0] - 2, :right)
    GameTut.draw if @tutorial
    Lota::Graphics.draw(CBACK, 2, 2)
    GamePause.draw if GameLogic.paused
  end

  def self.keyreleased(key)
    if @restarttime >= 0.3
      if key == :m
        State.change("menu")
      elsif key == :escape && GameLogic.playerwon == 0 && !GameLogic.paused
        pause_game
      end
    end
    GameTut.keyreleased(key) if @tutorial
    GamePause.keyreleased(key) if GameLogic.paused
  end

  def self.mousepressed(x, y, button)
    gw = GameLogic.grid.size
    gh = GameLogic.grid[1].size
    gridsize = GameLogic.c_gridsize
    if GameLogic.playerwon != 0 || (x >= 0 && x <= 44 && y >= 0 && y <= 44)
      @exiting = button
    elsif @tutorial && GameTut.mousepressed(x, y, button)
      nil
    elsif GameLogic.paused
      GamePause.mousepressed(x, y, button)
    elsif x >= 10 && x < 10 + (gw * gridsize) && y >= 90 && y < 90 + (gh * gridsize)
      pressx = ((x - 10) / gridsize.to_f).floor + 1
      pressy = ((y - 90) / gridsize.to_f).floor + 1
      GameLogic.clicked_tile(pressx, pressy)
    end
  end

  def self.mousereleased(x, y, button)
    if GameLogic.paused
      GamePause.mousereleased(x, y, button)
      return
    end
    return unless @exiting == button

    if GameLogic.playerwon == 0
      @exiting = nil
      pause_game
    else
      State.change("menu")
    end
  end

  def self.fullscreen(is_fullscreen)
    GameLogic.bgimg = nil
    GamePause.fullscreen(is_fullscreen) if GameLogic.paused
  end

  def self.resize(_x, _y)
    fullscreen(CA.full_screen)
  end
end
# SPDX-SnippetEnd
