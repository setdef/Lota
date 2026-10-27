# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' states/game/gamelogic.lua
# (test/fixtures/klele_atoms/states/game/gamelogic.lua, lines 1-414), as
# main.rb describes, by ADR 001's rules: newSource becomes
# Lota::Audio::Source.new (rule 2) with its type a symbol (rule 9),
# love.audio.play Lota::Audio.play, Source:setPitch pitch= (rule 5),
# newCanvas Canvas.new (rule 2), Canvas:renderTo render_to with a block
# (rule 12), love.filesystem.getInfo info (rule 3), and read and write
# Lota::Filesystem's, whose results are Arrays, of which Lua's single
# assignment keeps the first (rule 4).
#
# The logic table is the module GameLogic, whose fields are its
# accessors. The grid and the table of tiles needed to explode are Hashes
# of columns keyed from 1, each a Hash keyed from 1, as Lua's tables are,
# so Lua's #grid is grid.size; each tile, a table of named fields, is a
# Tile. An atom's {x, y, targetx, targety} is an Array, so Lua's v[1] is
# v[0]. The tables of players, indexed from 1 and with holes, are Hashes
# keyed by player, and the colors, from 0, an Array. A saved game's
# string.byte(str, i) is getbyte(i - 1), and string.char a byte's chr.

module GameLogic
  Tile = Struct.new(:player, :atoms, :explode)

  C_GRIDSIZE = 44 # Grid tile size in pixels

  C_ATOMSPEED = 60 # Atom animation speed in pixels per second

  SNDPUT = Lota::Audio::Source.new("sounds/put.wav", :static)

  SNDEXPLODE = Lota::Audio::Source.new("sounds/explode.wav", :static)

  CTILE = Lota::Graphics::Image.new("graphics/tile.png")

  COLORNAMES = %w[Red Blue Green Yellow].freeze

  CHECKTAB = [ # Order of chain reaction checks
    [0, 1], [0, -1], [1, 0], [-1, 0] # Down > Up > Right > Left
  ].freeze

  require "states/game/gameai"

  class << self
    attr_accessor :grid, :critgrid, :animplaying, :bgimg, :winsize, :curplayer, :playertab, :playeratoms,
      :playermoved, :players, :startplayers, :atomstack, :willexplode, :playerwon, :expcount, :paused, :coltab

    def ai = GameAI

    def c_gridsize = C_GRIDSIZE

    def c_atomspeed = C_ATOMSPEED
  end

  def self.get_win_size(w, h) # Get screen/window size based on grid size
    [20 + (w * C_GRIDSIZE), 100 + (h * C_GRIDSIZE)]
  end

  def self.next_player # Set the current player to next player
    GameAI.reset_time
    return if @players < 2

    loop do
      @curplayer += 1
      @curplayer = 1 if @curplayer > 4
      break if @playertab[@curplayer]
    end
  end

  # Put atom(s), set atom tile owner and prepare animations, return true if the tile becomes critical
  def self.put_atom(x, y, newplayer = nil, count = nil)
    midpos = (C_GRIDSIZE / 4.0) + 2
    endpos = (C_GRIDSIZE / 2.0) + 1
    count ||= 1
    if !newplayer
      @grid[x][y].player = @curplayer
    else
      @grid[x][y].player = newplayer
    end
    atomg = @grid[x][y].atoms
    atplayer = @grid[x][y].player
    1.upto(count) do
      if atomg.empty?
        atomg.push([midpos, midpos, midpos, midpos])
      elsif atomg.size == 1
        @animplaying = true
        atomg[0][2] = endpos
        atomg.push([midpos, midpos, 2, midpos])
      elsif atomg.size == 2
        @animplaying = true
        atomg[0][3] = 2
        atomg[1][3] = 2
        atomg.push([midpos, midpos, midpos, endpos])
      elsif atomg.size == 3
        @animplaying = true
        atomg[2][2] = 2
        atomg.push([midpos, endpos, endpos, endpos])
      elsif atomg.size > 3
        atomg.push([
          midpos,
          midpos,
          Lota::Math.random(midpos / 2, 3 * midpos / 2),
          Lota::Math.random(midpos / 2, 3 * midpos / 2),
])
      end
    end
    return true if atplayer > 0 && @grid[x][y].atoms && @grid[x][y].atoms.size >= @critgrid[x][y]

    false
  end

  # Give a position of a nearby critical atom tile or no position (nil) if there are none
  def self.check_surrounding(x, y)
    pmovetab = nil
    CHECKTAB.each do |v|
      nx = x + v[0]
      ny = y + v[1]
      next unless nx >= 1 && nx <= @grid.size && ny >= 1 && ny <= @grid[1].size

      if @grid[nx][ny].player > 0 && @grid[nx][ny].atoms && @grid[nx][ny].atoms.size >= @critgrid[nx][ny]
        pmovetab = [v[0], v[1]]
        break
      end
    end
    pmovetab
  end

  # Blow up a critical atom tile, spread atoms to nearby tiles and show explosion sprite
  def self.explode_atoms(x, y)
    @expcount += 1
    @grid[x][y].explode = 0.3 / [[@expcount, 2000].min / 10.0, 1].max
    atplayer = @grid[x][y].player
    extra = [@grid[x][y].atoms.size - @critgrid[x][y], 0].max
    if y < @grid[1].size
      put_atom(x, y + 1, atplayer, extra + 1)
      extra = 0
    end
    if y > 1
      put_atom(x, y - 1, atplayer, extra + 1)
      extra = 0
    end
    if x < @grid.size
      put_atom(x + 1, y, atplayer, extra + 1)
      extra = 0
    end
    put_atom(x - 1, y, atplayer, extra + 1) if x > 1
    @grid[x][y].player = 0
    @grid[x][y].atoms = []
    Lota::Audio.play(SNDEXPLODE) if @expcount < 2000
  end

  # Place atom on a tile, prepare for explosion if the tile is critical after that, otherwise give control to the
  # next player
  def self.prepare_new_atoms(tx, ty)
    ttpos = [tx, ty]
    @playeratoms[@curplayer] = [@playeratoms[@curplayer], 1].max
    if put_atom(ttpos[0], ttpos[1])
      @willexplode = [ttpos[0], ttpos[1], true]
      @atomstack.push(ttpos)
    else
      next_player
    end
  end

  # Place atoms without checking for critical atoms or invalid positions/player and without animations
  def self.set_atoms_unsafe(x, y, atomcount, player)
    midpos = (C_GRIDSIZE / 4.0) + 2
    endpos = (C_GRIDSIZE / 2.0) + 1
    @grid[x][y].explode = 0
    if atomcount == 0
      @grid[x][y].player = 0
      @grid[x][y].atoms = []
    elsif atomcount == 1
      @grid[x][y].player = player
      @grid[x][y].atoms = [[midpos, midpos, midpos, midpos]]
    elsif atomcount == 2
      @grid[x][y].player = player
      @grid[x][y].atoms = [[2, midpos, 2, midpos], [endpos, midpos, endpos, midpos]]
    elsif atomcount == 3
      @grid[x][y].player = player
      @grid[x][y].atoms = [[2, 2, 2, 2], [endpos, 2, endpos, 2], [midpos, endpos, midpos, endpos]]
    elsif atomcount > 3
      @grid[x][y].player = player
      @grid[x][y].atoms = [
        [2, endpos, 2, endpos],
        [endpos, endpos, endpos, endpos],
        [2, 2, 2, 2],
        [endpos, 2, endpos, 2],
]
      5.upto(atomcount) do
        ax = Lota::Math.random(midpos / 2, 3 * midpos / 2)
        ay = Lota::Math.random(midpos / 2, 3 * midpos / 2)
        @grid[x][y].atoms.push([ax, ay, ax, ay])
      end
    end
  end

  @grid = {} # Atom grid (contains data in format [x][y])

  @critgrid = {} # Stores precalculated amount of atoms required for a tile to become critical

  @animplaying = false # Is an animation playing? If true, no explosions and animations can start

  @bgimg = nil # It will be a background Canvas in-game

  @winsize = [640, 480] # Window size (will be different ingame)

  @curplayer = 1 # Current player

  @playertab = { 1 => true, 2 => true } # Player table (2-4 elements), true - not out, false - out

  @playeratoms = { 1 => 0, 2 => 0 } # Player atom count (2-4 elements), if it is 0 and the player has moved, player is out

  @playermoved = { 1 => false, 2 => false } # Has player moved?

  @players = 2 # Total players playing (1-4)

  @startplayers = 2 # Total player count (including eliminated players)

  @atomstack = [] # Atom split stack

  @willexplode = [1, 1, false] # Will an atom tile explode {x,y,willExplode}

  @playerwon = 0 # 0 if no player won yet

  @expcount = 0 # Explosion count (resets when explosions stop)

  @paused = false # Is the game paused?

  @coltab = [ # table of atom colors by player number
    [0.2, 0.2, 0.2, 1], # only for testing
    [1, 0.2, 0.2, 1], # red
    [0.2, 0.4, 1, 1], # blue
    [0, 1, 0, 1], # green
    [1, 1, 0, 1], # yellow
  ]

  def self.load_all(grid_width, grid_height, pttab) # Reset most of the game state with given values
    @grid = {}
    @critgrid = {}
    1.upto(grid_width) do |x|
      @grid[x] = {}
      @critgrid[x] = {}
      1.upto(grid_height) do |y|
        # {player,atoms,explode} - player is 0 when it's empty, atoms are array of {x,y,targetx,targety} where x
        # and y are 1 to cGRIDSIZE/2, explode is 0 when no explosion
        @grid[x][y] = Tile.new(player: 0, atoms: [], explode: 0)
        @critgrid[x][y] = 4
        @critgrid[x][y] -= 1 if x == 1 || x == grid_width
        @critgrid[x][y] -= 1 if y == 1 || y == grid_height
      end
    end
    @animplaying = false
    @winsize[0], @winsize[1] = get_win_size(grid_width, grid_height)
    @curplayer = -1
    @playertab = {}
    @playeratoms = {}
    @playermoved = {}
    @players = 0
    GameAI.playertab = {}
    GameAI.difficulty = {}
    GameAI.init(self)
    1.upto(4) do |i|
      next unless pttab[i - 1] > 0

      @curplayer = i if @curplayer == -1
      @players += 1
      @playertab[i] = true
      @playeratoms[i] = 0
      @playermoved[i] = false
      if pttab[i - 1] == 9
        @playertab[i] = "dummy"
      elsif pttab[i - 1] > 1
        GameAI.playertab[i] = true
        GameAI.difficulty[i] = pttab[i - 1] - 1
      else
        GameAI.playertab[i] = false
      end
    end
    if @curplayer == -1 || @players < 2
      @winsize[0], @winsize[1] = nil, nil
      State.printmsg("2 or more players required to play!", 3)
      State.change("menu")
      return
    end
    @startplayers = @players
    @atomstack = []
    @willexplode = [1, 1, false]
    @playerwon = 0
    @expcount = 0
    @bgimg = nil
    @paused = false
  end

  def self.clicked_tile(tx, ty, dontcheckai = nil) # Callback called when a tile is clicked by player or AI
    atplayer = @grid[tx][ty].player
    return if atplayer > 0 && atplayer != @curplayer
    return if !dontcheckai && GameAI.playertab[@curplayer]
    return if @players < 2 || @animplaying || @atomstack.size > 0 || @willexplode[2]

    @grid[tx][ty].atoms ||= []
    @expcount = 0
    @playermoved[@curplayer] = true
    Lota::Audio.play(SNDPUT)
    prepare_new_atoms(tx, ty)
  end

  # Game tick - disqualifies players, picks the winner, explodes atoms, checks if the player is valid, makes chain
  # reactions and executes AI thinker
  def self.tick(dt)
    SNDEXPLODE.pitch = 0.5
    SNDPUT.pitch = 0.75
    if @expcount > 20_000
      State.printmsg("More than 20000 simultaneous explosions! Stopping...", 4)
      State.change("menu")
    end
    1.upto(4) do |i|
      v = @playeratoms[i]
      next if v.nil?

      if @playertab[i] && v <= 0 && @playermoved[i]
        @players -= 1
        @playertab[i] = false
      end
    end
    if @players < 2
      winner = (1..4).find { |i| @playertab[i] }
      if winner
        @playerwon = winner
        return
      end
    end
    until @playertab[@curplayer]
      @curplayer += 1
      @curplayer = 1 if @curplayer > 4
    end
    return if @animplaying

    if @willexplode[2]
      tx = @willexplode[0]
      ty = @willexplode[1]
      explode_atoms(tx, ty)
      @willexplode = [1, 1, false]
    elsif @atomstack.size > 0
      # Pop up to 50 positions from stack per frame if they don't cause chain reactions
      1.upto([@atomstack.size, 50].min) do
        ttpos = @atomstack.last
        pmovetab = check_surrounding(ttpos[0], ttpos[1])
        if pmovetab
          ttpos = [ttpos[0] + pmovetab[0], ttpos[1] + pmovetab[1]]
          @willexplode = [ttpos[0], ttpos[1], true]
          @atomstack.push(ttpos)
          break
        else
          @atomstack.pop
          if @atomstack.empty?
            next_player
            break
          end
        end
      end
    elsif GameAI.playertab[@curplayer]
      GameAI.try_move(dt)
    end
  end

  def self.generate_grid(grid_width, grid_height) # Generate the grid background
    @bgimg = Lota::Graphics::Canvas.new(@winsize[0], @winsize[1])
    @bgimg.render_to do
      0.upto(grid_height - 1) do |y|
        0.upto(grid_width - 1) do |x|
          Lota::Graphics.draw(CTILE, 10 + (x * C_GRIDSIZE), 90 + (y * C_GRIDSIZE))
        end
      end
    end
  end

  def self.draw_victory_win(timestr) # Draw victory window and make background darker
    wx, wy = @winsize[0], @winsize[1]
    Lota::Graphics.color = 0, 0, 0, 0.5
    Lota::Graphics.rectangle(:fill, 0, 0, wx, wy)
    Lota::Graphics.color = 0.5, 0.5, 0.5, 1
    msgx, msgy = ((wx - 256) / 2.0).floor, ((wy - 128) / 2.0).floor
    Lota::Graphics.rectangle(:fill, msgx, msgy, 256, 128)
    Lota::Graphics.color = 0, 0, 0, 1
    Lota::Graphics.rectangle(:line, msgx, msgy, 256, 128)
    str = "#{COLORNAMES[@playerwon - 1]} has won!\nTime: #{timestr}\nClick to continue..."
    Lota::Graphics.printf(str, CA.font16, msgx + 8, msgy + 50, 240, :center)
    Lota::Graphics.color = 1, 1, 1, 1
    CA.play_exp = 3
    Lota::Graphics.printf("Victory!", CA.font24, msgx + 8, msgy + 8, 240, :center)
  end

  def self.cai(num, val, aidiff) # For loadGame: convert player AI value to boolean and AI difficulty
    if val == 0
      GameAI.playertab[num] = false
    else
      GameAI.playertab[num] = true
      if val == 1 # Default AI difficulty
        GameAI.difficulty[num] = aidiff
      elsif val <= 4
        GameAI.difficulty[num] = val - 1
      end
    end
  end

  def self.cpst(num, val) # For loadGame: convert player status value to various player variables
    if val == 0
      @playertab[num] = false
      @playermoved[num] = true
      @playeratoms[num] = 0
    elsif val == 1
      @playertab[num] = true
      @playermoved[num] = false
      @playeratoms[num] = 0
    elsif val == 2
      @playertab[num] = true
      @playermoved[num] = true
      @playeratoms[num] = 1
    end
  end

  def self.load_game # Loads the game, returns nil (on failure) or the new game time (on success)
    return nil unless Lota::Filesystem.info("savegame.ksf")

    str = Lota::Filesystem.read("savegame.ksf").first
    Lota::Filesystem.remove("savegame.ksf")
    if !str || str.byteslice(0, 3) != "KSF"
      State.printmsg("Previous save is corrupted!", 2)
      return nil
    end
    grid_width = str.getbyte(3).clamp(7, 30)
    grid_height = str.getbyte(4).clamp(4, 20)
    if str.bytesize != (2 * grid_width * grid_height) + 20
      State.printmsg("Previous save is invalid!", 2)
      return nil
    end
    @winsize[0], @winsize[1] = get_win_size(grid_width, grid_height)
    @playertab = {}
    @playeratoms = {}
    @playermoved = {}
    GameAI.playertab = {}
    GameAI.difficulty = {}
    @startplayers = [str.getbyte(5), 4].min
    @players = [str.getbyte(6), 4].min
    aidifficulty = [str.getbyte(7), 3].min # Only used in 1.1 - 1.2.1 save files
    @curplayer = str.getbyte(8)
    1.upto(4) do |i|
      cpst(i, str.getbyte(8 + i))
      cai(i, str.getbyte(12 + i), aidifficulty)
    end
    next_player if @curplayer == 0 || @curplayer > 4 || @playertab[@curplayer].nil?
    ttime = (str.getbyte(19) * 3600) + (str.getbyte(18) * 60) + str.getbyte(17)
    pos = 0
    @grid = {}
    @critgrid = {}
    1.upto(grid_width) do |x|
      @grid[x] = {}
      @critgrid[x] = {}
      1.upto(grid_height) do |y|
        @grid[x][y] = Tile.new(player: 0, atoms: [], explode: 0)
        set_atoms_unsafe(x, y, str.getbyte(pos + 21), str.getbyte(pos + 20))
        @critgrid[x][y] = 4
        @critgrid[x][y] -= 1 if x == 1 || x == grid_width
        @critgrid[x][y] -= 1 if y == 1 || y == grid_height
        pos += 2
      end
    end
    GameAI.init(self)
    ttime
  end

  def self.set_atoms(...) = set_atoms_unsafe(...)
end
# SPDX-SnippetEnd
